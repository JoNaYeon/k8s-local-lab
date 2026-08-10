"""애플리케이션 설정 — pydantic-settings로 환경 변수를 설정 객체로 변환한다.

동작 원리:
    - 아래 Settings의 각 필드는 "같은 이름의 환경 변수"에서 값을 읽는다.
      예: 환경 변수 APP_NAME → app_name 필드 (대소문자 무시 설정 덕분에 매핑됨)
    - 환경 변수가 없으면 필드에 적힌 기본값을 쓴다.

환경 변수는 어디서 오는가? (전체 흐름)
    manifests/app/configmap.yml (APP_NAME, LOG_LEVEL 등 비밀 아닌 값)
    manifests/app/secret.yml    (DATABASE_URL — 비밀값)
        → deployment.yml의 envFrom이 Pod 환경 변수로 주입
        → 이 파일의 Settings가 읽음
        → main.py가 settings 객체로 사용

DevOps 관점 (12-Factor App 원칙):
    - 설정을 코드에 하드코딩하지 않고 환경 변수로 분리하면,
      같은 Docker 이미지를 로컬/스테이징/프로덕션에서 값만 바꿔 재사용할 수 있다.
    - "설정 바꾸려고 이미지 재빌드"하는 일이 없어진다
      (ConfigMap 수정 + rollout restart면 끝 — docs/04-usage-guide.md 7절).
"""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # 각 필드의 기본값은 "환경 변수가 없을 때"(예: 로컬에서 직접 python 실행) 사용된다.
    # 쿠버네티스에서는 ConfigMap/Secret 값이 우선한다.
    app_name: str = "k8s-local-lab"      # ← 환경 변수 APP_NAME (configmap.yml)
    app_version: str = "0.1.0"           # ← APP_VERSION (configmap.yml)
    environment: str = "local"           # ← ENVIRONMENT (configmap.yml) — local/staging/prod 구분
    log_level: str = "INFO"              # ← LOG_LEVEL (configmap.yml) — main.py의 로깅 레벨
    # DB 접속 문자열. 기본값은 로컬 직접 실행용(localhost).
    # 쿠버네티스에서는 secret.yml의 DATABASE_URL(호스트명 postgres)로 덮어써진다.
    # 실제 비밀번호를 이 파일에 적으면 안 된다 — 기본값은 로컬 더미용만 허용.
    database_url: str = "postgresql://seemedi:seemedi@localhost:5432/seemedi"

    # pydantic-settings 동작 옵션:
    #   env_prefix="": 환경 변수 이름에 접두사 없음 (APP_NAME 그대로 매핑)
    #   case_sensitive=False: 대소문자 무시 (APP_NAME ↔ app_name 매핑의 핵심)
    model_config = {"env_prefix": "", "case_sensitive": False}


# 모듈 로드 시 1회 생성되는 전역 설정 객체 — 앱 전체가 이것을 import해서 쓴다.
# (main.py: from core.config import settings)
settings = Settings()
