# Homelab GitOps

Two-cluster Kubernetes homelab managed by Argo CD (running on the mgmt cluster, deploying to both).

## Architecture

```
Management cluster (controller.local - Pi 5)   Apps cluster (server.local - PC)
├── Argo CD (manages both clusters)            ├── Traefik / cert-manager / external-dns
├── Traefik / cert-manager / external-dns      ├── Argo Rollouts
├── Prometheus / Grafana / Loki / Alloy        └── Workloads (paperless-ngx, leafing)
├── Pi-hole / Sealed Secrets
└── Kyverno / Trivy / Dashboards
```

## Stack

| Area | Components |
|---|---|
| Cluster | k3s on both nodes (Traefik/servicelb disabled, replaced by chart-managed Traefik) |
| GitOps | Argo CD + ApplicationSets (git file generators over `app.yaml` files), Helm wrapper charts |
| Ingress | Traefik v3 (+ separate traefik-crds app), per-app Ingress/IngressRoute templates |
| TLS | cert-manager — Let's Encrypt prod/staging via Cloudflare DNS-01, plus a self-signed `homelab-ca` ClusterIssuer |
| DNS | external-dns → Cloudflare (`iron-lab.org`, one instance per cluster with separate txtOwnerIds); Pi-hole for LAN DNS/ad-blocking |
| Secrets | Sealed Secrets (Cloudflare API tokens committed as SealedSecrets; helper scripts in `scripts/`) |
| Monitoring | kube-prometheus-stack (Prometheus, Grafana, Alertmanager, node-exporter), custom Grafana dashboards app |
| Logging | Grafana Alloy (pod log collection) → Loki |
| Security & policy | Kyverno (policies), Trivy Operator (vulnerability scanning) |
| Delivery | Argo Rollouts (apps cluster, progressive delivery) |
| Ops UI | Kubernetes Dashboard (kong proxy, exposed via Traefik IngressRoute) |
| Workloads | paperless-ngx (raw manifests; backed by its own Redis 7 and PostgreSQL 16 instances); leafing (Next.js web + BullMQ worker from one GHCR image, PostgreSQL 18, Redis 8, FlareSolverr) |
| CI | GitHub Actions — kubeconform + helm-template validation of this repo on every push/PR |

## Repository layout

```
argocd/
├── bootstrap/
│   └── projects.yaml          # Argo CD AppProjects
├── applicationsets/
│   ├── mgmt-apps.yaml         # generates Applications from applications/mgmt/*/app.yaml
│   └── platform-apps.yaml     # generates Applications from applications/platform/*/app.yaml
└── applications/
    ├── mgmt/                  # everything deployed to the mgmt cluster
    │   └── <app>/
    │       ├── app.yaml       # Application config consumed by the ApplicationSets
    │       ├── charts/        # Helm chart (wrapper around upstream chart)
    │       │   └── templates/ingress.yaml   # only for apps exposed via Traefik
    │       └── config/values.yaml           # upstream chart values + ingress block
    └── platform/              # everything deployed to the apps cluster
        └── <app>/             # same structure; plain-manifest apps use manifests/ instead of charts/

scripts/
├── bootstrap/                 # 01: mgmt cluster + Argo CD, 02: apps cluster + registration
├── create-sealed-secret.sh
└── fix-cert-manager-sealed-secret.sh
```

### Adding an app

1. Create `argocd/applications/<mgmt|platform>/<app>/` with an `app.yaml`, a `charts/` Helm chart
   (or `manifests/` for raw YAML), and `config/values.yaml`.
2. Set `app.name`, `app.namespace`, `app.project`, `app.source.path`, and `app.destination.server`
   in `app.yaml` (copy a neighbouring app as a template).
3. To expose the app: copy `charts/templates/ingress.yaml` from an existing app (e.g. pihole)
   and add an `ingress:` block to `config/values.yaml` (hostname, serviceName, port, targetIP).
   Manifest-based apps include a plain `manifests/ingress.yaml` instead.
4. Commit and push — the ApplicationSets pick it up from git.

## Bootstrap

```bash
cp config.env.example config.env   # edit with your IPs
./scripts/bootstrap/01-bootstrap-mgmt.sh
./scripts/bootstrap/02-bootstrap-apps.sh
```

## Default credentials

Change these after first login:
- **ArgoCD:** admin / (shown after bootstrap)
- **Grafana:** admin / changeme
