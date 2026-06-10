# Homelab GitOps

Two-cluster Kubernetes homelab managed by Argo CD. The mgmt cluster (Pi 5) is a thin
controller: it runs Argo CD (which deploys to both clusters) and Pi-hole, plus the minimal
ingress/TLS/DNS stack needed to expose those two. Everything else runs on the apps
("platform") cluster.

## Architecture

```
Management cluster (controller.local - Pi 5)   Apps / platform cluster (server.local - PC)
├── Argo CD + Image Updater (controls both)    ├── Traefik / cert-manager / external-dns
├── Pi-hole (LAN DNS / ad-blocking)            ├── Longhorn (storage) / Velero (S3 backups)
└── Traefik / cert-manager / external-dns      ├── Prometheus / Grafana / Loki / Alloy
    + Sealed Secrets                           ├── Kyverno / Trivy / Headlamp
    (only to serve ArgoCD + Pi-hole)           ├── Argo Rollouts
                                               └── Workloads (paperless-ngx, leafing)
```

## Stack

| Area | Components |
|---|---|
| Cluster | k3s on both nodes (Traefik/servicelb disabled, replaced by chart-managed Traefik) |
| GitOps | Argo CD + ApplicationSets (git file generators over `app.yaml` files), Helm wrapper charts; Image Updater digest-tracks leafing and writes pins back to git |
| Storage | Longhorn (replicated block storage + snapshots; local-path stays the default StorageClass until flipped) |
| Ingress | Traefik v3 (+ separate traefik-crds app), per-app Ingress/IngressRoute templates |
| Load balancing | MetalLB (L2) — VIP pools per cluster: Traefik on `.210` (mgmt) / `.220` (apps), Pi-hole DNS on `.211`; reserve `.210-.229` outside the router's DHCP range |
| TLS | cert-manager — Let's Encrypt prod/staging via Cloudflare DNS-01, plus a self-signed `homelab-ca` ClusterIssuer |
| DNS | external-dns → Cloudflare (`iron-lab.org`, one instance per cluster with separate txtOwnerIds); Pi-hole for LAN DNS/ad-blocking |
| Secrets | Sealed Secrets (Cloudflare API tokens committed as SealedSecrets; helper scripts in `scripts/`) |
| Monitoring | kube-prometheus-stack (Prometheus, Grafana, Alertmanager, node-exporter), custom Grafana dashboards app |
| Logging | Grafana Alloy (pod log collection) → Loki |
| Backups | Velero + node agent (kopia file-system backups for local-path PVs) → S3, daily schedule |
| Security & policy | Kyverno (policies), Trivy Operator (vulnerability scanning) |
| Delivery | Argo Rollouts (apps cluster, progressive delivery) |
| Ops UI | Headlamp (`headlamp.iron-lab.org`, token login); Kubernetes Dashboard (retired upstream, kept until Headlamp is proven); Longhorn UI (port-forward only, no auth) |
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

1. Copy the golden template: `cp -r docs/new-app-skeleton argocd/applications/<mgmt|platform>/<app>`
2. Edit `charts/Chart.yaml` (upstream chart name/version/repo) and `config/values.yaml`
   (chart values + the `ingress:` block, or delete it and `charts/templates/ingress.yaml`
   if the app isn't exposed).
3. `app.yaml`: every field is optional — name/namespace/release default to the folder
   name, the chart path and destination are derived from where the folder lives, and
   `syncPolicy` merges over the fleet default in the ApplicationSet. Keep the fields you
   may want to tweak, delete the rest; `app: {}` is the minimum.
4. If the app needs a namespace the AppProject doesn't allow yet, add it to
   `argocd/bootstrap/projects.yaml`.
5. Commit and push — the ApplicationSets pick it up from git, and CI validates the chart
   render on the PR.

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
