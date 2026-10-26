#!/bin/bash

# Ensure /usr/local/bin is in PATH for this script session
export PATH="/usr/local/bin:$PATH"
set -o pipefail

# Clean up temporary download files on exit
cleanup() {
  rm -f ./kind ./kubectl
}
trap cleanup EXIT

echo "🚀 Starting installation and verification of Docker, Kind, and kubectl..."
echo

# -----------------------------------------------------------------------------
# Helper Functions: Docker
# -----------------------------------------------------------------------------
check_docker() {
  command -v docker &>/dev/null && docker --version &>/dev/null
}

get_docker_version() {
  docker --version 2>/dev/null || echo "Installed (version unavailable)"
}

install_docker() {
  echo "📦 Installing Docker..."
  if sudo apt-get update -y && sudo apt-get install -y docker.io; then
    echo "👤 Adding current user to docker group..."
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    return 0
  else
    echo "⚠️ Docker installation command failed."
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Helper Functions: Kind
# -----------------------------------------------------------------------------
check_kind() {
  command -v kind &>/dev/null && kind --version &>/dev/null
}

get_kind_version() {
  kind --version 2>/dev/null || echo "Installed (version unavailable)"
}

install_kind() {
  echo "📦 Installing Kind..."
  local ARCH
  ARCH=$(uname -m)
  local KIND_ARCH

  if [ "$ARCH" = "x86_64" ]; then
    KIND_ARCH="amd64"
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    KIND_ARCH="arm64"
  else
    echo "❌ Unsupported architecture for Kind: $ARCH"
    return 1
  fi

  rm -f ./kind
  if curl -fsSL -Lo ./kind "https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-${KIND_ARCH}"; then
    chmod +x ./kind
    if sudo mv ./kind /usr/local/bin/kind; then
      return 0
    else
      echo "⚠️ Failed to move Kind binary to /usr/local/bin/kind."
      rm -f ./kind
      return 1
    fi
  else
    echo "⚠️ Failed to download Kind binary."
    rm -f ./kind
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Helper Functions: kubectl
# -----------------------------------------------------------------------------
check_kubectl() {
  command -v kubectl &>/dev/null && kubectl version --client &>/dev/null
}

get_kubectl_version() {
  local ver
  ver=$(kubectl version --client 2>/dev/null | head -n 1)
  if [ -n "$ver" ]; then
    echo "$ver"
  else
    echo "Installed (version unavailable)"
  fi
}

install_kubectl() {
  echo "📦 Installing kubectl (latest stable version)..."
  local ARCH
  ARCH=$(uname -m)
  local KUBE_ARCH

  if [ "$ARCH" = "x86_64" ]; then
    KUBE_ARCH="amd64"
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    KUBE_ARCH="arm64"
  else
    echo "❌ Unsupported architecture for kubectl: $ARCH"
    return 1
  fi

  local VERSION
  VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || true)
  if [ -z "$VERSION" ]; then
    echo "⚠️ Could not fetch latest stable version tag for kubectl; falling back to v1.31.0."
    VERSION="v1.31.0"
  fi

  rm -f ./kubectl
  if curl -fsSL -Lo ./kubectl "https://dl.k8s.io/release/${VERSION}/bin/linux/${KUBE_ARCH}/kubectl"; then
    chmod +x ./kubectl
    if sudo mv ./kubectl /usr/local/bin/kubectl; then
      return 0
    else
      echo "⚠️ Failed to move kubectl binary to /usr/local/bin/kubectl."
      rm -f ./kubectl
      return 1
    fi
  else
    echo "⚠️ Failed to download kubectl binary."
    rm -f ./kubectl
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Execution: Attempt 1
# -----------------------------------------------------------------------------
echo "=================================================="
echo "▶ Running initial check and installation (Attempt 1)..."
echo "=================================================="

# 1. Docker
if check_docker; then
  echo "✅ Docker is already installed and verified ($(get_docker_version))."
  DOCKER_STATUS="SUCCESS"
else
  install_docker || true
  if check_docker; then
    echo "✅ Docker installed and verified successfully ($(get_docker_version))."
    DOCKER_STATUS="SUCCESS"
  else
    echo "❌ Docker verification failed on attempt 1."
    DOCKER_STATUS="FAILED"
  fi
fi

# 2. Kind
if check_kind; then
  echo "✅ Kind is already installed and verified ($(get_kind_version))."
  KIND_STATUS="SUCCESS"
else
  install_kind || true
  if check_kind; then
    echo "✅ Kind installed and verified successfully ($(get_kind_version))."
    KIND_STATUS="SUCCESS"
  else
    echo "❌ Kind verification failed on attempt 1."
    KIND_STATUS="FAILED"
  fi
fi

# 3. kubectl
if check_kubectl; then
  echo "✅ kubectl is already installed and verified ($(get_kubectl_version))."
  KUBECTL_STATUS="SUCCESS"
else
  install_kubectl || true
  if check_kubectl; then
    echo "✅ kubectl installed and verified successfully ($(get_kubectl_version))."
    KUBECTL_STATUS="SUCCESS"
  else
    echo "❌ kubectl verification failed on attempt 1."
    KUBECTL_STATUS="FAILED"
  fi
fi

# -----------------------------------------------------------------------------
# Execution: Attempt 2 (Retry on any failure)
# -----------------------------------------------------------------------------
if [ "$DOCKER_STATUS" = "FAILED" ] || [ "$KIND_STATUS" = "FAILED" ] || [ "$KUBECTL_STATUS" = "FAILED" ]; then
  echo
  echo "=================================================="
  echo "⚠️ Verification failed for one or more components on attempt 1."
  echo "🔄 Retrying installation for failed components (Attempt 2)..."
  echo "=================================================="
  sleep 2

  if [ "$DOCKER_STATUS" = "FAILED" ]; then
    echo
    echo "🔄 Retrying Docker installation..."
    install_docker || true
    if check_docker; then
      echo "✅ Docker installed and verified successfully on retry ($(get_docker_version))."
      DOCKER_STATUS="SUCCESS"
    else
      echo "❌ Docker verification failed on second attempt."
      DOCKER_STATUS="FAILED"
    fi
  fi

  if [ "$KIND_STATUS" = "FAILED" ]; then
    echo
    echo "🔄 Retrying Kind installation..."
    install_kind || true
    if check_kind; then
      echo "✅ Kind installed and verified successfully on retry ($(get_kind_version))."
      KIND_STATUS="SUCCESS"
    else
      echo "❌ Kind verification failed on second attempt."
      KIND_STATUS="FAILED"
    fi
  fi

  if [ "$KUBECTL_STATUS" = "FAILED" ]; then
    echo
    echo "🔄 Retrying kubectl installation..."
    install_kubectl || true
    if check_kubectl; then
      echo "✅ kubectl installed and verified successfully on retry ($(get_kubectl_version))."
      KUBECTL_STATUS="SUCCESS"
    else
      echo "❌ kubectl verification failed on second attempt."
      KUBECTL_STATUS="FAILED"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Final Evaluation & Reporting
# -----------------------------------------------------------------------------
if [ "$DOCKER_STATUS" = "FAILED" ] || [ "$KIND_STATUS" = "FAILED" ] || [ "$KUBECTL_STATUS" = "FAILED" ]; then
  echo
  echo "=================================================="
  echo "❌ Installation failed on second attempt!"
  echo "=================================================="
  echo "Component Status Report:"
  if [ "$DOCKER_STATUS" = "SUCCESS" ]; then
    echo "  ✅ Docker:  SUCCESS ($(get_docker_version))"
  else
    echo "  ❌ Docker:  FAILED"
  fi

  if [ "$KIND_STATUS" = "SUCCESS" ]; then
    echo "  ✅ Kind:    SUCCESS ($(get_kind_version))"
  else
    echo "  ❌ Kind:    FAILED"
  fi

  if [ "$KUBECTL_STATUS" = "SUCCESS" ]; then
    echo "  ✅ kubectl: SUCCESS ($(get_kubectl_version))"
  else
    echo "  ❌ kubectl: FAILED"
  fi
  echo "=================================================="
  echo "Please check the errors above, resolve any network or permission issues, and re-run the script."
  exit 1
fi

# -----------------------------------------------------------------------------
# Confirm Versions and Completion
# -----------------------------------------------------------------------------
echo
echo "🔍 Installed Versions:"
docker --version
kind --version
kubectl version --client --output=yaml

echo
echo "🎉 Docker, Kind, and kubectl installation complete!"
