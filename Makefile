# ============================================================================
# k8s-local-lab Makefile
# 모든 작업의 단일 진입점. 'make help'로 사용 가능한 명령을 확인하세요.
# ============================================================================

CLUSTER_NAME := seemedi-local
APP_NAME     := sample-app
APP_IMAGE    := $(APP_NAME):local
NAMESPACE    := seemedi-dev

.PHONY: help setup cluster-up cluster-down build deploy deploy-app deploy-db \
        deploy-monitoring port-forward logs status clean

# ── 도움말 ─────────────────────────────────────────────────────────────────

help: ## 사용 가능한 명령 목록 표시
	@echo ""
	@echo "k8s-local-lab — 로컬 쿠버네티스 테스트 환경"
	@echo "============================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ── 환경 설정 ──────────────────────────────────────────────────────────────

setup: ## 필요한 도구 설치 (k3d, kubectl, helm, kustomize)
	@bash scripts/setup.sh

cluster-up: ## k3d 클러스터 생성 (1 server + 2 agents)
	@bash scripts/cluster-create.sh

cluster-down: ## k3d 클러스터 삭제
	@bash scripts/cluster-delete.sh

# ── 빌드 ───────────────────────────────────────────────────────────────────

build: ## 샘플 앱 Docker 이미지 빌드
	@echo "[INFO] Docker 이미지 빌드: $(APP_IMAGE)"
	@docker build -t $(APP_IMAGE) ./app
	@echo "[INFO] 빌드 완료: $(APP_IMAGE)"
	@docker images $(APP_IMAGE)

load: build ## 이미지를 k3d 클러스터에 로드
	@echo "[INFO] 이미지를 k3d 클러스터에 로드 중..."
	@k3d image import $(APP_IMAGE) --cluster $(CLUSTER_NAME)
	@echo "[INFO] 이미지 로드 완료"

# ── 배포 ───────────────────────────────────────────────────────────────────

deploy: load ## 전체 매니페스트 배포 (네임스페이스 → DB → 앱)
	@bash scripts/deploy-all.sh

deploy-app: ## 앱 매니페스트만 재배포
	@kubectl apply -k manifests/app/ -n $(NAMESPACE)
	@kubectl rollout restart deployment/$(APP_NAME) -n $(NAMESPACE)
	@echo "[INFO] 앱 재배포 완료"

deploy-db: ## DB 매니페스트만 재배포
	@kubectl apply -k manifests/database/ -n $(NAMESPACE)
	@echo "[INFO] DB 재배포 완료"

deploy-monitoring: ## Prometheus 설치 (Helm)
	@bash manifests/monitoring/install.sh

# ── 운영 ───────────────────────────────────────────────────────────────────

port-forward: ## 주요 서비스 포트포워딩 (앱:8000, DB:5432, Prometheus:9090)
	@bash scripts/port-forward.sh

logs: ## 샘플 앱 로그 확인 (실시간)
	@kubectl logs -f -l app=$(APP_NAME) -n $(NAMESPACE) --all-containers

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

clean: ## 전체 삭제 (매니페스트 제거 + 클러스터 삭제)
	@echo "[WARN] 클러스터와 모든 리소스를 삭제합니다."
	@bash scripts/cluster-delete.sh
	@echo "[INFO] 정리 완료"
