"""k8s-local-lab 샘플 FastAPI 애플리케이션.

이 파일의 역할:
    - 쿠버네티스 프로브(probe)용 헬스체크 엔드포인트(/healthz, /readyz)와
      서비스 정보 엔드포인트(/)를 제공한다.
    - Dockerfile의 CMD("uvicorn main:app ...")가 이 파일의 `app` 객체를 실행한다.

이 파일과 연결된 것들:
    - /healthz → manifests/app/deployment.yml의 livenessProbe + Dockerfile HEALTHCHECK
    - /readyz  → manifests/app/deployment.yml의 readinessProbe
    - 설정값   → core/config.py의 Settings (환경 변수는 configmap.yml/secret.yml에서 주입)

SEEMEDI 백엔드 표준 적용: KST 타임존, 구조화 로깅, RFC 9457 에러 형식.
"""

import logging
import socket
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

# 설정 객체 — 환경 변수(ConfigMap/Secret에서 주입)를 읽어 만들어진다.
# 상세 동작은 core/config.py 주석 참고.
from core.config import settings

# KST 타임존 객체 (UTC+9) — SMEDI 표준: 모든 시각 표기는 한국 시간.
# 아래 root() 응답의 timestamp가 이 타임존으로 출력된다.
KST = timezone(timedelta(hours=9))

# ── 로깅 설정 ────────────────────────────────────────────────────────────────
# DevOps 관점: 컨테이너 앱의 로그는 파일이 아니라 표준 출력(stdout)으로 남긴다.
# 쿠버네티스가 stdout을 수집해 `kubectl logs`(make logs)로 볼 수 있게 해주기 때문.
# (참고: docs/04-usage-guide.md — 2. 로그 확인)
logging.basicConfig(
    # 로그 레벨을 환경 변수(LOG_LEVEL, configmap.yml)에서 가져온다.
    # getattr 3번째 인자(INFO): 잘못된 값이 들어와도 죽지 않고 INFO로 동작 (안전 기본값)
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    # 로그 한 줄 형식: 시각 [레벨] 로거이름: 메시지
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",  # ISO 8601 형식의 타임스탬프
)
logger = logging.getLogger(settings.app_name)  # 앱 이름을 로거 이름으로 사용


# ── 앱 수명주기(lifespan) 훅 ────────────────────────────────────────────────
# 앱 시작 직후와 종료 직전에 실행할 코드를 정의한다.
# yield 이전 = 시작 시 (DB 연결 풀 생성 등을 여기서 한다),
# yield 이후 = 종료 시 (연결 정리 등 — 쿠버네티스가 Pod를 내릴 때 실행됨).
# DevOps 관점: 시작/종료 로그가 있으면 `kubectl logs`로 "언제 재시작됐는지"를
# 추적할 수 있다 — CrashLoopBackOff 디버깅의 기본 단서.
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("[startup] %s %s started (env=%s)",
                settings.app_name, settings.app_version, settings.environment)
    yield  # ← 이 지점에서 앱이 실행되며 요청을 처리한다
    logger.info("[shutdown] %s stopped", settings.app_name)


# FastAPI 앱 본체 — Dockerfile CMD의 "main:app"이 가리키는 객체.
# title/version은 자동 생성되는 API 문서(/docs)에 표시된다.
app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    lifespan=lifespan,
)


# ── 전역 예외 처리기 (RFC 9457 problem+json 형식) ──────────────────────────
# 어떤 엔드포인트에서든 처리되지 않은 예외가 나면 이 함수가 받아서
# 표준화된 에러 JSON으로 응답한다.
# DevOps 관점에서 왜 필요한가?
#   - 스택트레이스(내부 코드 구조)가 사용자에게 노출되는 것을 막는다 (보안)
#   - 에러 응답 형식을 RFC 9457 표준으로 통일하면, 모니터링/클라이언트가
#     어떤 서비스의 에러든 같은 방식으로 파싱할 수 있다 (SMEDI 표준)
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    # 에러는 반드시 로그로 남긴다 — 사용자에게는 감추고, 운영자는 볼 수 있게
    logger.error("[error] %s %s — %s", request.method, request.url.path, str(exc))
    return JSONResponse(
        status_code=500,
        content={
            "type": "about:blank",              # 에러 유형 URI (특정 없음 = about:blank)
            "title": "Internal Server Error",   # 사람이 읽는 에러 제목
            "status": 500,                      # HTTP 상태 코드 (본문에도 중복 표기가 표준)
            "detail": "서버 내부 오류가 발생했습니다.",  # 사용자용 설명 (내부 정보 노출 금지)
            "instance": str(request.url.path),  # 에러가 발생한 경로
        },
    )


# ── 엔드포인트 ──────────────────────────────────────────────────────────────

@app.get("/healthz")
async def healthz():
    """Liveness probe — "앱 프로세스가 살아 있는가?"만 확인.

    호출자:
        - 쿠버네티스 livenessProbe (manifests/app/deployment.yml) — 10초마다 호출,
          3연속 실패 시 Pod를 재시작한다
        - Docker HEALTHCHECK (app/Dockerfile)

    주의: 여기서 DB 등 외부 의존성을 검사하면 안 된다.
    DB가 잠깐 느려진 것뿐인데 앱 Pod가 전부 재시작되는 연쇄 장애가 나기 때문.
    "프로세스 생존"만 답하는 것이 원칙이다.
    """
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    """Readiness probe — "지금 트래픽을 받아도 되는가?"를 확인.

    호출자:
        - 쿠버네티스 readinessProbe (manifests/app/deployment.yml) — 5초마다 호출,
          실패하면 Pod를 재시작하지 않고 Service의 분배 대상에서만 제외한다

    liveness와의 차이 (중요):
        - liveness 실패 → 재시작 (프로세스가 죽었다고 판단)
        - readiness 실패 → 트래픽 차단만 (아직 준비가 안 됐다고 판단)

    실제 프로덕션에서는 여기서 DB 연결 등을 확인한다
    (예: database/configmap.yml이 만든 health_check 테이블 SELECT).
    지금은 학습용이라 더미 값을 반환한다.
    """
    return {"status": "ok", "db": "connected"}


@app.get("/")
async def root():
    """서비스 정보 엔드포인트 — 배포 확인용.

    curl http://localhost:8000/ (또는 http://app.localhost/) 응답으로
    "지금 어떤 버전이, 어떤 환경 설정으로, 어느 Pod에서" 돌고 있는지 즉시 확인한다.
    특히 hostname은 Pod 이름이므로, 여러 번 호출하면 값이 번갈아 나오는 것으로
    Service의 로드밸런싱(2개 Pod 분산)을 눈으로 확인할 수 있다.
    """
    return {
        "service": settings.app_name,                # ConfigMap의 APP_NAME
        "version": settings.app_version,             # ConfigMap의 APP_VERSION
        "environment": settings.environment,         # ConfigMap의 ENVIRONMENT (local/prod 구분)
        "hostname": socket.gethostname(),            # 컨테이너 호스트명 = 쿠버네티스 Pod 이름
        "timestamp": datetime.now(KST).isoformat(),  # 현재 시각 (KST, SMEDI 표준)
    }
