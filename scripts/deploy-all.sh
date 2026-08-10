#!/usr/bin/env bash
# ============================================================================
# deploy-all.sh — 전체 매니페스트를 순서대로 적용한다.
#
# 순서가 중요한 이유:
#   1. Namespace가 먼저 있어야 그 안에 리소스를 만들 수 있다
#   2. ConfigMap/Secret이 있어야 Pod가 환경 변수를 참조할 수 있다
#   3. DB가 먼저 떠야 앱이 DB에 연결할 수 있다
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

NAMESPACE="seemedi-dev"

# ── 1단계: Namespace ──────────────────────────────────────────────────────
info "1/4 — 네임스페이스 생성"
kubectl apply -k manifests/base/

# ── 2단계: Ingress Controller (nginx) ─────────────────────────────────────
info "2/4 — Ingress Controller 설치"
if ! kubectl get ns ingress-nginx &> /dev/null; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/cloud/deploy.yaml
  info "Ingress Controller 설치 완료. 시작 대기 중..."
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s 2>/dev/null || warn "Ingress Controller 시작 대기 시간 초과 (계속 진행)"
else
  info "Ingress Controller 이미 설치됨"
fi

# ── 3단계: Database ───────────────────────────────────────────────────────
info "3/4 — PostgreSQL 배포"
kubectl apply -k manifests/database/
info "PostgreSQL Pod 시작 대기 중..."
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=120s 2>/dev/null || warn "PostgreSQL 시작 대기 시간 초과"

# ── 4단계: Application ────────────────────────────────────────────────────
info "4/4 — 샘플 앱 배포"
kubectl apply -k manifests/app/
info "앱 Pod 시작 대기 중..."
kubectl wait --for=condition=ready pod -l app=sample-app -n "$NAMESPACE" --timeout=120s 2>/dev/null || warn "앱 시작 대기 시간 초과"

# ── 결과 확인 ──────────────────────────────────────────────────────────────
echo ""
info "=== 배포 완료 ==="
echo ""
kubectl get all -n "$NAMESPACE"
echo ""
info "포트포워딩: make port-forward"
info "앱 접근:    curl http://app.localhost/healthz"
info "상태 확인:  make status"
