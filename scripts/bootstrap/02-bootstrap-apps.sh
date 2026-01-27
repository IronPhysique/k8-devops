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
# Improved Bootstrap Script for the Apps Cluster
################################################################################

# Attempt to source config.env from the project root. Compute PROJECT_ROOT
# relative to this script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/scripts/bootstrap}"
if [ -f "${PROJECT_ROOT}/config.env" ]; then
  # shellcheck source=/dev/null
  . "${PROJECT_ROOT}/config.env"
fi

# Validate required variables
: "${APPS_IP:?APPS_IP not set}"
: "${APPS_HOSTNAME:?APPS_HOSTNAME not set}"
: "${MGMT_IP:?MGMT_IP not set}"

# Ingress service type:
# - NodePort works everywhere
# - LoadBalancer only works if you have MetalLB / other LB implementation
LB_TYPE="${LB_TYPE:-NodePort}"

echo "=== Phase 2: Bootstrap Apps Cluster ==="
echo "Target: ${APPS_IP}"
echo ""

###############################################
# Step 1: Install k3s on the apps node
###############################################
echo "[1/5] Installing k3s on apps cluster..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${APPS_IP}" bash -s -- "${APPS_IP}" "${APPS_HOSTNAME}" <<'REMOTE_SCRIPT'
set -euo pipefail
APPS_IP="$1"
APPS_HOSTNAME="$2"

# System preparation
sudo apt update
sudo apt install -y curl

# Install k3s (server mode, single node for now)
# NOTE: --advertise-address/--node-ip helps ensure kubeconfig points to LAN IP
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --tls-san "${APPS_IP}" \
  --advertise-address "${APPS_IP}" \
  --node-ip "${APPS_IP}" \
  --node-label "homelab/cluster=apps" \
  --node-label "homelab/workload=true"

echo "Waiting for k3s to become ready..."
until sudo k3s kubectl get nodes 2>/dev/null | grep -q Ready; do
  sleep 5
done

echo "k3s installed successfully"
REMOTE_SCRIPT

###################################################
# Step 2: Pull kubeconfig and merge with mgmt config
###################################################
echo "[2/5] Copying apps kubeconfig..."
mkdir -p "$HOME/.kube"

APPS_CONFIG="$HOME/.kube/config-apps"
MGMT_CONFIG="$HOME/.kube/config-mgmt"
MERGED_CONFIG="$HOME/.kube/config"

# Fetch apps kubeconfig from remote node
scp "${SSH_OPTS[@]}" "${SSH_USER}@${APPS_IP}:/etc/rancher/k3s/k3s.yaml" "$APPS_CONFIG"

# Portable sed invocation for macOS/Linux
if sed --version >/dev/null 2>&1; then
  SED_I=( -i )
else
  SED_I=( -i '' )
fi

# Fix ONLY the server line (k3s default uses 127.0.0.1)
sed "${SED_I[@]}" \
  "s#^\\( *server: \\)https://127\\.0\\.0\\.1:6443#\\1https://${APPS_IP}:6443#g" \
  "$APPS_CONFIG"

chmod 600 "$APPS_CONFIG"

# Rename the default context to 'apps-cluster'
KUBECONFIG="$APPS_CONFIG" kubectl config rename-context default apps-cluster 2>/dev/null || true

# Merge management and apps kubeconfigs into a single file for convenience
export KUBECONFIG="${MGMT_CONFIG}:${APPS_CONFIG}"
kubectl config view --flatten > "$MERGED_CONFIG"
export KUBECONFIG="$MERGED_CONFIG"

echo "Contexts:"
kubectl config get-contexts

# Validate both contexts
kubectl get nodes --context=default         # mgmt
kubectl get nodes --context=apps-cluster    # apps

###################################################
# Step 3: Register apps cluster with Argo CD on mgmt
###################################################
echo "[3/5] Registering apps cluster with Argo CD..."

kubectl --context=apps-cluster apply -f - <<'EOF_APPS_SA'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF_APPS_SA

sleep 5

APPS_TOKEN="$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)"
APPS_CA="$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.ca\.crt}')"

kubectl --context=default apply -f - <<EOF_CLUSTER_SECRET
apiVersion: v1
kind: Secret
metadata:
  name: apps-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
  annotations:
    managed-by: homelab-bootstrap
type: Opaque
stringData:
  name: apps-cluster
  server: https://${APPS_IP}:6443
  config: |
    {
      "bearerToken": "${APPS_TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${APPS_CA}"
      }
    }
EOF_CLUSTER_SECRET

echo "Apps cluster registered with Argo CD"

###################################################
# Step 4: Trigger platform sync for apps cluster
###################################################
echo "[4/5] Triggering GitOps sync for apps platform..."

echo "Waiting for apps platform applications to appear..."
sleep 10

kubectl get applications -n argocd | grep apps- || true

echo ""
echo "=== Apps Cluster Bootstrap Complete ==="
echo ""
echo "Verify both clusters:"
echo "  kubectl get nodes --context=default         # mgmt cluster"
echo "  kubectl get nodes --context=apps-cluster    # apps cluster"
echo ""
echo "Watch apps platform sync:"
echo "  watch kubectl get applications -n argocd"
echo ""
echo "Access Argo CD:"
echo "  http://${MGMT_IP}"
echo ""
echo "Next steps:"
echo "  1. Wait for all apps-* applications to sync (5-10 minutes)"
echo "  2. Configure Grafana datasource for apps Prometheus"
echo "  3. Deploy your applications to apps cluster"
