#!/bin/bash

# Ensure /usr/local/bin is in PATH for this script session
export PATH="/usr/local/bin:$PATH"
set -o pipefail

# Clean up temporary download files on exit
cleanup() {
  rm -f ./minikube ./kubectl
}
trap cleanup EXIT

echo "🚀 Starting installation and verification of Docker, Minikube, and kubectl..."
echo

# -----------------------------------------------------------------------------
# Pre-requisite Check: Virtualization Support
# -----------------------------------------------------------------------------
check_virtualization() {
  echo "🔍 Checking virtualization support..."
  if [ -f /proc/cpuinfo ]; then
    local vmx_count
    vmx_count=$(grep -Ec '(vmx|svm)' /proc/cpuinfo 2>/dev/null || echo 0)
    if [ "$vmx_count" -gt 0 ]; then
      echo "  ℹ️ Virtualization support is enabled ($vmx_count CPU threads supporting VT-x/AMD-V)."
    else
      echo "  ⚠️ Virtualization support (VMX/SVM) not detected in /proc/cpuinfo."
      echo "     Minikube will run using the Docker container driver without hardware VM acceleration."
    fi
  else
    echo "  ℹ️ /proc/cpuinfo not available; skipping virtualization check."
  fi
  echo
}

# -----------------------------------------------------------------------------
# Helper Functions: Docker & Required Packages
# -----------------------------------------------------------------------------
check_docker() {
  command -v docker &>/dev/null && docker --version &>/dev/null
}

get_docker_version() {
  docker --version 2>/dev/null || echo "Installed (version unavailable)"
}

install_docker() {
  echo "📦 Updating packages and installing required packages (curl, wget, apt-transport-https) and Docker..."
  if sudo apt-get update -y && sudo apt-get install -y curl wget apt-transport-https docker.io; then
    echo "👤 Adding current user ($USER) to docker group..."
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    return 0
  else
    echo "⚠️ Docker and dependencies installation command failed."
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Helper Functions: Minikube
# -----------------------------------------------------------------------------
check_minikube() {
  command -v minikube &>/dev/null && minikube version &>/dev/null
}

get_minikube_version() {
  local ver
  ver=$(minikube version 2>/dev/null | head -n 1)
  if [ -n "$ver" ]; then
    echo "$ver"
  else
    echo "Installed (version unavailable)"
  fi
}

install_minikube() {
  echo "📦 Installing Minikube..."
  local ARCH
  ARCH=$(uname -m)
  local MINIKUBE_ARCH

  if [ "$ARCH" = "x86_64" ]; then
    MINIKUBE_ARCH="amd64"
  elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    MINIKUBE_ARCH="arm64"
  else
    echo "❌ Unsupported architecture for Minikube: $ARCH"
    return 1
  fi

  rm -f ./minikube
  if curl -fsSL -Lo ./minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${MINIKUBE_ARCH}"; then
    chmod +x ./minikube
    if sudo mv ./minikube /usr/local/bin/minikube; then
      return 0
    else
      echo "⚠️ Failed to move Minikube binary to /usr/local/bin/minikube."
      rm -f ./minikube
      return 1
    fi
  else
    echo "⚠️ Failed to download Minikube binary."
    rm -f ./minikube
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
check_virtualization

echo "=================================================="
echo "▶ Running initial check and installation (Attempt 1)..."
echo "=================================================="

# 1. Docker & Required Packages
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

# 2. Minikube
if check_minikube; then
  echo "✅ Minikube is already installed and verified ($(get_minikube_version))."
  MINIKUBE_STATUS="SUCCESS"
else
  install_minikube || true
  if check_minikube; then
    echo "✅ Minikube installed and verified successfully ($(get_minikube_version))."
    MINIKUBE_STATUS="SUCCESS"
  else
    echo "❌ Minikube verification failed on attempt 1."
    MINIKUBE_STATUS="FAILED"
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
if [ "$DOCKER_STATUS" = "FAILED" ] || [ "$MINIKUBE_STATUS" = "FAILED" ] || [ "$KUBECTL_STATUS" = "FAILED" ]; then
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

  if [ "$MINIKUBE_STATUS" = "FAILED" ]; then
    echo
    echo "🔄 Retrying Minikube installation..."
    install_minikube || true
    if check_minikube; then
      echo "✅ Minikube installed and verified successfully on retry ($(get_minikube_version))."
      MINIKUBE_STATUS="SUCCESS"
    else
      echo "❌ Minikube verification failed on second attempt."
      MINIKUBE_STATUS="FAILED"
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
if [ "$DOCKER_STATUS" = "FAILED" ] || [ "$MINIKUBE_STATUS" = "FAILED" ] || [ "$KUBECTL_STATUS" = "FAILED" ]; then
  echo
  echo "=================================================="
  echo "❌ Installation failed on second attempt!"
  echo "=================================================="
  echo "Component Status Report:"
  if [ "$DOCKER_STATUS" = "SUCCESS" ]; then
    echo "  ✅ Docker:    SUCCESS ($(get_docker_version))"
  else
    echo "  ❌ Docker:    FAILED"
  fi

  if [ "$MINIKUBE_STATUS" = "SUCCESS" ]; then
    echo "  ✅ Minikube:  SUCCESS ($(get_minikube_version))"
  else
    echo "  ❌ Minikube:  FAILED"
  fi

  if [ "$KUBECTL_STATUS" = "SUCCESS" ]; then
    echo "  ✅ kubectl:   SUCCESS ($(get_kubectl_version))"
  else
    echo "  ❌ kubectl:   FAILED"
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
minikube version
kubectl version --client --output=yaml

echo
echo "🎉 Docker, Minikube, and kubectl installation complete!"
echo
echo "💡 Next Steps:"
echo "   1. If user was just added to docker group, refresh group membership:"
echo "      newgrp docker"
echo "      (or log out and log back in)"
echo "   2. Start Minikube cluster (using Docker driver as per minikube_installation.md):"
echo "      minikube start --driver=docker --vm=true"
echo "   3. Verify cluster status:"
echo "      minikube status"
echo "      kubectl get nodes"
echo "   4. Stop or delete cluster when finished:"
echo "      minikube stop"
echo "      minikube delete"
