#!/usr/bin/env bash
# ============================================================================
# setup.sh — 로컬 k8s 환경에 필요한 도구를 설치한다 (Ubuntu)
# 사용법: bash scripts/setup.sh
# ============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ── OS 확인 ────────────────────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]]; then
  PKG_MANAGER="brew"
  info "macOS 감지 — Homebrew 사용"
  if ! command -v brew &> /dev/null; then
    echo "Homebrew가 설치되어 있지 않습니다."
    echo "https://brew.sh 에서 설치 후 다시 실행하세요."
    exit 1
  fi
else
  PKG_MANAGER="apt"
  info "Linux 감지 — apt 사용"
fi

# ── Docker 확인 ────────────────────────────────────────────────────────────
if ! command -v docker &> /dev/null; then
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    warn "Docker가 설치되어 있지 않습니다. 설치 중..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    sudo usermod -aG docker "$USER"
    info "Docker 설치 완료. 그룹 변경 반영을 위해 재로그인이 필요할 수 있습니다."
  else
    warn "Docker Desktop을 먼저 설치하세요: https://www.docker.com/products/docker-desktop/"
    exit 1
  fi
fi

if ! docker info &> /dev/null 2>&1; then
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    warn "Docker 데몬 시작 중..."
    sudo systemctl start docker || true
    sleep 2
    if ! docker info &> /dev/null 2>&1; then
      warn "Docker 데몬이 실행되지 않습니다. 'sudo systemctl start docker' 후 다시 시도하세요."
      exit 1
    fi
  else
    warn "Docker 데몬이 실행 중이 아닙니다."
    warn "OrbStack 또는 Docker Desktop을 실행한 후 다시 시도하세요."
    exit 1
  fi
fi
info "Docker 확인 완료: $(docker --version)"

# ── k3d 설치 ──────────────────────────────────────────────────────────────
if command -v k3d &> /dev/null; then
  info "k3d 이미 설치됨: $(command -v k3d)"
else
  info "k3d 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install k3d
  else
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi
fi

# ── kubectl 설치 ──────────────────────────────────────────────────────────
if command -v kubectl &> /dev/null; then
  info "kubectl 이미 설치됨: $(command -v kubectl)"
else
  info "kubectl 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install kubernetes-cli
  else
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | \
      sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq kubectl
  fi
fi

# ── helm 설치 ─────────────────────────────────────────────────────────────
if command -v helm &> /dev/null; then
  info "helm 이미 설치됨: $(command -v helm)"
else
  info "helm 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install helm
  else
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
fi

# ── kustomize 설치 ────────────────────────────────────────────────────────
if command -v kustomize &> /dev/null; then
  info "kustomize 이미 설치됨: $(command -v kustomize)"
else
  info "kustomize 설치 중..."
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    brew install kustomize
  else
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    sudo mv kustomize /usr/local/bin/
  fi
fi

# ── 버전 확인 ──────────────────────────────────────────────────────────────
echo ""
info "=== 설치된 도구 버전 ==="
echo "  Docker:     $(docker --version)"
echo "  k3d:        $(k3d version | head -1)"
echo "  kubectl:    $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "  helm:       $(helm version --short)"
echo "  kustomize:  $(kustomize version 2>/dev/null || echo 'installed')"
echo ""
info "=== 설치 완료! ==="
info "'make cluster-up' 으로 클러스터를 생성하세요."
