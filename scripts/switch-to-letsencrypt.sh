#!/bin/bash
set -e

echo "Switching nginx-router to use Let's Encrypt certificate..."
echo ""

# Check if certificate exists and is ready
CERT_STATUS=$(kubectl get certificate -n nginx-router iron-lab-org-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")

if [ "$CERT_STATUS" != "True" ]; then
    echo "❌ Let's Encrypt certificate is not ready yet!"
    echo ""
    echo "Current status:"
    kubectl get certificate -n nginx-router iron-lab-org-tls 2>/dev/null || echo "Certificate not found"
    echo ""
    echo "Check certificate details:"
    echo "  kubectl describe certificate -n nginx-router iron-lab-org-tls"
    echo ""
    echo "Check cert-manager logs:"
    echo "  kubectl logs -n cert-manager -l app=cert-manager"
    exit 1
fi

echo "✅ Let's Encrypt certificate is ready!"
echo ""

# Update deployment to use Let's Encrypt certificate
echo "Updating nginx-router deployment..."
kubectl patch deployment -n nginx-router nginx-router --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/volumes/1/secret/secretName",
    "value": "iron-lab-org-tls"
  }
]'

echo ""
echo "✅ Deployment updated!"
echo ""
echo "Waiting for pods to restart..."
sleep 10

# Check pod status
kubectl get pods -n nginx-router

echo ""
echo "✅ Done! Your services now use Let's Encrypt certificates:"
echo "  - https://argocd.iron-lab.org"
echo "  - https://pihole.iron-lab.org"
echo "  - https://grafana.iron-lab.org"
echo "  - https://amp.iron-lab.org"
