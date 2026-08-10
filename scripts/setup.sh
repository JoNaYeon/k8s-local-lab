#!/usr/bin/env bash
# ============================================================================
# setup.sh — 로컬 k8s 환경에 필요한 도구 5종을 자동 설치한다.
#
# 설치 도구와 역할: (참고: docs/03-local-setup-guide.md — Step 1)
#   - Docker    : 컨테이너 런타임 — 모든 것의 기반. k3d 클러스터도 Docker 위에서 돈다
#   - k3d       : k3s(경량 쿠버네티스)를 Docker 컨테이너 안에서 실행하는 도구
#   - kubectl   : 쿠버네티스 CLI — 클러스터에 명령을 내리는 유일한 창구
#   - helm      : 쿠버네티스 패키지 매니저 — Prometheus 설치에 사용
#   - kustomize : 매니페스트 묶음 관리 도구 — manifests/ 배포에 사용
#
# DevOps 관점에서 왜 스크립트로 설치하는가?
#   - 팀원마다 손으로 설치하면 버전/방법이 제각각이 되어
#     "내 컴퓨터에서는 되는데" 문제가 생긴다.
#   - 설치 과정을 코드로 남기면 새 팀원 온보딩이 명령 하나(make setup)로 끝난다.
#   - 이미 설치된 도구는 건너뛰므로 여러 번 실행해도 안전하다 (멱등성).
#
# 실행 경로: `make setup` (Makefile) → 이 스크립트
# 지원 OS:  Ubuntu(apt) / macOS(brew) — 아래에서 자동 감지
# ============================================================================

# 안전장치: -e 실패 시 즉시 중단 / -u 미선언 변수 에러 / -o pipefail 파이프 실패 감지
set -euo pipefail

# 터미널 출력 색상 코드 (가독성용)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 로그 헬퍼: 초록 [INFO] / 노랑 [WARN] 접두사로 출력
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── OS 확인 ────────────────────────────────────────────────────────────────
# uname -s: 커널 이름 출력 (macOS는 "Darwin", 리눅스는 "Linux").
# OS에 따라 패키지 매니저를 달리 선택하고, 이후 모든 설치 분기가 이 변수를 따른다.
if [[ "$(uname -s)" == "Darwin" ]]; then
  PKG_MANAGER="brew"
  info "macOS 감지 — Homebrew 사용"
  # command -v: 해당 명령이 존재하는지 확인 (있으면 경로 출력, 없으면 실패)
  if ! command -v brew &> /dev/null; then
    echo "Homebrew가 설치되어 있지 않습니다."
    echo "https://brew.sh 에서 설치 후 다시 실행하세요."
    exit 1     # brew 없이는 진행 불가 → 비정상 종료 코드(1)로 중단
  fi
else
  PKG_MANAGER="apt"
  info "Linux 감지 — apt 사용"
fi

# ── Docker 확인/설치 ───────────────────────────────────────────────────────
# Docker가 없으면: Ubuntu는 공식 저장소를 등록해 자동 설치, macOS는 수동 안내.
# (macOS의 Docker Desktop은 GUI 앱이라 스크립트 설치가 부적절)
if ! command -v docker &> /dev/null; then
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    warn "Docker가 설치되어 있지 않습니다. 설치 중..."
    # Docker 공식 apt 저장소 등록 절차 (Ubuntu 표준 설치법):
    sudo apt-get update -qq                                   # 패키지 목록 갱신 (-qq: 조용히)
    sudo apt-get install -y -qq ca-certificates curl gnupg    # 저장소 등록에 필요한 기본 도구
    sudo install -m 0755 -d /etc/apt/keyrings                 # GPG 키 보관 디렉토리 생성 (권한 755)
    # Docker의 GPG 서명 키 다운로드 — 패키지가 위조되지 않았음을 검증하는 열쇠.
    # `|| true`: 키가 이미 있으면 gpg가 에러를 내는데, 그 경우에도 계속 진행 (재실행 안전)
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    sudo chmod a+r /etc/apt/keyrings/docker.gpg               # 모든 사용자가 키를 읽을 수 있게
    # Docker 저장소를 apt 소스 목록에 추가.
    # $(dpkg --print-architecture): CPU 아키텍처(amd64/arm64) 자동 감지
    # $VERSION_CODENAME: Ubuntu 버전 코드명(jammy 등) 자동 감지
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq                                   # 새 저장소 반영
    # docker-ce(엔진) + CLI + containerd(런타임) + buildx(빌드 확장) 설치
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    # 현재 사용자를 docker 그룹에 추가 — sudo 없이 docker 명령을 쓰기 위함.
    # 그룹 변경은 재로그인(또는 newgrp docker) 후에 반영된다.
    # (참고: docs/03-local-setup-guide.md — Docker 그룹 권한)
    sudo usermod -aG docker "$USER"
    info "Docker 설치 완료. 그룹 변경 반영을 위해 재로그인이 필요할 수 있습니다."
  else
    warn "Docker Desktop을 먼저 설치하세요: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi
