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

## Default Credentials

Change these after first login:
- **ArgoCD:** admin / (shown after bootstrap)
- **Grafana:** admin / changeme

## Documentation

- [docs/quickstart.md](docs/quickstart.md) - Step-by-step setup
- [docs/sealed-secrets.md](docs/sealed-secrets.md) - Managing secrets

## Stack

k3s, ArgoCD, Prometheus/Grafana, cert-manager, external-dns, Sealed Secrets, Pi-hole
