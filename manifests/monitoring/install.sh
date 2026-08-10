#!/usr/bin/env bash
# ============================================================================
# install.sh — Helm으로 kube-prometheus-stack(모니터링 도구 모음)을 설치한다.
#
# Helm이란?
#   - 쿠버네티스의 "패키지 매니저" (Ubuntu의 apt, macOS의 brew 같은 역할)
#   - 복잡한 앱(수십 개의 YAML로 구성)을 명령 하나로 설치/업그레이드/삭제한다
#   - 용어: Chart = 패키지(설치 템플릿), Release = 실제 설치된 인스턴스,
#           values = 설치 옵션 (이 레포에서는 prometheus-values.yml)
#
# DevOps 관점에서 왜 Helm을 쓰는가?
#   - Prometheus 스택은 CRD, RBAC, Deployment 등 YAML이 수십 개라
#     손으로 관리하면 누락/버전 불일치가 생긴다. 커뮤니티가 검증한 차트를
#     쓰면 "설치 방법"이 아니라 "설정값"만 관리하면 된다.
#
# 실행 경로: `make deploy-monitoring` (Makefile) → 이 스크립트
# 사용법:   bash manifests/monitoring/install.sh (레포 루트에서 실행)
# ============================================================================

# 안전장치 3종 세트 (모든 스크립트 공통):
#   -e: 명령 하나라도 실패하면 즉시 중단 (실패를 무시하고 진행하다 더 큰 사고 방지)
#   -u: 선언 안 된 변수 사용 시 에러 (오타로 빈 값이 들어가는 사고 방지)
#   -o pipefail: 파이프(|) 중간 명령이 실패해도 실패로 처리
set -euo pipefail

# 터미널 출력 색상 코드 (가독성용 — 기능에는 영향 없음)
GREEN='\033[0;32m'   # 초록색 시작
NC='\033[0m'         # 색상 초기화(No Color)

# [INFO] 접두사를 붙여 초록색으로 출력하는 헬퍼 함수
info() { echo -e "${GREEN}[INFO]${NC} $1"; }

# ── 설치 파라미터 ───────────────────────────────────────────────────────────
RELEASE_NAME="prometheus"                                # Helm Release 이름 — 업그레이드/삭제 시 이 이름으로 지정
NAMESPACE="monitoring"                                   # 설치 대상 네임스페이스 (manifests/base/namespaces.yml에서 정의)
VALUES_FILE="manifests/monitoring/prometheus-values.yml" # 설치 옵션 파일 (상세 설명은 해당 파일 주석 참고)

# ── Helm repo 추가 ────────────────────────────────────────────────────────
# Helm repo = 차트를 내려받는 저장소 주소 (apt의 소스 리스트와 같은 개념).
# prometheus-community는 Prometheus 관련 공식 커뮤니티 차트 저장소다.
info "Helm repo 추가: prometheus-community"
# `|| true`: 이미 추가된 repo면 에러가 나는데, 그 경우에도 스크립트를
# 중단하지 않고 계속 진행한다 (재실행해도 안전한 "멱등성" 확보).
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
# repo의 차트 목록을 최신으로 갱신 (apt update와 동일한 역할)
helm repo update

# ── 네임스페이스 확인 ──────────────────────────────────────────────────────
# monitoring 네임스페이스가 없으면 생성한다.
# make deploy를 건너뛰고 이 스크립트만 실행해도 동작하게 하는 방어 코드.
kubectl get ns "$NAMESPACE" &>/dev/null || kubectl create ns "$NAMESPACE"

# ── 설치 또는 업그레이드 ──────────────────────────────────────────────────
info "kube-prometheus-stack 설치/업그레이드 중..."
# `upgrade --install`: 없으면 설치, 있으면 업그레이드 — 첫 실행과 재실행을
# 같은 명령으로 처리하는 Helm의 표준 패턴 (CI/CD에서도 이 패턴을 쓴다).
# 옵션 설명:
#   --namespace : 설치 대상 네임스페이스
#   --values    : 설치 옵션 파일 (prometheus-values.yml)
#   --wait      : 모든 Pod가 Ready 될 때까지 기다린다 (설치 "성공"을 보장하고 종료)
#   --timeout 5m: 5분 안에 Ready가 안 되면 실패 처리 (무한 대기 방지)
helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --values "$VALUES_FILE" \
  --wait \
  --timeout 5m

# ── 완료 안내 ──────────────────────────────────────────────────────────────
echo ""
info "=== Prometheus 설치 완료 ==="
# Prometheus UI는 클러스터 내부에만 있으므로, 브라우저에서 보려면 포트포워딩 필요
info "포트포워딩: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring"
info "또는: make port-forward"
echo ""
# 설치된 Pod 목록을 보여줘서 상태를 바로 확인할 수 있게 한다
kubectl get pods -n "$NAMESPACE"
