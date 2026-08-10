#!/usr/bin/env bash
# ============================================================================
# cluster-create.sh — k3d 로컬 클러스터를 생성한다.
#
# k3d는 k3s(경량 쿠버네티스)를 Docker 컨테이너 안에서 실행한다.
# 로컬 테스트용이며, 프로덕션 서버에서는 표준 k8s(kubeadm)로 전환 예정.
#
# 구성:
#   - 1 server (컨트롤 플레인) + 2 agents (워커 노드)
#   - 포트 매핑: 80(HTTP), 443(HTTPS) → 호스트에서 Ingress 접근 가능
#
# 사용법: bash scripts/cluster-create.sh
# ============================================================================
set -euo pipefail

CLUSTER_NAME="seemedi-local"
AGENTS=2
SERVER_PORT_HTTP=80
SERVER_PORT_HTTPS=443

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── 기존 클러스터 확인 ─────────────────────────────────────────────────────
if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  warn "클러스터 '$CLUSTER_NAME'이 이미 존재합니다."
  warn "삭제 후 재생성하려면: make cluster-down && make cluster-up"
  exit 0
fi

# ── 클러스터 생성 ──────────────────────────────────────────────────────────
info "=== k3d 클러스터 생성 시작 ==="
info "클러스터명: $CLUSTER_NAME"
info "구성: 1 server + $AGENTS agents"
info "포트 매핑: $SERVER_PORT_HTTP(HTTP), $SERVER_PORT_HTTPS(HTTPS)"
echo ""

k3d cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents "$AGENTS" \
  --port "${SERVER_PORT_HTTP}:80@loadbalancer" \
  --port "${SERVER_PORT_HTTPS}:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0" \
  --wait

# ── kubeconfig 설정 확인 ───────────────────────────────────────────────────
info "kubeconfig 설정 중..."
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context

# ── 노드 상태 확인 ─────────────────────────────────────────────────────────
echo ""
info "=== 클러스터 노드 상태 ==="
kubectl get nodes -o wide

echo ""
info "=== 클러스터 생성 완료! ==="
info "kubectl 컨텍스트: k3d-$CLUSTER_NAME"
info "'make deploy' 로 앱을 배포하세요."
