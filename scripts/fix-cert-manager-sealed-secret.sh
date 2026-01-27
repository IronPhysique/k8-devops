#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════╗"
echo "║   Fix Cert-Manager Cloudflare API Token Sealed Secret  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Determine which cluster to use
CLUSTER="${1:-mgmt}"
# Try to auto-detect controller name (could be sealed-secrets or mgmt-sealed-secrets)
CONTROLLER_NAMESPACE="sealed-secrets"
# Default to sealed-secrets, will auto-detect if not found
CONTROLLER_NAME="${2:-sealed-secrets}"

echo "Target cluster: ${CLUSTER}"
echo "Controller: ${CONTROLLER_NAME}"
echo ""

# Check if kubeseal is installed
if ! command -v kubeseal &> /dev/null; then
  echo "❌ Error: kubeseal is not installed"
  echo "   Install it from: https://github.com/bitnami-labs/sealed-secrets/releases"
  exit 1
fi

# Get Cloudflare API token from environment or prompt
if [ -z "$CLOUDFLARE_TOKEN" ]; then
  read -sp "Enter your Cloudflare API token: " CLOUDFLARE_TOKEN
  echo ""
  echo ""
fi

if [ -z "$CLOUDFLARE_TOKEN" ]; then
  echo "❌ Error: Cloudflare API token is required"
  echo "   Set CLOUDFLARE_TOKEN environment variable or enter it when prompted"
  exit 1
fi

# Set kubeconfig context if needed
if [ "$CLUSTER" = "apps" ]; then
  KUBECTL_CMD="kubectl --context=apps-cluster"
  KUBESEAL_CMD="kubeseal --controller-name=${CONTROLLER_NAME} --controller-namespace=${CONTROLLER_NAMESPACE} --context=apps-cluster"
  OUTPUT_FILE="argocd/applications/apps/platform/cert-manager/charts/templates/00-cloudflare-sealedsecret.yaml"
  NAMESPACE="cert-manager"
else
  KUBECTL_CMD="kubectl"
  KUBESEAL_CMD="kubeseal --controller-name=${CONTROLLER_NAME} --controller-namespace=${CONTROLLER_NAMESPACE}"
  OUTPUT_FILE="argocd/applications/mgmt/platform/cert-manager/charts/templates/00-cloudflare-sealedsecret.yaml"
  NAMESPACE="cert-manager"
fi

# Check if sealed-secrets controller is running
echo "[1/4] Checking sealed-secrets controller..."
if ! $KUBECTL_CMD get deployment -n ${CONTROLLER_NAMESPACE} ${CONTROLLER_NAME} &>/dev/null; then
  echo "⚠️  Warning: Sealed-secrets controller '${CONTROLLER_NAME}' not found in namespace '${CONTROLLER_NAMESPACE}'"
  echo "   Attempting to auto-detect controller name..."
  # Try to find the controller
  DETECTED_CONTROLLER=$($KUBECTL_CMD get deployment -n ${CONTROLLER_NAMESPACE} -o name 2>/dev/null | head -1 | sed 's|deployment.apps/||' || echo "")
  if [ -n "$DETECTED_CONTROLLER" ]; then
    CONTROLLER_NAME="$DETECTED_CONTROLLER"
    echo "   Using detected controller: ${CONTROLLER_NAME}"
  else
    echo "❌ Error: Could not find sealed-secrets controller"
    echo "   Make sure you're connected to the correct cluster and sealed-secrets is installed"
    exit 1
  fi
fi

echo "  ✅ Controller found: ${CONTROLLER_NAME}"

# Create temporary secret file
echo "[2/4] Creating temporary secret..."
TMP_SECRET=$(mktemp)
cat > "$TMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  api-token: ${CLOUDFLARE_TOKEN}
EOF

# Create sealed secret
echo "[3/4] Sealing secret with current controller key..."
$KUBESEAL_CMD \
  --format=yaml \
  < "$TMP_SECRET" \
  > "$OUTPUT_FILE"

# Clean up temporary file
rm "$TMP_SECRET"

echo "[4/4] ✅ Sealed secret created at: ${OUTPUT_FILE}"
echo ""
echo "Next steps:"
echo "  1. Review the sealed secret: cat ${OUTPUT_FILE}"
echo "  2. Commit to git: git add ${OUTPUT_FILE} && git commit -m 'Fix cert-manager Cloudflare sealed secret for ${CLUSTER} cluster' && git push"
echo "  3. ArgoCD will automatically sync and apply the new sealed secret"
echo ""
echo "⚠️  Note: The original API token value is NOT stored anywhere."
echo "    Only the encrypted SealedSecret is saved."
