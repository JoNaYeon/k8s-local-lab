# ============================================================================
# k8s-local-lab Makefile — 모든 작업의 "단일 진입점"
#
# Makefile이란?
#   - 원래는 빌드 도구지만, DevOps에서는 "자주 쓰는 명령 모음집"으로 널리 쓴다.
#   - `make <타겟>` 형태로 실행한다. 예: make deploy
#
# DevOps 관점에서 왜 필요한가?
#   - 긴 명령(kubectl apply -k ... && kubectl rollout ...)을 외울 필요 없이
#     `make deploy-app` 하나로 통일한다 → 팀원 누구나 같은 방식으로 작업 (실수 방지)
#   - 명령이 바뀌어도 Makefile만 고치면 팀 전체의 사용법은 그대로다
#   - 인수인계 시 "make help만 쳐보세요"로 온보딩이 끝난다
#
# 사용법: make help  (사용 가능한 전체 명령 목록 표시)
# 문법 메모:
#   - 각 타겟의 명령 줄은 반드시 탭(tab)으로 시작해야 한다 (스페이스면 에러)
#   - 명령 앞의 @: 명령 자체를 화면에 출력하지 않음 (결과만 출력)
#   - `타겟: 의존타겟` 형태면 의존타겟을 먼저 실행한다 (예: load는 build를 먼저 실행)
# ============================================================================

# ── 공통 변수 ───────────────────────────────────────────────────────────────
# 이름을 변수로 뽑아두면 클러스터/앱 이름 변경 시 이 4줄만 고치면 된다.
# 단, scripts/*.sh와 manifests/*.yml에도 같은 이름이 하드코딩되어 있으므로 함께 확인할 것.
CLUSTER_NAME := seemedi-local
APP_NAME     := sample-app
APP_IMAGE    := $(APP_NAME):local
NAMESPACE    := seemedi-dev

# .PHONY: "이 타겟들은 실제 파일이 아니다"라는 선언.
# 같은 이름의 파일이 우연히 존재해도(예: build라는 파일) 항상 명령이 실행되게 한다.
.PHONY: help setup cluster-up cluster-down build deploy deploy-app deploy-db \
        deploy-monitoring port-forward logs status clean

# ── 도움말 ─────────────────────────────────────────────────────────────────
# 각 타겟 뒤의 "## 설명" 주석을 grep으로 긁어 목록을 자동 생성한다.
# 새 타겟을 추가할 때 "## 설명"만 붙이면 help에 자동으로 나타난다.

help: ## 사용 가능한 명령 목록 표시
	@echo ""
	@echo "k8s-local-lab — 로컬 쿠버네티스 테스트 환경"
	@echo "============================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ── 환경 설정 ──────────────────────────────────────────────────────────────
# 상세 동작은 각 스크립트의 상단 주석 참고 (스크립트마다 라인 단위 설명 있음).

setup: ## 필요한 도구 설치 (k3d, kubectl, helm, kustomize)
	@bash scripts/setup.sh

cluster-up: ## k3d 클러스터 생성 (1 server + 2 agents)
	@bash scripts/cluster-create.sh

cluster-down: ## k3d 클러스터 삭제
	@bash scripts/cluster-delete.sh

# ── 빌드 ───────────────────────────────────────────────────────────────────

# app/Dockerfile로 FastAPI 앱 이미지를 빌드한다.
# 태그(:local)는 manifests/app/deployment.yml의 image와 일치해야 한다.
build: ## 샘플 앱 Docker 이미지 빌드
	@echo "[INFO] Docker 이미지 빌드: $(APP_IMAGE)"
	@docker build -t $(APP_IMAGE) ./app
	@echo "[INFO] 빌드 완료: $(APP_IMAGE)"
	@docker images $(APP_IMAGE)

# "load: build" — build를 먼저 실행한 뒤 이미지를 k3d 클러스터 안으로 복사한다.
# 왜 필요한가: k3d 노드는 Docker 컨테이너라서 호스트의 이미지를 직접 못 본다.
# import를 안 하면 Pod가 ImagePullBackOff로 실패한다
# (참고: docs/03-local-setup-guide.md — 문제 해결, deployment.yml의 imagePullPolicy 주석).
load: build ## 이미지를 k3d 클러스터에 로드
	@echo "[INFO] 이미지를 k3d 클러스터에 로드 중..."
	@k3d image import $(APP_IMAGE) --cluster $(CLUSTER_NAME)
	@echo "[INFO] 이미지 로드 완료"

