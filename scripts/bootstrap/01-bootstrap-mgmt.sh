#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# SSH configuration (key-based, non-interactive)
# -----------------------------------------------------------------------------
SSH_USER="${SSH_USER:-ryan}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab-k8}"

SSH_OPTS=(
  -i "${SSH_KEY}"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

################################################################################
# Improved Bootstrap Script for the Management Cluster (Drop-in)
# - Forces clean reinstall of k3s to avoid old systemd ExecStart flags
# - Installs k3s with minimal safe flags (no advertise/node-ip)
# - Fixes kubeconfig server endpoint for remote kubectl usage
################################################################################

# Try to source config.env from the project root.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/scripts/bootstrap}"
if [ -f "${PROJECT_ROOT}/config.env" ]; then
  # shellcheck source=/dev/null
  . "${PROJECT_ROOT}/config.env"
fi

: "${MGMT_IP:?MGMT_IP not set}"
# Note: GITHUB_REPO and GITHUB_USERNAME are no longer required
# The repo URL is configured in argocd/bootstrap/applicationsets.yaml

LB_TYPE="${LB_TYPE:-NodePort}" # Set LB_TYPE=LoadBalancer if you have MetalLB, etc.

echo "=== Phase 1: Bootstrap Management Cluster ==="
echo "Target: ${MGMT_IP}"
echo ""

###############################################
# Step 1: Clean install k3s on management node
###############################################
echo "[1/6] Installing k3s on management cluster (clean reinstall)..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${MGMT_IP}" bash -s -- "${MGMT_IP}" <<'REMOTE_SCRIPT'
set -euo pipefail
MGMT_IP="$1"

echo "==> Removing any existing k3s (if present)..."
if [ -x /usr/local/bin/k3s-uninstall.sh ]; then
  sudo /usr/local/bin/k3s-uninstall.sh || true
fi

# Ensure service is not running/restarting with old args
sudo systemctl stop k3s 2>/dev/null || true
sudo systemctl disable k3s 2>/dev/null || true

# Remove unit file if it still exists for any reason
sudo rm -f /etc/systemd/system/k3s.service /etc/systemd/system/k3s.service.env 2>/dev/null || true
sudo systemctl daemon-reload || true

# Remove leftover state
sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s

echo "==> Installing dependencies..."
sudo apt update
sudo apt install -y curl

echo "==> Installing k3s (minimal safe flags)..."
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --tls-san "${MGMT_IP}" \
  --node-label "homelab/cluster=mgmt"

echo "==> Waiting for k3s service to be active..."
for i in {1..60}; do
  if sudo systemctl is-active --quiet k3s; then
    break
  fi
  sleep 2
done

if ! sudo systemctl is-active --quiet k3s; then
  echo "ERROR: k3s service is not active"
  sudo systemctl status k3s --no-pager -l | tail -n 120 || true
  sudo journalctl -u k3s --no-pager -n 200 || true
  exit 1
fi

echo "==> Waiting for node to become Ready..."
for i in {1..120}; do
  status="$(sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' | head -n1 || true)"
  echo "  node status: ${status:-unknown}"
  if echo "$status" | grep -q "Ready"; then
    echo "k3s installed successfully"
    exit 0
  fi
  sleep 2
done

echo "ERROR: Timed out waiting for node Ready"
sudo k3s kubectl get nodes -o wide || true
sudo systemctl status k3s --no-pager -l | tail -n 120 || true
sudo journalctl -u k3s --no-pager -n 200 || true
exit 1
REMOTE_SCRIPT

###################################################
# Step 2: Retrieve and fix the kubeconfig for mgmt
###################################################
echo "[2/6] Copying kubeconfig..."
mkdir -p "$HOME/.kube"
scp "${SSH_OPTS[@]}" "${SSH_USER}@${MGMT_IP}:/etc/rancher/k3s/k3s.yaml" "$HOME/.kube/config-mgmt"

# Portable sed -i
if sed --version >/dev/null 2>&1; then
  SED_I=( -i )
else
  SED_I=( -i '' )
fi

# Fix ONLY the server line
sed "${SED_I[@]}" \
  "s#^\\( *server: \\)https://127\\.0\\.0\\.1:6443#\\1https://${MGMT_IP}:6443#g" \
  "$HOME/.kube/config-mgmt"

chmod 600 "$HOME/.kube/config-mgmt"
export KUBECONFIG="$HOME/.kube/config-mgmt"

echo "Kubeconfig server endpoint:"
kubectl config view --minify --raw | awk '/server:/{print}'

###################################################
# Step 3: Install Argo CD on management cluster
###################################################
echo "[3/6] Installing Argo CD..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f "$PROJECT_ROOT/scripts/bootstrap/argocd-install.yaml"

echo "Waiting for Argo CD to become ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=600s

ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "Argo CD admin password: ${ARGOCD_PASSWORD}"
echo "Save this password!"
echo ""

########################################################
# Step 4: Deploy AppProjects and ApplicationSets (GitOps bootstrap)
########################################################
echo "[4/6] Deploying AppProjects and ApplicationSets..."
kubectl apply -f "$PROJECT_ROOT/argocd/bootstrap/projects.yaml"
# Note: applicationsets.yaml is now disabled - ApplicationSets cannot be deployed via Application
# ApplicationSets are cluster-scoped resources and must be applied directly
# kubectl apply -f "$PROJECT_ROOT/argocd/bootstrap/applicationsets.yaml"
kubectl apply -f "$PROJECT_ROOT/argocd/applicationsets/"
# Apply ApplicationSets from applications directory
for appsets in "$PROJECT_ROOT/argocd/applications/mgmt/platform"/*/*.yaml \
               "$PROJECT_ROOT/argocd/applications/apps/platform"/*/*.yaml \
               "$PROJECT_ROOT/argocd/applications/apps/services"/*/*.yaml; do
  if [[ -f "$appsets" ]] && \
     [[ "$appsets" != *"ingress.yaml" ]] && \
     [[ "$appsets" != *"ingress-resource.yaml" ]] && \
     [[ "$appsets" != *"values.yaml" ]] && \
     [[ "$appsets" != *"Chart.yaml" ]] && \
     [[ "$appsets" != *"sealedsecret"* ]] && \
     [[ "$appsets" != *"manifests"* ]] && \
     [[ "$appsets" != *"dashboards"* ]] && \
     [[ "$appsets" != *"templates"* ]]; then
    kubectl apply -f "$appsets" || echo "Warning: Failed to apply $appsets"
  fi
done

echo "Waiting for ApplicationSets to be ready..."
sleep 5
kubectl wait --for=condition=ready applicationset -n argocd --all --timeout=60s || true

echo "Waiting for ApplicationSets to generate Applications..."
echo "  (This may take 30-60 seconds for Git repo sync)"
for i in {1..12}; do
  APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")
  echo "  Applications found: ${APP_COUNT} (attempt $i/12)"
  if [ "${APP_COUNT}" -gt "0" ]; then
    echo "  ✅ Applications detected!"
    break
  fi
  sleep 5
done

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Management cluster is ready!"
echo ""
echo "Access Argo CD:"
echo "  URL: http://${MGMT_IP}"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "⚠️  IMPORTANT: Configure Git repo access in ArgoCD:"
echo "  1. Go to Settings > Repositories"
echo "  2. Add your Git repo (SSH or HTTPS with credentials)"
echo "  3. Applications will start syncing automatically"
echo ""
echo "Verify GitOps sync:"
echo "  kubectl get applications -n argocd"
echo "  kubectl get applicationsets -n argocd"
echo ""
echo "Next: Run 02-bootstrap-apps.sh"