fi

# ── Docker 데몬 실행 확인 ──────────────────────────────────────────────────
# docker 명령이 있어도 데몬(백그라운드 서비스)이 꺼져 있으면 모든 작업이 실패한다.
# docker info: 데몬과 통신이 되어야만 성공하는 명령이라 "살아있는지" 확인용으로 적합.
if ! docker info &> /dev/null 2>&1; then
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    warn "Docker 데몬 시작 중..."
    sudo systemctl start docker || true    # systemd로 데몬 시작 (실패해도 아래에서 재확인)
    sleep 2                                # 데몬 기동 시간 잠깐 대기
    if ! docker info &> /dev/null 2>&1; then
      warn "Docker 데몬이 실행되지 않습니다. 'sudo systemctl start docker' 후 다시 시도하세요."
      exit 1
    fi
  else
    # macOS는 Docker Desktop/OrbStack 같은 GUI 앱이 데몬 역할 — 사용자가 직접 실행해야 함
    warn "Docker 데몬이 실행 중이 아닙니다."
    warn "OrbStack 또는 Docker Desktop을 실행한 후 다시 시도하세요."
    exit 1
  fi
fi
info "Docker 확인 완료: $(docker --version)"

# ── k3d 설치 ──────────────────────────────────────────────────────────────
# k3d: k3s 클러스터를 Docker 컨테이너로 띄우는 래퍼 도구.
# scripts/cluster-create.sh가 이 도구로 클러스터를 만든다.
if command -v k3d &> /dev/null; then
  info "k3d 이미 설치됨: $(command -v k3d)"   # 이미 있으면 건너뜀 (멱등성)
else
  info "k3d 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install k3d
  else
    # 공식 설치 스크립트 실행 — /usr/local/bin/k3d에 최신 버전을 설치한다
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi
fi

# ── kubectl 설치 ──────────────────────────────────────────────────────────
# kubectl: 쿠버네티스 클러스터에 명령을 내리는 공식 CLI.
# 이후 모든 배포/조회/디버깅(docs/04-usage-guide.md)이 이 도구로 이뤄진다.
if command -v kubectl &> /dev/null; then
  info "kubectl 이미 설치됨: $(command -v kubectl)"
else
  info "kubectl 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install kubernetes-cli
  else
    # 쿠버네티스 공식 apt 저장소(pkgs.k8s.io) 등록 — Docker 저장소 등록과 동일한 패턴.
    # v1.31: kubectl 마이너 버전. 클러스터(k3s v1.30~)와 ±1 마이너 버전 이내면 호환된다.
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
      sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq kubectl
  fi
fi

# ── helm 설치 ─────────────────────────────────────────────────────────────
# helm: 쿠버네티스 패키지 매니저. manifests/monitoring/install.sh가
# Prometheus 스택 설치에 사용한다. (Helm 설명: 해당 파일 상단 주석)
if command -v helm &> /dev/null; then
  info "helm 이미 설치됨: $(command -v helm)"
else
  info "helm 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install helm
  else
    # Helm 공식 설치 스크립트 (get-helm-3) — 최신 v3를 /usr/local/bin에 설치
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
fi

# ── kustomize 설치 ────────────────────────────────────────────────────────
# kustomize: manifests/의 kustomization.yml을 해석해 여러 YAML을 묶어주는 도구.
# kubectl에도 내장(-k 옵션)되어 있지만, CI 검증 등에서 단독 실행형도 필요하다.
# (.github/workflows/ci.yml의 "Validate Kustomize manifests" 스텝과 동일한 도구)
if command -v kustomize &> /dev/null; then
  info "kustomize 이미 설치됨: $(command -v kustomize)"
else
  info "kustomize 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install kustomize
  else
    # 공식 설치 스크립트는 현재 디렉토리에 바이너리를 내려놓으므로
    # PATH에 잡히도록 /usr/local/bin으로 직접 옮긴다
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
  fi
fi

# ── 버전 확인 ──────────────────────────────────────────────────────────────
# 설치가 전부 성공했는지 버전 출력으로 최종 확인.
# (docs/03-local-setup-guide.md — Step 1의 "성공" 판정 기준이 이 출력)
echo ""
info "=== 설치된 도구 버전 ==="
echo "  Docker:     $(docker --version)"
echo "  k3d:        $(k3d version | head -1)"
# kubectl 구버전은 --short 옵션이 있고 신버전은 제거됨 — 둘 다 대응하는 fallback
echo "  kubectl:    $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "  helm:       $(helm version --short)"
echo "  kustomize:  $(kustomize version 2>/dev/null || echo 'installed')"
echo ""
info "=== 설치 완료! ==="
info "'make cluster-up' 으로 클러스터를 생성하세요."