# ── 배포 ───────────────────────────────────────────────────────────────────

# "deploy: load" — 빌드+로드 후 전체 배포 스크립트 실행.
# 배포 순서(네임스페이스 → Ingress Controller → DB → 앱)와 그 이유는
# scripts/deploy-all.sh 상단 주석 참고.
deploy: load ## 전체 매니페스트 배포 (네임스페이스 → DB → 앱)
	@bash scripts/deploy-all.sh

# 앱 관련 매니페스트만 다시 적용하고 Pod를 재시작한다.
# rollout restart가 필요한 이유: 이미지 태그(sample-app:local)가 항상 같아서
# apply만으로는 쿠버네티스가 "변경 없음"으로 판단해 새 이미지를 안 쓴다.
# 재시작으로 Pod를 새로 만들면 load된 최신 이미지를 다시 읽는다.
# (코드 수정 → make load → make deploy-app 이 일상 사이클.
#  참고: docs/04-usage-guide.md — 1. 앱 코드 수정 후 재배포)
deploy-app: ## 앱 매니페스트만 재배포
	@kubectl apply -k manifests/app/ -n $(NAMESPACE)
	@kubectl rollout restart deployment/$(APP_NAME) -n $(NAMESPACE)
	@echo "[INFO] 앱 재배포 완료"

deploy-db: ## DB 매니페스트만 재배포
	@kubectl apply -k manifests/database/ -n $(NAMESPACE)
	@echo "[INFO] DB 재배포 완료"

# Prometheus 스택 설치 — Helm 사용 (상세: manifests/monitoring/install.sh 주석)
deploy-monitoring: ## Prometheus 설치 (Helm)
	@bash manifests/monitoring/install.sh

# ── 운영 ───────────────────────────────────────────────────────────────────

# 클러스터 내부 서비스를 localhost로 연결 (상세: scripts/port-forward.sh 주석)
port-forward: ## 주요 서비스 포트포워딩 (앱:8000, DB:5432, Prometheus:9090)
	@bash scripts/port-forward.sh

# -f: 실시간 스트리밍(tail -f처럼) / -l app=...: 라벨로 Pod 선택
# (라벨은 manifests/app/deployment.yml의 template.metadata.labels에서 정의)
# --all-containers: Pod 안 컨테이너가 여러 개여도 전부 출력
logs: ## 샘플 앱 로그 확인 (실시간)
	@kubectl logs -f -l app=$(APP_NAME) -n $(NAMESPACE) --all-containers

# 노드/앱/모니터링 상태를 한눈에 출력. 배포 후 정상 확인용
# (모든 Pod가 Running이어야 정상 — docs/03-local-setup-guide.md Step 4).
# `2>/dev/null || echo ...`: monitoring 미설치 시 에러 대신 안내 문구 출력
status: ## 전체 리소스 상태 확인
	@echo ""
	@echo "=== 노드 ==="
	@kubectl get nodes
	@echo ""
	@echo "=== 네임스페이스: $(NAMESPACE) ==="
	@kubectl get all -n $(NAMESPACE)
	@echo ""
	@echo "=== 네임스페이스: monitoring ==="
	@kubectl get all -n monitoring 2>/dev/null || echo "(monitoring 네임스페이스 없음)"
	@echo ""

# ── 정리 ───────────────────────────────────────────────────────────────────

# 클러스터 전체 삭제 — PVC의 DB 데이터도 함께 사라진다 (cluster-delete.sh 주석 참고).
# 환경이 꼬였을 때: make clean → make cluster-up → make deploy 로 초기화
clean: ## 전체 삭제 (매니페스트 제거 + 클러스터 삭제)
	@echo "[WARN] 클러스터와 모든 리소스를 삭제합니다."
	@bash scripts/cluster-delete.sh
	@echo "[INFO] 정리 완료"
