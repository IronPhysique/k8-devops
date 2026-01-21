# Nginx Router

HTTP/HTTPS reverse proxy for homelab services using name-based virtual hosting.

## Current Configuration

**Port 80 (HTTP)** and **Port 443 (HTTPS)** are exposed via `hostNetwork` on the mgmt cluster.

### Routed Services
- **argocd.home** → ArgoCD UI
- **pihole.home** → Pi-hole Admin Interface
- **grafana.home** → Grafana Dashboards
- **amp.home** → AMP Game Server Manager

## TLS/SSL Configuration

Currently using **self-signed certificates** valid for 10 years.

### Why Not Let's Encrypt?

Let's Encrypt cannot be used for `.home` domains because:
1. `.home` domains are not publicly routable
2. Let's Encrypt requires either:
   - **HTTP-01 challenge**: Requires port 80 to be publicly accessible
   - **DNS-01 challenge**: Requires DNS provider API access for public domain

### To Use Let's Encrypt (Optional Future Enhancement)

If you want proper Let's Encrypt certificates, you would need to:
1. Purchase a public domain (e.g., `yourdomain.com`)
2. Use DNS-01 challenge with a supported DNS provider (Cloudflare, Route53, etc.)
3. Configure cert-manager with ACME DNS-01 issuer
4. Update nginx-router to use the cert-manager generated certificates

Example cert-manager configuration for Let's Encrypt with Cloudflare:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

## Certificate Regeneration

To regenerate the self-signed certificate:
```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout tls.key \
  -out tls.crt \
  -subj "/CN=*.home/O=homelab" \
  -addext "subjectAltName=DNS:*.home,DNS:argocd.home,DNS:pihole.home,DNS:grafana.home,DNS:amp.home"

kubectl create secret tls home-tls \
  --key=tls.key \
  --cert=tls.crt \
  -n nginx-router \
  --dry-run=client -o yaml > manifests/base/tls-secret.yaml
```

## Port Configuration

**Port 443 was chosen over 8443** because:
- Standard HTTPS port (no need to specify port in URLs)
- Pi-hole HTTPS was disabled (`webHttps: ""`) to free up port 443
- Browser compatibility (some browsers/apps assume port 443 for HTTPS)
