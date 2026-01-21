#!/bin/bash
set -e

echo "╔════════════════════════════════════════════════════════╗"
echo "║        Sealed Secret Creator for Homelab              ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Prompt for inputs
read -p "Secret name: " SECRET_NAME
read -p "Namespace: " NAMESPACE
read -p "Secret key (e.g., api-token, password): " SECRET_KEY
read -sp "Secret value: " SECRET_VALUE
echo ""
read -p "Output file path (e.g., argocd/applications/mgmt/platform/my-app/sealed-secret.yaml): " OUTPUT_FILE

echo ""
echo "Creating sealed secret..."
echo "  Name: $SECRET_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Key: $SECRET_KEY"
echo ""

# Create temporary secret file
TMP_SECRET=$(mktemp)
cat > "$TMP_SECRET" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
type: Opaque
stringData:
  $SECRET_KEY: $SECRET_VALUE
EOF

# Create sealed secret
kubeseal \
  --controller-name=mgmt-sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format=yaml \
  < "$TMP_SECRET" \
  > "$OUTPUT_FILE"

# Clean up temporary file
rm "$TMP_SECRET"

echo "✅ Sealed secret created at: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the sealed secret: cat $OUTPUT_FILE"
echo "  2. Commit to git: git add $OUTPUT_FILE && git commit -m 'Add $SECRET_NAME sealed secret' && git push"
echo "  3. Apply to cluster: kubectl apply -f $OUTPUT_FILE"
echo ""
echo "⚠️  Note: The original secret value is NOT stored anywhere."
echo "    Only the encrypted SealedSecret is saved."
