# Quick Start

## Prerequisites

- Raspberry Pi 5 with Ubuntu (controller.local)
- PC with Ubuntu (server.local)  
- Static IPs via DHCP
- SSH access to both
- Fork this repository

## Setup

```bash
# 1. Clone your fork
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# 2. Update GitHub username
find . -name "*.yaml" -exec sed -i "s/YOUR_USERNAME/your-username/g" {} +
git add . && git commit -m "Configure" && git push

# 3. Bootstrap management cluster
./bootstrap/01-bootstrap-mgmt.sh

# 4. Bootstrap apps cluster
./bootstrap/02-bootstrap-apps.sh
```

## Access

- **ArgoCD:** `http://controller.local` (password shown after Step 3)
- **Grafana:** Port-forward via `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
- **Pi-hole:** `http://pihole.local/admin`

## Deploy Apps

All configuration is in `argocd/applications/`. ArgoCD auto-syncs changes from Git.

See existing apps in `argocd/applications/apps/services/` for examples.

## Manage Secrets

See [sealed-secrets.md](sealed-secrets.md)
