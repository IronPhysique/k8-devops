# Homelab GitOps

Two-cluster Kubernetes homelab managed by Argo CD (running on the mgmt cluster, deploying to both).

## Architecture

```
Management cluster (controller.local - Pi 5)   Apps cluster (server.local - PC)
├── Argo CD (manages both clusters)            ├── Traefik / cert-manager / external-dns
├── Traefik / cert-manager / external-dns      ├── Argo Rollouts
├── Prometheus / Grafana / Loki / Alloy        └── Workloads (paperless-ngx, ...)
├── Pi-hole / Sealed Secrets
└── Kyverno / Trivy / Dashboards
```

## Repository layout

```
argocd/
├── bootstrap/
│   └── projects.yaml          # Argo CD AppProjects
├── applicationsets/
│   ├── mgmt-apps.yaml         # generates Applications from applications/mgmt/*/app.yaml
│   ├── platform-apps.yaml     # generates Applications from applications/platform/*/app.yaml
│   ├── mgmt-ingress.yaml      # generates Ingress apps for mgmt apps with ingress.hostname set
│   ├── platform-ingress.yaml  # generates Ingress apps for apps-cluster apps with ingress.hostname set
│   └── templates/ingress/     # shared Helm chart used by the ingress ApplicationSets
└── applications/
    ├── mgmt/                  # everything deployed to the mgmt cluster
    │   └── <app>/
    │       ├── app.yaml       # Application config consumed by the ApplicationSets
    │       ├── charts/        # Helm chart (wrapper around upstream chart)
    │       └── config/values.yaml
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
3. Optionally set `ingress.hostname` to get an Ingress + DNS record generated automatically.
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

## Stack

k3s, Argo CD, Traefik, Prometheus/Grafana/Loki, cert-manager, external-dns, Sealed Secrets, Pi-hole, Kyverno, Trivy, Argo Rollouts
