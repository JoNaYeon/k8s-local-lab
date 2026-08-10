#!/usr/bin/env bash
# ============================================================================
# port-forward.sh — 클러스터 내부 서비스를 내 컴퓨터의 localhost 포트에 연결한다.
#
# 포트포워딩이란?
#   - 쿠버네티스 Service는 기본적으로 클러스터 "안"에서만 접근 가능하다(ClusterIP).
#   - kubectl port-forward는 내 컴퓨터의 포트 ↔ 클러스터 안 Service 사이에
#     터널을 뚫어, localhost:포트로 바로 접근할 수 있게 한다.
#   - Ingress를 거치지 않고 서비스에 직접 붙므로 개발/디버깅에 유용하다.
#
# 매핑 (이 스크립트가 여는 터널):
#   localhost:8000  → sample-app Service:80  (FastAPI 앱)
#   localhost:5432  → postgres Service:5432  (PostgreSQL — DBeaver 등 GUI 도구 연결 가능)
#   localhost:9090  → Prometheus:9090        (monitoring 설치 후에만)
#
# DevOps 관점: 왜 DB를 Ingress로 노출하지 않고 포트포워딩으로만 여는가?
#   - DB를 외부에 상시 노출하는 것은 보안상 금물. 필요할 때만 로컬 터널로 연다.
#   - 포트포워딩은 kubectl 인증(kubeconfig)을 거치므로 접근 통제가 된다.
#
# 실행 경로: `make port-forward` (Makefile) → 이 스크립트
# 종료 방법: Ctrl+C (또는 pkill -f 'kubectl port-forward')
# ============================================================================

# 안전장치: -e 실패 시 즉시 중단 / -u 미선언 변수 에러 / -o pipefail 파이프 실패 감지
set -euo pipefail

# 터미널 출력 색상 및 로그 헬퍼
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

NAMESPACE="seemedi-dev"

# ── 기존 포트포워딩 정리 ───────────────────────────────────────────────────
# 이전에 실행한 port-forward 프로세스가 남아 있으면 "port already in use"로
# 실패하므로 먼저 모두 종료한다. `|| true`: 종료할 프로세스가 없어도 계속 진행.
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1    # 프로세스가 완전히 종료되고 포트가 반환될 시간을 잠깐 준다

info "포트포워딩 시작..."

# ── 앱: localhost:8000 → sample-app Service ────────────────────────────────
# Service 존재 여부를 먼저 확인해, 배포 전이라면 에러 대신 안내를 출력한다.
if kubectl get svc sample-app -n "$NAMESPACE" &> /dev/null; then
  # "8000:80" = 내 컴퓨터 8000 포트 → Service의 80 포트 (manifests/app/service.yml).
  # 끝의 `&` = 백그라운드 실행 — 여러 터널을 동시에 열기 위함.
  kubectl port-forward svc/sample-app 8000:80 -n "$NAMESPACE" &
  info "앱      → http://localhost:8000"
else
  warn "sample-app Service가 없습니다. 'make deploy' 를 먼저 실행하세요."
fi

# ── PostgreSQL: localhost:5432 → postgres Service ──────────────────────────
if kubectl get svc postgres -n "$NAMESPACE" &> /dev/null; then
  # 5432:5432 — 로컬 psql/GUI 도구에서 localhost:5432로 바로 접속 가능해진다
  kubectl port-forward svc/postgres 5432:5432 -n "$NAMESPACE" &
  info "DB      → localhost:5432 (user: seemedi, db: seemedi)"
else
  warn "postgres Service가 없습니다."
fi

# ── Prometheus: localhost:9090 (모니터링 설치된 경우만) ────────────────────
# Prometheus는 Helm이 만든 Service 이름이 길고 릴리스에 따라 달라질 수 있어,
# 라벨(app.kubernetes.io/name=prometheus)로 검색해 동적으로 찾는다.
if kubectl get svc -n monitoring 2>/dev/null | grep -q prometheus; then
  PROM_SVC=$(kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus -o name 2>/dev/null | head -1)
  if [ -n "$PROM_SVC" ]; then                    # -n: 문자열이 비어있지 않으면 (서비스를 찾았으면)
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

# ── 대기 ───────────────────────────────────────────────────────────────────
# wait: 백그라운드로 띄운 port-forward 프로세스들이 끝날 때까지 이 스크립트를
# 살려둔다. 사용자가 Ctrl+C를 누르면 스크립트와 함께 터널도 모두 종료된다.
# (이게 없으면 스크립트가 바로 끝나면서 make가 터널을 정리해버릴 수 있다)
wait
