#!/usr/bin/env bash
# ============================================================================
# cluster-delete.sh — k3d 로컬 클러스터를 삭제한다.
#
# 삭제되는 것:
#   - 클러스터를 구성하던 Docker 컨테이너(노드 3개 + 로드밸런서) 전부
#   - 클러스터 안의 모든 리소스 (Pod, Service, PVC 등)
#   - ⚠️ PVC에 저장된 PostgreSQL 데이터도 함께 사라진다 (로컬 학습용이라 백업 없음)
#   - kubeconfig에서 이 클러스터의 접속 정보도 k3d가 자동 정리한다
#
# DevOps 관점: 로컬 환경은 "언제든 부수고 다시 만들 수 있는 것"이 장점이다.
#   환경이 꼬였을 때 원인을 오래 찾기보다 clean → cluster-up → deploy로
#   재현 가능한 초기 상태에서 다시 시작하는 것이 빠르다.
#   (참고: docs/03-local-setup-guide.md — 클러스터 완전 초기화)
#
# 실행 경로: `make cluster-down` 또는 `make clean` (Makefile) → 이 스크립트
# ============================================================================

# 안전장치: -e 실패 시 즉시 중단 / -u 미선언 변수 에러 / -o pipefail 파이프 실패 감지
set -euo pipefail

# 삭제 대상 클러스터 이름 — cluster-create.sh에서 만든 이름과 일치해야 한다
CLUSTER_NAME="seemedi-local"

# 터미널 출력 색상 및 로그 헬퍼
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── 존재 확인 ──────────────────────────────────────────────────────────────
# 클러스터가 없으면 에러 대신 안내 후 정상 종료(exit 0).
# make clean을 여러 번 실행해도 실패하지 않게 하는 방어 코드 (멱등성).
if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
  warn "클러스터 '$CLUSTER_NAME'이 존재하지 않습니다."
  exit 0
fi

# ── 삭제 실행 ──────────────────────────────────────────────────────────────
info "클러스터 '$CLUSTER_NAME' 삭제 중..."
# 노드 컨테이너, 로드밸런서, 네트워크, kubeconfig 항목까지 한 번에 정리한다
k3d cluster delete "$CLUSTER_NAME"
info "클러스터 삭제 완료."
