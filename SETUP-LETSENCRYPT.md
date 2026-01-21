# Let's Encrypt Setup with Cloudflare

This guide will set up automatic Let's Encrypt certificates and DNS management for iron-lab.org.

## Prerequisites

1. **Cloudflare Account** with iron-lab.org domain
2. **Cloudflare API Token** with DNS edit permissions
3. **Public IP** or port forwarding configured for your homelab

## Step 1: Create Cloudflare API Token

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → My Profile → API Tokens
2. Click "Create Token"
3. Use the "Edit zone DNS" template
4. Configure:
   - **Permissions**: Zone - DNS - Edit
   - **Zone Resources**: Include - Specific zone - iron-lab.org
5. Copy the API token (you'll only see it once!)

## Step 2: Create Sealed Secret for API Token

```bash
# Create a temporary secret file (DO NOT commit this!)
cat > /tmp/cloudflare-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: cert-manager
type: Opaque
stringData:
  api-token: YOUR_CLOUDFLARE_API_TOKEN_HERE
EOF

# Create sealed secret using kubeseal
kubeseal --format=yaml < /tmp/cloudflare-secret.yaml > argocd/applications/mgmt/platform/cert-manager/cloudflare-api-token-sealedsecret.yaml

# Clean up temporary file
rm /tmp/cloudflare-secret.yaml

# Also create for external-dns namespace
cat > /tmp/cloudflare-secret-extdns.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-api-token
  namespace: external-dns
type: Opaque
stringData:
  api-token: YOUR_CLOUDFLARE_API_TOKEN_HERE
EOF

kubeseal --format=yaml < /tmp/cloudflare-secret-extdns.yaml > argocd/applications/mgmt/platform/external-dns/cloudflare-api-token-sealedsecret.yaml
rm /tmp/cloudflare-secret-extdns.yaml
```

## Step 3: Apply Sealed Secrets

```bash
# Apply the sealed secrets
kubectl apply -f argocd/applications/mgmt/platform/cert-manager/cloudflare-api-token-sealedsecret.yaml
kubectl apply -f argocd/applications/mgmt/platform/external-dns/cloudflare-api-token-sealedsecret.yaml
```

## Step 4: Deploy cert-manager and ExternalDNS

```bash
# Apply ExternalDNS application
kubectl apply -f argocd/applications/mgmt/platform/external-dns/application.yaml

# Apply Let's Encrypt issuers
kubectl apply -f argocd/applications/mgmt/platform/cert-manager/letsencrypt-issuer.yaml

# Apply certificate request
kubectl apply -f argocd/applications/mgmt/platform/cert-manager/certificate.yaml
```

## Step 5: Configure Cloudflare DNS (if not using ExternalDNS automation)

If ExternalDNS doesn't work or you prefer manual DNS, create these A records in Cloudflare:

```
argocd.iron-lab.org   → YOUR_PUBLIC_IP
pihole.iron-lab.org   → YOUR_PUBLIC_IP
grafana.iron-lab.org  → YOUR_PUBLIC_IP
amp.iron-lab.org      → YOUR_PUBLIC_IP
```

**Important**: Disable Cloudflare proxy (orange cloud) for these records initially, or configure Authenticated Origin Pulls.

## Step 6: Update nginx to use Let's Encrypt certificates

Once the certificate is issued, update nginx deployment to use the new secret:

```yaml
# In nginx-router deployment, change:
volumes:
  - name: tls-certs
    secret:
      secretName: iron-lab-org-tls  # Changed from home-tls
```

## Step 7: Port Forwarding

Configure your router to forward ports to `192.168.178.144`:
- Port 80 (HTTP) → 192.168.178.144:80
- Port 443 (HTTPS) → 192.168.178.144:443

## Verification

```bash
# Check certificate status
kubectl get certificate -n nginx-router iron-lab-org-tls

# Check certificate details
kubectl describe certificate -n nginx-router iron-lab-org-tls

# Check ExternalDNS logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns

# Test HTTPS
curl https://argocd.iron-lab.org
```

## Automatic DNS with ExternalDNS

ExternalDNS will automatically:
1. Read the nginx-router-external service annotations
2. Create A records in Cloudflare for all domains listed
3. Point them to the service's external IP
4. Keep them updated if IPs change

## Troubleshooting

**Certificate stuck in Pending**:
```bash
kubectl describe certificate -n nginx-router iron-lab-org-tls
kubectl get challenges -n nginx-router
kubectl describe challenges -n nginx-router <challenge-name>
```

**ExternalDNS not creating records**:
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50
```

**DNS-01 challenge failing**:
- Verify Cloudflare API token has DNS edit permissions
- Check the cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
- Ensure iron-lab.org is correctly configured in Cloudflare

## Security Notes

1. **Never commit the Cloudflare API token** - always use SealedSecrets
2. **Use staging issuer first** to avoid Let's Encrypt rate limits
3. **Monitor certificate expiry** - cert-manager auto-renews 30 days before expiry
4. **Keep API token secret safe** - it has DNS edit permissions for your domain
