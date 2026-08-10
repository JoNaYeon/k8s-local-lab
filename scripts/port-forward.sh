#!/usr/bin/env bash
# ============================================================================
# port-forward.sh — 주요 서비스를 로컬 포트에 연결한다.
#
# 포트포워딩이란?
#   쿠버네티스 클러스터 안의 서비스를 내 컴퓨터의 localhost:포트로 접근할 수 있게 한다.
#   개발/디버깅 시 유용하다.
#
# 매핑:
#   localhost:8000  → sample-app (FastAPI)
#   localhost:5432  → PostgreSQL
#   localhost:9090  → Prometheus (monitoring 배포 후)
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

NAMESPACE="seemedi-dev"

# 기존 포트포워딩 프로세스 종료
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1

info "포트포워딩 시작..."

# 앱: localhost:8000
if kubectl get svc sample-app -n "$NAMESPACE" &> /dev/null; then
  kubectl port-forward svc/sample-app 8000:80 -n "$NAMESPACE" &
  info "앱      → http://localhost:8000"
else
  warn "sample-app Service가 없습니다. 'make deploy' 를 먼저 실행하세요."
fi

# PostgreSQL: localhost:5432
if kubectl get svc postgres -n "$NAMESPACE" &> /dev/null; then
  kubectl port-forward svc/postgres 5432:5432 -n "$NAMESPACE" &
  info "DB      → localhost:5432 (user: seemedi, db: seemedi)"
else
  warn "postgres Service가 없습니다."
fi

# Prometheus: localhost:9090
if kubectl get svc -n monitoring 2>/dev/null | grep -q prometheus; then
  PROM_SVC=$(kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus -o name 2>/dev/null | head -1)
  if [ -n "$PROM_SVC" ]; then
    kubectl port-forward "$PROM_SVC" 9090:9090 -n monitoring &
    info "Prometheus → http://localhost:9090"
  fi
else
  warn "Prometheus가 설치되지 않았습니다. 'make deploy-monitoring' 으로 설치하세요."
fi

echo ""
info "포트포워딩이 백그라운드에서 실행 중입니다."
info "종료하려면: pkill -f 'kubectl port-forward'"
echo ""

# 포그라운드에서 대기 (Ctrl+C로 종료)
wait
