# Homelab GitOps

Two-cluster Kubernetes homelab with GitOps.

## Architecture

```
Management (controller.local - Pi 5)     Apps (server.local - PC)
├── Argo CD (manages both)              ├── Prometheus
├── Grafana (central)                   └── Workloads
├── Prometheus
└── Pi-hole
```

## Quick Start

```bash
# 1. Fork and clone this repo
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# 2. Update GitHub username in YAML files
find . -name "*.yaml" -exec sed -i "s/YOUR_USERNAME/your-username/g" {} +
git add . && git commit -m "Configure" && git push

# 3. Bootstrap clusters
./bootstrap/01-bootstrap-mgmt.sh
./bootstrap/02-bootstrap-apps.sh
```

Access ArgoCD: `http://controller.local`

## Documentation

- [docs/quickstart.md](docs/quickstart.md) - Step-by-step setup
- [docs/sealed-secrets.md](docs/sealed-secrets.md) - Managing secrets

## Stack

k3s, ArgoCD, Prometheus/Grafana, cert-manager, external-dns, Sealed Secrets, Pi-hole
