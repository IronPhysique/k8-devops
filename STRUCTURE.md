# Repository Structure

Complete guide to the homelab repository organization.

## Overview

This repository uses a **GitOps approach** where all Kubernetes resources are defined in Git and automatically deployed via ArgoCD.

## Top-Level Directories

```
homelab/
├── argocd/                 # All ArgoCD and Kubernetes resources
│   ├── applications/      # Application definitions
│   ├── apps/              # Non-Helm app manifests
│   ├── bootstrap/         # Foundation resources
│   ├── argocd/clusters/          # Cluster-specific configs (Helm values)
│   ├── platform/          # (Future) Shared platform templates
│   └── secrets/           # (Future) Sealed secrets
├── bootstrap/              # Initial cluster setup scripts
├── docs/                  # Documentation and runbooks
└── examples/              # Example applications
```

## Detailed Structure

### argocd/

**Purpose:** All ArgoCD-related files including Application definitions and raw Kubernetes manifests.

```
argocd/
├── bootstrap/             # Foundation resources
│   ├── projects.yaml     # AppProjects (mgmt-platform, apps-platform, applications)
│   └── root-app.yaml     # Root applications that bootstrap everything
│
├── applications/          # Application definitions (what to deploy)
│   ├── mgmt/             # Management cluster apps
│   │   ├── platform/     # Infrastructure (sealed-secrets, cert-manager, etc.)
│   │   └── services/     # Services (pihole, etc.)
│   └── apps/             # Apps cluster apps
│       └── platform/     # Infrastructure
│
└── apps/                  # Raw manifests (Kustomize/plain YAML)
    └── nginx-router/      # Non-Helm apps go here
        └── base/
```

**Key Concepts:**

