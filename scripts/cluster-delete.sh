#!/usr/bin/env bash
# ============================================================================
# cluster-delete.sh — k3d 로컬 클러스터를 삭제한다.
# 사용법: bash scripts/cluster-delete.sh
# ============================================================================
set -euo pipefail

CLUSTER_NAME="seemedi-local"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  warn "클러스터 '$CLUSTER_NAME'이 존재하지 않습니다."
  exit 0
fi

info "클러스터 '$CLUSTER_NAME' 삭제 중..."
k3d cluster delete "$CLUSTER_NAME"
info "클러스터 삭제 완료."
