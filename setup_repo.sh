#!/bin/bash
set -euo pipefail

# =============================================================================
# Generic RunPod Repository Setup Script
# =============================================================================
# Required Environment Variables:
#   - GIT_SSH_KEY_B64: Base64-encoded SSH private key for GitHub
#   - REPO_NAME: Name of the repository (e.g., "AE-Scientist")
#   - REPO_ORG: GitHub organization (default: "agencyenterprise")
#   - REPO_BRANCH: Branch to checkout (default: "main")
#   - REPO_STARTUP_CMD: Command to run after setup (optional)
# =============================================================================

# Set defaults
REPO_ORG="${REPO_ORG:-agencyenterprise}"
REPO_BRANCH="${REPO_BRANCH:-main}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"

# Validate required variables
: "${GIT_SSH_KEY_B64:?ERROR: GIT_SSH_KEY_B64 environment variable not set}"
: "${REPO_NAME:?ERROR: REPO_NAME environment variable not set}"

echo "========================================"
echo "🚀 RunPod Setup: ${REPO_NAME}"
echo "========================================"
echo "Organization: ${REPO_ORG}"
echo "Branch: ${REPO_BRANCH}"
echo "Workspace: ${WORKSPACE_DIR}"
echo ""

# =============================================================================
# Step 1: Install Git and SSH if not present
# =============================================================================
echo "Step 1: Ensuring git and SSH client are installed..."
if ! command -v git >/dev/null 2>&1; then
  echo "  Installing git and openssh-client..."
  apt-get update -y && apt-get install -y git openssh-client
else
  echo "  ✓ git already installed"
fi

# =============================================================================
# Step 2: Configure SSH for GitHub
# =============================================================================
echo ""
echo "Step 2: Configuring SSH for GitHub..."

mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add GitHub to known hosts
if ! grep -q "github.com" ~/.ssh/known_hosts 2>/dev/null; then
  echo "  Adding GitHub to known hosts..."
  ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
  chmod 644 ~/.ssh/known_hosts
else
  echo "  ✓ GitHub already in known hosts"
fi

# Decode and save SSH key
echo "  Decoding SSH deploy key..."
echo "$GIT_SSH_KEY_B64" | base64 -d > ~/.ssh/id_deploy_runpod
chmod 600 ~/.ssh/id_deploy_runpod

# Configure SSH config with unique host alias
SSH_HOST_ALIAS="github.com-runpod-${REPO_NAME}"
if ! grep -q "Host ${SSH_HOST_ALIAS}" ~/.ssh/config 2>/dev/null; then
  echo "  Writing SSH config..."
  cat >> ~/.ssh/config <<EOF
Host ${SSH_HOST_ALIAS}
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_deploy_runpod
  IdentitiesOnly yes
EOF
  chmod 600 ~/.ssh/config
else
  echo "  ✓ SSH config already exists"
fi

# Set git config
git config --global user.name "RunPod Worker" 2>/dev/null || true
git config --global user.email "runpod@local" 2>/dev/null || true

echo "  ✓ SSH configured"

# =============================================================================
# Step 3: Test SSH connection
# =============================================================================
echo ""
echo "Step 3: Testing SSH connection to GitHub..."
if ssh -T git@${SSH_HOST_ALIAS} </dev/null 2>&1 | grep -q "successfully authenticated"; then
  echo "  ✅ SSH authentication successful!"
else
  echo "  ⚠️  SSH test gave unexpected output, but continuing..."
fi

# =============================================================================
# Step 4: Clone or update repository
# =============================================================================
echo ""
echo "Step 4: Setting up ${REPO_NAME} repository..."

REPO_DIR="${WORKSPACE_DIR}/${REPO_NAME}"
REPO_URL="git@${SSH_HOST_ALIAS}:${REPO_ORG}/${REPO_NAME}.git"

if [ -d "$REPO_DIR" ]; then
  echo "  Repository directory exists, updating..."
  cd "$REPO_DIR"
  
  # Fetch latest changes
  echo "  Fetching latest changes..."
  git fetch origin
  
  # Check if we're on the right branch
  CURRENT_BRANCH=$(git branch --show-current)
  if [ "$CURRENT_BRANCH" != "$REPO_BRANCH" ]; then
    echo "  Switching to branch $REPO_BRANCH..."
    git checkout "$REPO_BRANCH"
  fi
  
  # Pull latest changes
  echo "  Pulling latest changes..."
  git pull origin "$REPO_BRANCH"
  
  echo "  ✓ Repository updated"
else
  echo "  Cloning repository..."
  mkdir -p "$WORKSPACE_DIR"
  cd "$WORKSPACE_DIR"
  git clone "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
  
  echo "  Checking out branch $REPO_BRANCH..."
  git fetch origin "$REPO_BRANCH"
  git checkout "$REPO_BRANCH"
  
  echo "  ✓ Repository cloned"
fi

# =============================================================================
# Step 5: Run startup command if provided
# =============================================================================
echo ""
echo "✓ Repository setup complete! Repository ready at: ${REPO_DIR}"
echo ""