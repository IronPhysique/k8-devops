# Homelab GitOps

Two-cluster Kubernetes homelab with GitOps, per-cluster monitoring, and easy scaling.

## Architecture

```
Management (controller.local - Pi 5)     Apps (server.local - PC)
├── Argo CD (manages both)              ├── Prometheus
├── Grafana (central)                   └── Workloads (scalable)
├── Prometheus
└── Pi-hole
```

## Quick Start

```bash
# 1. Setup
cp config.env.example config.env
vim config.env  # Set MGMT_IP, APPS_IP, GITHUB_USERNAME

# 2. Configure
source config.env
find . -name "*.yaml" -exec sed -i "s/YOUR_USERNAME/${GITHUB_USERNAME}/g" {} +
git add . && git commit -m "Configure" && git push

# 3. Deploy
./docs/runbooks/01-bootstrap-mgmt.sh
./docs/runbooks/02-bootstrap-apps.sh
```

Access: `http://controller.local` (Argo CD)

## Features

- **GitOps**: Push to Git → auto-deploy
- **Multi-cluster**: Separate mgmt/apps isolation
- **Monitoring**: Per-cluster Prometheus + central Grafana
- **Scaling**: Add nodes with one command
- **Secrets**: GitOps-safe with Sealed Secrets
- **Recovery**: Rebuild from Git in 30min

## Tech Stack

- **k3s**: Lightweight Kubernetes
- **Argo CD**: GitOps
- **Prometheus/Grafana**: Monitoring
- **Sealed Secrets**: Encrypted secrets
- **Pi-hole**: DNS + ad-blocking

## Docs

- [START_HERE.md](START_HERE.md) - Get running fast
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Common commands
- [docs/](docs/) - Full guides and runbooks

## What You'll Learn

Real-world DevOps: GitOps, multi-cluster, observability, secret management, disaster recovery, platform engineering.
