# ============================================================================
# [Dockerfile] — FastAPI 샘플 앱을 Docker 이미지로 만드는 설계도
#
# Dockerfile이란?
#   - "이 앱을 어떤 OS에, 무엇을 설치해서, 어떻게 실행할지"를 적은 레시피.
#   - `docker build`(make build)가 이 파일을 위에서부터 한 줄씩 실행해
#     이미지를 만든다. 각 줄이 하나의 "레이어(층)"로 저장된다.
#
# 이 파일이 미치는 영향:
#   - 여기서 만든 이미지(sample-app:local)를 manifests/app/deployment.yml이 실행한다.
#   - 여기서 만든 사용자 UID(1001)를 deployment.yml의 securityContext가 참조한다.
#   - EXPOSE한 8000 포트를 deployment.yml(containerPort), service.yml(targetPort)이 참조한다.
#
# 적용된 컨벤션 (ai-ops-harness /dockerfile 스킬 표준):
#   - Multi-stage build: 빌드 도구는 최종 이미지에서 제외 → 이미지 축소 + 공격면 감소
#   - 최소 베이스(python:3.12-slim) + 버전 고정(:latest 금지 — 재현성 보장)
#   - Non-root 사용자 실행 (보안: 컨테이너 탈취 시 피해 최소화)
#   - HEALTHCHECK 포함 (Docker 단독 실행 시에도 상태 확인 가능)
#   - 레이어 캐시 활용: 의존성 먼저, 소스는 나중에 (아래 COPY 순서 주석 참고)
# ============================================================================

# ── Stage 1: Builder — 의존성 설치 전용 임시 작업장 ─────────────────────────
# 이 스테이지는 최종 이미지에 포함되지 않는다. pip 캐시, 빌드 부산물 등
# "실행에 불필요한 것들"을 여기 격리하는 것이 multi-stage의 핵심이다.

# 베이스 이미지: 공식 Python 3.12의 slim 변형 (풀버전 대비 수백 MB 작음).
# AS builder: 이 스테이지에 이름을 붙여 아래에서 --from=builder로 참조한다.
FROM python:3.12-slim AS builder

# 이후 명령들의 작업 디렉토리 (없으면 자동 생성)
WORKDIR /build

# 의존성 목록만 먼저 복사한다. 소스 코드보다 먼저 복사하는 이유(레이어 캐시):
# Docker는 이전 빌드와 입력이 같은 줄은 캐시를 재사용한다.
# requirements.txt가 안 바뀌면 아래 pip install 전체를 건너뛰므로,
# "소스만 고친" 일상적인 재빌드가 수 초 만에 끝난다.
COPY requirements.txt .

# 패키지 설치:
#   --no-cache-dir     : pip 다운로드 캐시를 남기지 않음 (이미지 용량 절약)
#   --prefix=/install  : 패키지를 /install 아래에 격리 설치
#                        → Stage 2에서 이 폴더만 쏙 복사해가기 위함
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime — 실제로 배포되는 최종 이미지 ─────────────────────────
# 깨끗한 베이스에서 다시 시작해, 실행에 필요한 것만 담는다.
FROM python:3.12-slim AS runtime

# 타임존을 KST로 설정 (SMEDI 표준) — 컨테이너 안의 시각/로그가 한국 시간이 된다.
# manifests/app/configmap.yml의 TZ=Asia/Seoul과 이중으로 보장하는 구조.
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 전용 비루트 사용자 생성 (보안 — 최소 권한 원칙):
#   - 컨테이너가 해킹당해도 root가 아니면 시스템 훼손 범위가 제한된다
#   - UID/GID 1001은 deployment.yml의 securityContext(runAsUser: 1001)와
#     반드시 일치해야 한다. 불일치하면 runAsNonRoot 검증에 걸려 Pod가 안 뜬다.
#   - --no-create-home: 홈 디렉토리 불필요 (용량/공격면 절약)
RUN groupadd --gid 1001 appuser && \
    useradd --uid 1001 --gid 1001 --no-create-home appuser

# 앱 실행 디렉토리
WORKDIR /app

# Stage 1(builder)의 /install에 설치해둔 패키지들을 파이썬 표준 경로(/usr/local)로 복사.
# 결과: pip도, 빌드 캐시도 없이 "설치된 패키지만" 최종 이미지에 들어온다.
COPY --from=builder /install /usr/local

# 애플리케이션 소스 복사 (src/ 내용물 → /app).
# 의존성 레이어 뒤에 두었으므로 소스 수정 시 이 줄부터만 다시 빌드된다.
# 불필요한 파일(.venv, __pycache__ 등)은 .dockerignore가 걸러준다.
COPY src/ ./

# 이 지점부터 모든 프로세스가 appuser 권한으로 실행된다.
# (USER 선언 전의 RUN들은 root로 실행 — 사용자 생성/시스템 설정에 필요했기 때문)
USER appuser

# "이 컨테이너는 8000 포트를 사용한다"는 문서화 선언.
# 실제 포트 개방은 쿠버네티스(containerPort/Service)가 담당하지만,
# 사람과 도구가 포트를 알 수 있도록 명시하는 것이 관례다.
EXPOSE 8000

# Docker 수준의 자체 상태 검사 — /healthz(app/src/main.py)를 주기적으로 호출한다.
#   --interval=10s     : 10초마다 검사
#   --timeout=3s       : 3초 내 응답 없으면 실패
#   --start-period=5s  : 시작 후 5초간은 실패해도 봐줌 (기동 시간)
#   --retries=3        : 3연속 실패 시 "unhealthy" 판정
# 쿠버네티스에서는 livenessProbe(deployment.yml)가 이 역할을 대신하지만,
# `docker run` 단독 실행 시에도 상태를 알 수 있도록 이미지에 내장해둔다.
# curl 대신 파이썬 표준 라이브러리를 쓰는 이유: slim 이미지에는 curl이 없다.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz')"]

# 컨테이너 시작 시 실행할 명령: uvicorn(ASGI 서버)으로 FastAPI 앱 구동.
#   main:app        : src/main.py 파일의 app 객체 (WORKDIR가 /app이므로 main으로 바로 찾음)
#   --host 0.0.0.0  : 모든 네트워크 인터페이스에서 수신.
#                     127.0.0.1로 하면 컨테이너 "밖"(Pod 네트워크)에서 접근 불가 — 흔한 실수
#   --port 8000     : EXPOSE/containerPort와 일치
# JSON 배열 형식(exec form)을 쓰면 셸을 거치지 않아 종료 신호(SIGTERM)가
# 앱에 직접 전달된다 → 쿠버네티스가 Pod를 우아하게 종료(graceful shutdown)할 수 있다.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