- **applications/**: Contains ArgoCD `Application` resources (CRDs that tell ArgoCD WHAT to deploy)
- **apps/**: Contains the actual Kubernetes manifests for non-Helm applications

**Helm vs Non-Helm:**
- **Helm charts**: Only need an Application definition in `applications/` + values in `argocd/clusters/`
- **Non-Helm apps**: Need Application definition in `applications/` + manifests in `apps/`

### bootstrap/

**Purpose:** Initial cluster setup and ArgoCD installation.

```
bootstrap/
├── argocd-install.yaml   # ArgoCD ConfigMaps for configuration
└── root-app.yaml         # Root Application that syncs argocd/bootstrap/
```

**Usage:**
```bash
# Bootstrap management cluster
./bootstrap/01-bootstrap-mgmt.sh
```

### argocd/clusters/

**Purpose:** Cluster-specific configurations, primarily Helm values files.

```
argocd/clusters/
├── mgmt/                      # Management cluster config
│   ├── prometheus-values.yaml
│   ├── pihole-values.yaml
│   ├── cert-manager-values.yaml
│   ├── cert-manager-clusterissuer.yaml
│   └── *-sealed.yaml          # Encrypted secrets
│
└── apps/                      # Apps cluster config
    ├── prometheus-values.yaml
    ├── cert-manager-values.yaml
    └── app-workloads/         # User application configs
```

**Important:**
- Helm values referenced by Applications in `argocd/applications/`
- Each Application uses `$values/argocd/clusters/mgmt/<app>-values.yaml` pattern

### docs/

**Purpose:** Documentation and operational runbooks.

```
docs/
├── runbooks/
│   ├── 01-bootstrap-mgmt.sh
│   ├── 02-bootstrap-apps.sh
│   ├── validate-cluster.sh
│   ├── upgrade-strategy.md
│   ├── rebuild-mgmt.md
│   └── ...
├── TABLE_OF_CONTENTS.md
├── IMPLEMENTATION_SUMMARY.md
└── ...
```

## GitOps Flow

### 1. Bootstrap Flow

```
kubectl apply -f bootstrap/root-app.yaml
            ↓
    Syncs argocd/bootstrap/
            ↓
    ┌───────┴────────┐
    ↓                ↓
projects.yaml    root-app.yaml (creates mgmt-root & apps-root)
                     ↓
    ┌────────────────┴────────────────┐
    ↓                                 ↓
mgmt-root                         apps-root
(syncs argocd/applications/mgmt/) (syncs argocd/applications/apps/)
    ↓                                 ↓
Deploys all mgmt apps             Deploys all apps apps
```

### 2. Application Deployment Flow

#### For Helm Charts (e.g., kube-prometheus-stack):

```
argocd/applications/mgmt/platform/kube-prometheus-stack.yaml
    ↓ (references)
argocd/clusters/mgmt/prometheus-values.yaml
    ↓ (ArgoCD fetches chart and applies values)
Deployed resources in monitoring namespace
```

#### For Non-Helm Apps (e.g., nginx-router):

```
argocd/applications/mgmt/platform/nginx-router.yaml
    ↓ (points to)
argocd/apps/nginx-router/base/
    ↓ (ArgoCD applies manifests)
Deployed resources in nginx-router namespace
```

## File Organization Principles

### 1. Application Definitions

**Location:** `argocd/applications/<cluster>/<category>/<app-name>.yaml`

**Naming Convention:**
- Application name: `<cluster>-<app-name>` (e.g., `mgmt-prometheus`)
- File name: `<app-name>.yaml` (e.g., `prometheus.yaml`)

**Categories:**
- `platform/`: Infrastructure components (sealed-secrets, cert-manager, prometheus, etc.)
- `services/`: User-facing services (pihole, etc.)

### 2. Application Manifests (Non-Helm)

**Location:** `argocd/apps/<app-name>/base/`

**Structure:**
```
argocd/apps/my-app/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── configmap.yaml
└── overlays/              # (Optional) for environment-specific overrides
    ├── dev/
    └── prod/
```

### 3. Cluster Configurations

**Location:** `argocd/clusters/<cluster-name>/<app>-values.yaml`

**Naming Convention:**
- Format: `<app>-values.yaml`
- Examples: `prometheus-values.yaml`, `pihole-values.yaml`

## Common Patterns

### Adding a Helm Chart Application

1. Create Application definition:
   ```bash
   vim argocd/applications/mgmt/platform/grafana.yaml
   ```

2. Create Helm values:
   ```bash
   vim argocd/clusters/mgmt/grafana-values.yaml
   ```

3. Commit and push:
   ```bash
   git add argocd/applications/mgmt/platform/grafana.yaml
   git add argocd/clusters/mgmt/grafana-values.yaml
   git commit -m "Add Grafana"
   git push
   ```

### Adding a Non-Helm Application

1. Create manifests:
   ```bash
   mkdir -p argocd/apps/my-app/base
   vim argocd/apps/my-app/base/deployment.yaml
   vim argocd/apps/my-app/base/service.yaml
   vim argocd/apps/my-app/base/kustomization.yaml
   ```

2. Create Application definition:
   ```bash
   vim argocd/applications/mgmt/services/my-app.yaml
   ```

3. Commit and push:
   ```bash
   git add argocd/apps/my-app/
   git add argocd/applications/mgmt/services/my-app.yaml
   git commit -m "Add my-app"
   git push
   ```

## Directory Purposes Summary

| Directory | Purpose | Contains |
|-----------|---------|----------|
| `argocd/bootstrap/` | Bootstrap resources | AppProjects, root Applications |
| `argocd/applications/` | Application definitions | ArgoCD Application CRDs |
| `argocd/apps/` | Non-Helm manifests | Kustomize/plain YAML |
| `bootstrap/` | Cluster setup | Installation scripts, ArgoCD config |
| `argocd/clusters/` | Cluster configs | Helm values, cluster-specific settings |
| `docs/` | Documentation | Runbooks, guides, references |
| `examples/` | Sample apps | Example deployments for learning |

## Best Practices

1. **Keep it organized:**
   - All ArgoCD-related files under `argocd/`
   - Cluster-specific configs under `argocd/clusters/`
   - One application per file

2. **Naming consistency:**
   - Application names: `<cluster>-<app-name>`
   - File names: `<app-name>.yaml`
   - Consistent with directory structure

3. **Separate concerns:**
   - Platform components in `platform/`
   - User services in `services/`
   - Helm values in `argocd/clusters/`
   - Raw manifests in `argocd/apps/`

4. **Documentation:**
   - Update CHANGELOG.md for significant changes
   - Keep runbooks current
   - Comment complex configurations

## Quick Reference

```bash
# Where do I put...?

# 1. A new Helm chart application?
argocd/applications/<cluster>/<platform|services>/<app>.yaml  # Application definition
argocd/clusters/<cluster>/<app>-values.yaml                          # Helm values

# 2. A non-Helm application?
argocd/applications/<cluster>/<platform|services>/<app>.yaml  # Application definition
argocd/apps/<app>/base/                                       # Kubernetes manifests

# 3. Cluster-specific secrets?
argocd/clusters/<cluster>/<app>-sealed.yaml                          # Encrypted secrets

# 4. Shared platform configuration?
argocd/clusters/<cluster>/<component>-values.yaml                    # Helm values
```

## See Also

- [argocd/README.md](argocd/README.md) - Detailed ArgoCD usage guide
- [docs/TABLE_OF_CONTENTS.md](docs/TABLE_OF_CONTENTS.md) - Complete documentation index
- [CHANGELOG.md](CHANGELOG.md) - Recent changes and migrations
