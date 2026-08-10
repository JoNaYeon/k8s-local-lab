#!/usr/bin/env bash
# ============================================================================
# deploy-all.sh — 전체 매니페스트를 "순서대로" 적용한다.
#
# 배포 순서와 그 이유 (순서가 틀리면 배포가 실패하거나 앱이 뜨자마자 죽는다):
#   1. Namespace      — 모든 리소스가 들어갈 "그릇". 없으면 이후 전부 실패
#   2. Ingress Controller — Ingress "규칙"(manifests/app/ingress.yml)을 실제로
#                       처리할 엔진. 없으면 규칙이 있어도 외부 접근 불가
#   3. Database       — 앱보다 먼저. 앱이 뜨면서 DB에 연결하기 때문
#   4. Application    — 마지막. ConfigMap/Secret/DB가 모두 준비된 상태에서 기동
#
# DevOps 관점: 이런 "적용 순서"를 사람 머리가 아니라 스크립트에 박아두는 이유
#   - 누가 실행해도 같은 순서로 배포된다 (운영 실수 방지, 인수인계 용이)
#   - 각 단계 사이에 "준비될 때까지 대기(kubectl wait)"를 넣어
#     아직 안 뜬 DB에 앱이 붙으려다 실패하는 경쟁 조건을 줄인다
#   - 프로덕션에서는 이 역할을 ArgoCD 같은 GitOps 도구가 대신한다
#     (참고: docs/05-production-mapping.md — 6. CI/CD)
#
# 실행 경로: `make deploy` (Makefile) → 이미지 빌드/로드(make load) → 이 스크립트
# ============================================================================

# 안전장치: -e 실패 시 즉시 중단 / -u 미선언 변수 에러 / -o pipefail 파이프 실패 감지
set -euo pipefail

# 터미널 출력 색상 및 로그 헬퍼
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 앱/DB가 배포되는 네임스페이스 (manifests/base/namespaces.yml에서 정의)
NAMESPACE="seemedi-dev"

# ── 1단계: Namespace ──────────────────────────────────────────────────────
# apply -k: 디렉토리의 kustomization.yml을 읽어 그 안의 리소스를 전부 적용.
# seemedi-dev, monitoring 네임스페이스가 만들어진다.
info "1/4 — 네임스페이스 생성"
kubectl apply -k manifests/base/

# ── 2단계: Ingress Controller (nginx) ─────────────────────────────────────
# Ingress Controller = Ingress 규칙을 읽어 실제 트래픽을 라우팅하는 nginx Pod.
# k3s 기본 내장 Traefik은 클러스터 생성 시 껐으므로(cluster-create.sh 주석 참고)
# 프로덕션 표준인 nginx-ingress를 공식 매니페스트 URL로 설치한다.
# URL에 버전(v1.12.2)을 고정한 이유: latest를 쓰면 어느 날 동작이 바뀔 수 있다 (재현성).
info "2/4 — Ingress Controller 설치"
if ! kubectl get ns ingress-nginx &> /dev/null; then     # 이미 설치돼 있으면 건너뜀 (멱등성)
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.2/deploy/static/provider/cloud/deploy.yaml
  info "Ingress Controller 설치 완료. 시작 대기 중..."
  # controller Pod가 Ready 될 때까지 최대 120초 대기.
  # 실패해도(|| warn) 중단하지 않는 이유: 이미지 다운로드가 느릴 뿐 결국 뜨는 경우가
  # 대부분이라, 여기서 전체 배포를 멈추는 것보다 경고 후 진행이 낫다.
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s 2>/dev/null || warn "Ingress Controller 시작 대기 시간 초과 (계속 진행)"
else
  info "Ingress Controller 이미 설치됨"
fi

# ── 3단계: Database ───────────────────────────────────────────────────────
# PostgreSQL 세트(ConfigMap → Secret → PVC → StatefulSet → Service) 적용.
# 파일별 역할은 manifests/database/kustomization.yml 주석 참고.
info "3/4 — PostgreSQL 배포"
kubectl apply -k manifests/database/
info "PostgreSQL Pod 시작 대기 중..."
# `-l app=postgres`: statefulset.yml의 Pod 라벨로 대상을 지정.
# DB가 Ready 된 후에 앱을 배포해야 앱의 첫 DB 연결이 실패하지 않는다.
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=120s 2>/dev/null || warn "PostgreSQL 시작 대기 시간 초과"

# ── 4단계: Application ────────────────────────────────────────────────────
# 샘플 앱 세트(ConfigMap → Secret → Deployment → Service → Ingress → HPA) 적용.
# 파일별 역할은 manifests/app/kustomization.yml 주석 참고.
info "4/4 — 샘플 앱 배포"
kubectl apply -k manifests/app/
info "앱 Pod 시작 대기 중..."
kubectl wait --for=condition=ready pod -l app=sample-app -n "$NAMESPACE" --timeout=120s 2>/dev/null || warn "앱 시작 대기 시간 초과"

# ── 결과 확인 ──────────────────────────────────────────────────────────────
# 배포된 전체 리소스(Pod/Service/Deployment/StatefulSet 등)를 한눈에 출력.
# 모든 Pod가 Running이어야 정상 (참고: docs/03-local-setup-guide.md — Step 4 확인)
echo ""
info "=== 배포 완료 ==="
echo ""
kubectl get all -n "$NAMESPACE"
echo ""
info "포트포워딩: make port-forward"
info "앱 접근:    curl http://app.localhost/healthz"
info "상태 확인:  make status"
