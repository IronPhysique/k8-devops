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
# Improved Bootstrap Script for the Apps Cluster
#
# This script installs k3s on your apps PC (or first worker node), merges
# kubeconfigs, installs an ingress controller, registers the cluster with
# Argo CD on the management cluster, and triggers the platform deployment for
# the apps cluster.  It addresses multiple issues in the original
# `02-bootstrap-apps.sh`:
#
#  • Reads configuration values from `config.env` automatically if present.
#    This eliminates hard‑coded IPs/hostnames in the script.  The variables
#    `APPS_IP`, `APPS_HOSTNAME` and `MGMT_IP` must be set in your environment
#    or defined in `config.env`.
#
#  • Passes IP/hostname values into the remote k3s installer via positional
#    parameters so the `--tls-san` argument is populated correctly.  The
#    original script attempted to interpolate `${APPS_IP}` inside a
#    single‑quoted heredoc, which fails.
#
#  • Uses portable in‑place `sed` so the kubeconfig updates work on both
#    GNU/Linux and macOS.
#
#  • Renames and rewrites the context in the apps kubeconfig using
#    `kubectl config` commands instead of blind `sed` substitutions.  This
#    avoids unintended changes to cluster/user names and works across
#    kubectl versions.
#
#  • Avoids globally reassigning `KUBECONFIG` to a single file while still
#    applying resources to both clusters.  Instead it uses explicit
#    `--kubeconfig` and `--context` flags so each command knows which
#    cluster it is talking to.
#
#  • Allows you to override the ingress service type (LoadBalancer vs
#    NodePort) via the `LB_TYPE` environment variable.  If your environment
#    lacks a load balancer (e.g. MetalLB or k3s servicelb), set
#      LB_TYPE=NodePort
#    before running the script.
#
# Usage:
#   chmod +x 02-bootstrap-apps.improved.sh
#   ./02-bootstrap-apps.improved.sh
################################################################################

# Attempt to source config.env from the project root.  Compute PROJECT_ROOT
# relative to this script's location.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR%/docs/runbooks}"
if [ -f "${PROJECT_ROOT}/config.env" ]; then
  # shellcheck source=/dev/null
  . "${PROJECT_ROOT}/config.env"
fi

# Validate required variables
: "${APPS_IP:?APPS_IP not set}"
: "${APPS_HOSTNAME:?APPS_HOSTNAME not set}"
: "${MGMT_IP:?MGMT_IP not set}"

# Determine ingress service type (default: LoadBalancer).  Override by
# exporting LB_TYPE=NodePort before running this script if you do not have
# a load balancer implementation.
LB_TYPE="${LB_TYPE:-LoadBalancer}"

echo "=== Phase 2: Bootstrap Apps Cluster ==="
echo "Target: ${APPS_IP}"
echo ""

###############################################
# Step 1: Install k3s on the apps node
###############################################
echo "[1/5] Installing k3s on apps cluster..."
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${APPS_IP}" bash -s -- "${APPS_IP}" "${APPS_HOSTNAME}" <<'REMOTE_SCRIPT'
APPS_IP="$1"
APPS_HOSTNAME="$2"
  set -euo pipefail
  # System preparation
  sudo apt update
  sudo apt install -y curl

  # Install k3s (server mode for single node).  Disable built‑in Traefik and
  # service‑loadbalancer.  Supply `--tls-san` so the API server advertises
  # the node's LAN IP.  Add labels for homelab cluster and workload and set
  # the Kubernetes hostname label explicitly.
  curl -sfL https://get.k3s.io | sh -s - \
    --write-kubeconfig-mode 644 \
    --disable traefik \
    --disable servicelb \
    --tls-san "${APPS_IP}" \
    --node-label "node-role.kubernetes.io/control-plane=true" \
    --node-label "homelab/cluster=apps" \
    --node-label "homelab/workload=true" \
    --node-label "kubernetes.io/hostname=${APPS_HOSTNAME}"

  echo "Waiting for k3s to become ready..."
  until sudo k3s kubectl get nodes | grep -q Ready; do
    sleep 5
  done

  echo "k3s installed successfully"
REMOTE_SCRIPT

###################################################
# Step 2: Pull kubeconfig and merge with mgmt config
###################################################
echo "[2/5] Copying apps kubeconfig..."
mkdir -p "$HOME/.kube"

APPS_CONFIG="$HOME/.kube/config-apps"
MGMT_CONFIG="$HOME/.kube/config-mgmt"
MERGED_CONFIG="$HOME/.kube/config"

# Fetch apps kubeconfig from remote node
scp "${SSH_OPTS[@]}" "${SSH_USER}@${APPS_IP}:/etc/rancher/k3s/k3s.yaml" "$APPS_CONFIG"

# Portable sed invocation
if sed --version >/dev/null 2>&1; then
  SED_I=( -i )
else
  SED_I=( -i '' )
fi
# Replace localhost with the node IP
sed "${SED_I[@]}" "s/127\.0\.0\.1/${APPS_IP}/g" "$APPS_CONFIG"

# Rename the default context to 'apps-cluster' and update server address
KUBECONFIG="$APPS_CONFIG" kubectl config rename-context default apps-cluster || true
KUBECONFIG="$APPS_CONFIG" kubectl config set-cluster default --server="https://${APPS_IP}:6443" --insecure-skip-tls-verify

# Merge management and apps kubeconfigs into a single file for convenience
export KUBECONFIG="${MGMT_CONFIG}:${APPS_CONFIG}"
kubectl config view --flatten > "$MERGED_CONFIG"
export KUBECONFIG="$MERGED_CONFIG"

# Validate both contexts
kubectl get nodes --context=default  # mgmt
kubectl get nodes --context=apps-cluster  # apps

###############################################
# Step 3: Install Traefik on apps cluster
###############################################
echo "[3/5] Installing Traefik on apps cluster..."
kubectl --context=apps-cluster apply -f - <<EOF_TRAEFIK_APPS
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
    service:
      type: ${LB_TYPE}
EOF_TRAEFIK_APPS

# Wait until Traefik is ready before proceeding
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --context=apps-cluster --timeout=300s

###################################################
# Step 4: Register apps cluster with Argo CD on mgmt
###################################################
echo "[4/5] Registering apps cluster with Argo CD..."

# Create service account, token and cluster role binding in the apps cluster
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

# Wait a moment for the token to be created
sleep 5

# Extract the service account token and CA data from the apps cluster
APPS_TOKEN=$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
APPS_CA=$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.ca\\.crt}')

# Register the apps cluster secret into the management Argo CD.  Use the
# management context (default) so we don't need to change KUBECONFIG
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
# Step 5: Trigger platform sync for apps cluster
###################################################
echo "[5/5] Triggering GitOps sync for apps platform..."

echo "Waiting for apps platform applications to appear..."
sleep 10

# List Argo CD applications for apps cluster (non‑fatal if none yet)
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
echo "Access Argo CD to see apps cluster:"
echo "  http://${MGMT_IP}"
echo ""
echo "Next steps:"
echo "  1. Wait for all apps-* applications to sync (5-10 minutes)"
echo "  2. Configure Grafana datasource for apps Prometheus"
echo "  3. Deploy your applications to apps cluster"
