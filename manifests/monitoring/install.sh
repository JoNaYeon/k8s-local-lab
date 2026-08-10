#!/usr/bin/env bash
# ============================================================================
# install.sh — Helm으로 kube-prometheus-stack을 설치한다.
#
# Helm이란?
#   - 쿠버네티스의 "패키지 매니저" (apt, brew 같은 역할)
#   - 복잡한 앱(수십 개 YAML)을 하나의 명령으로 설치/업그레이드/삭제
#   - Chart = 패키지, Release = 설치된 인스턴스
#
# 사용법: bash manifests/monitoring/install.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }

RELEASE_NAME="prometheus"
NAMESPACE="monitoring"
VALUES_FILE="manifests/monitoring/prometheus-values.yml"

# ── Helm repo 추가 ────────────────────────────────────────────────────────
info "Helm repo 추가: prometheus-community"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# ── 네임스페이스 확인 ──────────────────────────────────────────────────────
kubectl get ns "$NAMESPACE" &>/dev/null || kubectl create ns "$NAMESPACE"

# ── 설치 또는 업그레이드 ──────────────────────────────────────────────────
info "kube-prometheus-stack 설치/업그레이드 중..."
helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 5m

echo ""
info "=== Prometheus 설치 완료 ==="
info "포트포워딩: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
info "또는: make port-forward"
echo ""
kubectl get pods -n "$NAMESPACE"
