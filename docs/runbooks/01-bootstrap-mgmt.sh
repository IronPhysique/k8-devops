#!/bin/bash
set -euo pipefail


# SSH configuration (key-based, non-interactive)
SSH_USER="${SSH_USER:-ryan}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab-k8}"

SSH_OPTS=(
  -i "${SSH_KEY}"
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=10
)

################################################################################
# Improved Bootstrap Script for the Management Cluster
#
# This script installs k3s on your Raspberry Pi management node, installs
# Traefik and Argo CD, and deploys the root GitOps application.  It is a
# drop‑in replacement for `01-bootstrap-mgmt.sh` that resolves several
# shortcomings in the original version:
#
#  • Reads configuration values from `config.env` automatically if present.
#    You no longer need to hard‑code IP addresses in the script.  The
#    variables `MGMT_IP`, `GITHUB_REPO` and `GITHUB_USERNAME` must be set in
#    your environment or defined in `config.env`.
#
#  • Passes the management IP into the remote installer via a positional
#    parameter.  The original script incorrectly used `${MGMT_IP}` inside a
#    single‑quoted heredoc, causing the literal string `${MGMT_IP}` to be
#    passed to k3s.  The improved version ensures the remote host uses the
#    correct IP for the TLS SAN.
#
#  • Uses a portable in‑place `sed` invocation so that the script works on
#    both GNU/Linux and macOS.  BSD sed requires an empty suffix when
#    performing in‑place substitutions.
#
#  • Replaces `YOUR_USERNAME` in the Argo CD root application with
#    `GITHUB_USERNAME` instead of mis‑deriving it from `GITHUB_REPO`.  This
#    ensures Argo CD checks out the correct GitHub repository.
#
# Usage:
#   chmod +x 01-bootstrap-mgmt.improved.sh
#   ./01-bootstrap-mgmt.improved.sh
################################################################################

# Try to source config.env from the project root.  We compute PROJECT_ROOT
# relative to this script's location.  If the file doesn't exist you can
# export the variables yourself before running the script.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/docs/runbooks}"
if [ -f "${PROJECT_ROOT}/config.env" ]; then
  # shellcheck source=/dev/null
  . "${PROJECT_ROOT}/config.env"
fi

# Ensure required variables are present.
: "${MGMT_IP:?MGMT_IP not set}"
: "${GITHUB_REPO:?GITHUB_REPO not set}"
: "${GITHUB_USERNAME:?GITHUB_USERNAME not set}"

echo "=== Phase 1: Bootstrap Management Cluster ==="
echo "Target: ${MGMT_IP}"
echo ""

###############################################
# Step 1: Install k3s on management node (Pi 5)
###############################################
echo "[1/6] Installing k3s on management cluster..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${MGMT_IP}" bash -s -- "${MGMT_IP}" <<'REMOTE_SCRIPT'
MGMT_IP="$1"

  set -euo pipefail
  # System preparation
  sudo apt update
  sudo apt install -y curl

  # Install k3s (control‑plane).  We disable the built‑in Traefik and
  # service‑loadbalancer because we manage ingress ourselves.  The
  # `--tls-san` option ensures that the API server advertises the LAN IP,
  # otherwise clients will default to 127.0.0.1 in the generated kubeconfig.
  curl -sfL https://get.k3s.io | sh -s - \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --disable servicelb \
    --tls-san "${MGMT_IP}" \
    --node-label "node-role.kubernetes.io/control-plane=true" \
    --node-label "homelab/cluster=mgmt"

  echo "Waiting for k3s to become ready..."
  until sudo k3s kubectl get nodes | grep -q Ready; do
    sleep 5
  done

  echo "k3s installed successfully"
REMOTE_SCRIPT

###################################################
# Step 2: Retrieve and fix the kubeconfig for mgmt
###################################################
echo "[2/6] Copying kubeconfig..."
mkdir -p "$HOME/.kube"
scp "${SSH_OPTS[@]}" "${SSH_USER}@${MGMT_IP}:/etc/rancher/k3s/k3s.yaml" "$HOME/.kube/config-mgmt"

# Use a sed invocation that works on both GNU and BSD sed.
if sed --version >/dev/null 2>&1; then
  SED_I=( -i )
else
  SED_I=( -i '' )
fi
# Replace localhost with the management IP so kubectl contacts the Pi.
sed "${SED_I[@]}" "s/127\.0\.0\.1/${MGMT_IP}/g" "$HOME/.kube/config-mgmt"
# Set appropriate permissions and export KUBECONFIG
chmod 600 "$HOME/.kube/config-mgmt"
export KUBECONFIG="$HOME/.kube/config-mgmt"

###############################################
# Step 3: Install Traefik for management cluster
###############################################
echo "[3/6] Installing Traefik..."
kubectl apply -f - <<'EOF_TRAEFIK'
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: traefik
  namespace: kube-system
spec:
  repo: https://traefik.github.io/charts
  chart: traefik
  targetNamespace: traefik
  valuesContent: |-
    ports:
      web:
        exposedPort: 80
      websecure:
        exposedPort: 443
      dns-tcp:
        port: 8053
        exposedPort: 53
        protocol: TCP
      dns-udp:
        port: 8054
        exposedPort: 53
        protocol: UDP
    service:
      type: LoadBalancer
EOF_TRAEFIK

echo "Waiting for Traefik to become ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=300s

###################################################
# Step 4: Install Argo CD on management cluster
###################################################
echo "[4/6] Installing Argo CD..."
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Apply any custom Argo CD configuration from bootstrap/argocd-install.yaml
kubectl apply -f "$PROJECT_ROOT/bootstrap/argocd-install.yaml"

echo "Waiting for Argo CD to become ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=600s

# Show initial password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo ""
echo "Argo CD admin password: ${ARGOCD_PASSWORD}"
echo "Save this password!"
echo ""

########################################################
# Step 5: Expose Argo CD via Traefik IngressRoute
########################################################
echo "[5/6] Exposing Argo CD UI..."
kubectl apply -f - <<'EOF_ARGO_INGRESS'
apiVersion: traefik.containo.us/v1alpha1
kind: IngressRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  entryPoints:
    - web
    - websecure
  routes:
    - match: Host(`argocd.mgmt.local`)
      kind: Rule
      services:
        - name: argocd-server
          port: 80
EOF_ARGO_INGRESS

echo "Argo CD UI: http://${MGMT_IP} (or http://argocd.mgmt.local if DNS configured)"

########################################################
# Step 6: Deploy the root Application (GitOps bootstrap)
########################################################
echo "[6/6] Deploying root Application..."

# Replace placeholder username with your actual GitHub username and apply
# through kubectl.  Using `${GITHUB_USERNAME}` ensures that Argo CD clones
# from `https://github.com/${GITHUB_USERNAME}/homelab.git`.
sed "s|YOUR_USERNAME|${GITHUB_USERNAME}|g" "$PROJECT_ROOT/bootstrap/root-app.yaml" | kubectl apply -f -

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
echo "Verify GitOps sync:"
echo "  kubectl get applications -n argocd"
echo ""
echo "Wait for all applications to sync (5-10 minutes):"
echo "  watch kubectl get applications -n argocd"
echo ""
echo "Next: Run 02-bootstrap-apps.improved.sh"
