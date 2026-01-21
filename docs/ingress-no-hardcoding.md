# Ingress Without Hardcoded Values

## Solution Overview

We've removed hardcoded IPs and hostnames from ingress resources by:

1. **Hostname**: external-dns automatically reads from `spec.rules[].host` - no annotation needed
2. **IP Address**: Configure Traefik to set ingress status with node IP, or use external-dns configuration

## Current Setup

### Ingress Resources
- ✅ No `external-dns.alpha.kubernetes.io/hostname` annotation (reads from spec)
- ✅ No `external-dns.alpha.kubernetes.io/target` annotation (auto-detects from ingress status)

### external-dns Configuration
- ✅ `publishInternalServices: true` - allows external-dns to work with internal services
- ✅ Reads hostname from ingress `spec.rules[].host` automatically

## Traefik Configuration (Required)

For external-dns to auto-detect the IP, Traefik needs to set the ingress status. Add this to Traefik's configuration:

```yaml
# In Traefik Helm values or ConfigMap
ingressRoute:
  kubernetes:
    ingressEndpoint:
      publishedService: traefik/traefik  # Points to Traefik service
```

Or if using k3s's built-in Traefik, you may need to configure it via:
- Traefik's `--ingress.ingressEndpoint.publishedService` flag
- Or set ingress status manually via a controller

## Alternative: Use Node IP in external-dns

If Traefik doesn't set ingress status, configure external-dns to use node IP:

```yaml
# In external-dns values
env:
  - name: EXTERNAL_DNS_SOURCE
    value: ingress
  # Or use a default target IP
  - name: EXTERNAL_DNS_TARGET_IP
    value: "192.168.178.144"  # From config.env MGMT_IP
```

## Template Usage

Copy `examples/ingress-reusable.yaml` and replace:
- `APP_NAME` → Your app name (e.g., "argocd", "grafana")
- `NAMESPACE` → Your namespace
- `SERVICE_NAME` → Your service name
- `SERVICE_PORT` → Your service port (usually 80)
- `HOSTNAME` → Your hostname (e.g., "argocd" becomes "argocd.iron-lab.org")

No IP or hostname annotations needed!
