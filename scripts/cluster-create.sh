#!/usr/bin/env bash
# ============================================================================
# cluster-create.sh — k3d 로컬 쿠버네티스 클러스터를 생성한다.
#
# k3d란?
#   - k3s(경량 쿠버네티스)를 Docker 컨테이너 안에서 실행하는 도구.
#   - "노드 1개 = Docker 컨테이너 1개"로 만들어, 노트북 한 대에서
#     멀티노드 클러스터를 흉내낼 수 있다.
#   - 로컬 테스트용이며, 프로덕션 서버는 표준 k8s(kubeadm)로 전환 예정.
#     (참고: docs/01-kubernetes-intro.md — 우리의 전략,
#            docs/05-production-mapping.md — 1. 클러스터)
#
# 생성되는 구성:
#   - 1 server (컨트롤 플레인: 클러스터를 관리하는 "두뇌")
#   - 2 agents (워커 노드: 실제 앱 Pod가 실행되는 "일꾼")
#   - 포트 매핑: 호스트의 80/443 → 클러스터 로드밸런서
#     → 브라우저에서 http://app.localhost 접근이 가능해지는 이유
#     (manifests/app/ingress.yml의 트래픽 흐름 주석 참고)
#
# DevOps 관점: 멀티노드로 만드는 이유
#   - 단일 노드면 "Pod가 어느 노드에 배치되는가"(스케줄링) 개념을 볼 수 없다.
#   - 프로덕션과 같은 구조(컨트롤 플레인/워커 분리)로 연습해야 이관이 쉽다.
#
# 실행 경로: `make cluster-up` (Makefile) → 이 스크립트
# ============================================================================

# 안전장치: -e 실패 시 즉시 중단 / -u 미선언 변수 에러 / -o pipefail 파이프 실패 감지
set -euo pipefail

# ── 클러스터 파라미터 ──────────────────────────────────────────────────────
CLUSTER_NAME="seemedi-local"   # 클러스터 이름 — Makefile의 CLUSTER_NAME, kubectl 컨텍스트(k3d-seemedi-local)와 연동
AGENTS=2                       # 워커 노드 수 — 이 값만 바꾸면 노드를 늘릴 수 있다 (예: 4 → 1 server + 4 agents)
                               # 재생성 없이 실행 중인 클러스터에 노드를 추가하려면:
                               #   k3d node create <노드명> --cluster seemedi-local --role agent
SERVER_PORT_HTTP=80            # 호스트에서 열 HTTP 포트
SERVER_PORT_HTTPS=443          # 호스트에서 열 HTTPS 포트

# 터미널 출력 색상 및 로그 헬퍼 (모든 스크립트 공통 패턴)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── 기존 클러스터 확인 ─────────────────────────────────────────────────────
# 같은 이름의 클러스터가 이미 있으면 안내만 하고 정상 종료(exit 0).
# 실수로 두 번 실행해도 기존 클러스터를 건드리지 않는다 (멱등성 + 데이터 보호).
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

# k3d cluster create 옵션 설명:
#   --servers 1                : 컨트롤 플레인 노드 1개 (로컬이므로 1개, 프로덕션은 3개 HA)
#                                서버를 늘릴 땐 반드시 홀수(1, 3, 5)로 한다.
#                                이유: etcd 쿼럼 — 클러스터 상태 저장소(etcd)는 쓰기마다
#                                전체 서버의 "과반수 동의"가 필요하다. 과반수를 못 채우면
#                                쓰기를 거부해 데이터가 갈라지는 것(split-brain)을 막는다.
#                                짝수는 장애 허용 수가 한 단계 아래 홀수와 같아서
#                                (2대=0대 허용, 4대=1대 허용) 비용만 늘고 안정성은 그대로.
#                                주의: 서버가 2개 이상이면 아래 --disable=traefik의
#                                @server:0 을 @server:* 로 바꿔야 모든 서버에 적용된다.
#   --agents N                 : 워커 노드 N개
#   --port "80:80@loadbalancer": 호스트 80 포트 → 클러스터 내장 로드밸런서의 80 포트.
#                                이 매핑 덕분에 Ingress(nginx)가 받은 트래픽이
#                                호스트 브라우저까지 연결된다.
#   --port "443:443@..."       : HTTPS도 동일하게 매핑 (로컬은 TLS 미사용이지만 미리 열어둠)
#   --k3s-arg "--disable=traefik@server:0":
#                                k3s에 기본 내장된 Ingress Controller(Traefik)를 끈다.
#                                이유: 프로덕션 표준으로 쓸 nginx-ingress를 대신 설치하기
#                                위함 (scripts/deploy-all.sh 2단계). 둘이 같이 있으면
#                                80 포트를 두고 충돌한다.
#   --wait                     : 모든 노드가 Ready 될 때까지 명령이 기다린다
k3d cluster create "$CLUSTER_NAME" \
  --servers 1 \
  --agents "$AGENTS" \
  --port "${SERVER_PORT_HTTP}:80@loadbalancer" \
  --port "${SERVER_PORT_HTTPS}:443@loadbalancer" \
  --k3s-arg "--disable=traefik@server:0" \
  --wait

# ── kubeconfig 설정 확인 ───────────────────────────────────────────────────
# kubeconfig: kubectl이 "어느 클러스터에, 어떤 인증서로" 접속할지 담은 설정 파일(~/.kube/config).
# merge --kubeconfig-switch-context: 새 클러스터 접속 정보를 kubeconfig에 합치고,
# 현재 컨텍스트(kubectl의 기본 대상)를 이 클러스터로 전환한다.
# → 이 다음부터 모든 kubectl 명령이 자동으로 이 클러스터를 향한다.
info "kubeconfig 설정 중..."
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context

# ── 노드 상태 확인 ─────────────────────────────────────────────────────────
# 노드 전체(server 1 + agent $AGENTS)가 모두 Ready면 성공.
# (기대 출력 예시: docs/03-local-setup-guide.md — Step 2 확인)
echo ""
info "=== 클러스터 노드 상태 ==="
kubectl get nodes -o wide     # -o wide: IP, OS, 컨테이너 런타임 등 상세 컬럼 추가

echo ""
info "=== 클러스터 생성 완료! ==="
info "kubectl 컨텍스트: k3d-$CLUSTER_NAME"
info "'make deploy' 로 앱을 배포하세요."
