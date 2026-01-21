# Repository Structure

Complete guide to the homelab repository organization.

## Overview

This repository uses a **GitOps approach** where all Kubernetes resources are defined in Git and automatically deployed via ArgoCD.

## Top-Level Directories

```
homelab/
├── argocd/                 # All ArgoCD and Kubernetes resources
│   ├── applications/      # Application definitions (each app in its own directory)
│   ├── apps/              # Non-Helm app manifests (nginx-router, etc.)
│   └── bootstrap/         # Foundation resources (projects, root apps)
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
├── applications/          # Application definitions (each app in its own directory)
│   ├── mgmt/             # Management cluster apps
│   │   ├── platform/     # Infrastructure components
│   │   │   ├── kube-prometheus-stack/
│   │   │   │   ├── application.yaml         # ArgoCD Application definition
│   │   │   │   ├── values.yaml              # Helm values
│   │   │   │   └── grafana-datasource-apps.yaml  # Additional configs
│   │   │   ├── cert-manager/
│   │   │   │   ├── application.yaml
│   │   │   │   ├── values.yaml
│   │   │   │   └── clusterissuer.yaml
│   │   │   ├── sealed-secrets/
│   │   │   ├── alloy/
│   │   │   └── nginx-router/
│   │   └── services/     # Services
│   │       └── pihole/
│   │           ├── application.yaml
│   │           ├── values.yaml
│   │           └── traefik.yaml
│   └── apps/             # Apps cluster apps
│       └── platform/     # Infrastructure
│           ├── kube-prometheus-stack/
│           ├── cert-manager/
│           ├── sealed-secrets/
│           └── alloy/
│
└── apps/                  # Raw manifests for non-Helm applications
    └── nginx-router/      # Kustomize/plain YAML apps
        └── base/
            ├── namespace.yaml
            ├── configmap.yaml
            ├── deployment.yaml
            └── kustomization.yaml
```

**Key Concepts:**

- **applications/**: Each app has its OWN directory containing ALL related files:
  - `application.yaml` - ArgoCD Application definition (what to deploy)
  - `values.yaml` - Helm values (for Helm charts)
  - Any additional configs (ClusterIssuers, ConfigMaps, IngressRoutes, etc.)

- **apps/**: Actual Kubernetes manifests for non-Helm applications (nginx-router uses this)

**Important Notes:**

1. **For Helm apps:** Everything lives in `applications/<cluster>/<category>/<app>/`
   - Example: `applications/mgmt/platform/kube-prometheus-stack/` has application.yaml AND values.yaml

2. **For non-Helm apps:** Split between two locations:
   - Application definition: `applications/<cluster>/<category>/<app>/application.yaml`
   - Actual manifests: `apps/<app>/base/*.yaml`
   - Example: nginx-router has Application def in `applications/mgmt/platform/nginx-router/` but manifests in `apps/nginx-router/base/`
   - Why? The manifests aren't ArgoCD resources, they're the actual Kubernetes YAML files

**Benefits of This Structure:**
- **No hunting for Helm apps**: Everything for an app is in ONE place
- **Clear separation for non-Helm apps**: Application definition vs actual manifests
- **Easy to find**: Want to see Pi-hole config? Look in `applications/mgmt/services/pihole/`
- **Clear ownership**: Each directory is self-contained
- **Better git history**: Changes to one app don't touch other apps

### bootstrap/ (Top-Level)

**Purpose:** ONE-TIME initial cluster setup scripts and ArgoCD installation.

```
bootstrap/
├── 01-bootstrap-mgmt.sh  # Script to set up management cluster
├── 02-bootstrap-apps.sh  # Script to set up apps cluster
├── argocd-install.yaml   # ArgoCD ConfigMaps for configuration
└── root-app.yaml         # Entry point Application (points to argocd/bootstrap/)
```

**Usage:**
```bash
# Bootstrap management cluster (run ONCE)
./bootstrap/01-bootstrap-mgmt.sh

# This installs k3s, ArgoCD, and applies root-app.yaml
# The root-app.yaml then syncs argocd/bootstrap/ directory
```

**Important:** This is different from `argocd/bootstrap/` which contains the ArgoCD-managed resources!

### docs/

**Purpose:** Documentation and operational runbooks.

```
docs/
├── runbooks/
│   ├── 03-configure-cross-cluster-monitoring.md
│   ├── validate-cluster.sh
│   ├── upgrade-strategy.md
│   ├── rebuild-mgmt.md
│   ├── rebuild-apps.md
│   ├── add-node.md
│   └── rotate-sealed-secrets.md
├── TABLE_OF_CONTENTS.md
├── IMPLEMENTATION_SUMMARY.md
├── secrets-management.md
└── ...
```

**Note:** Bootstrap scripts (`01-bootstrap-mgmt.sh`, `02-bootstrap-apps.sh`) are now in `bootstrap/` directory.

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
argocd/applications/mgmt/platform/kube-prometheus-stack/
├── application.yaml         # Points to Helm chart
└── values.yaml             # Helm values ($values reference in application.yaml)
    ↓ (ArgoCD fetches chart and applies values)
Deployed resources in monitoring namespace
```

#### For Non-Helm Apps (e.g., nginx-router):

```
argocd/applications/mgmt/platform/nginx-router/
└── application.yaml        # Points to argocd/apps/nginx-router/base/
    ↓
argocd/apps/nginx-router/base/
├── namespace.yaml
├── deployment.yaml
├── service.yaml
└── kustomization.yaml
    ↓ (ArgoCD applies manifests)
Deployed resources in nginx-router namespace
```

## File Organization Principles

### 1. Application Definitions

**Location:** `argocd/applications/<cluster>/<category>/<app-name>/`

**Structure:** Each app gets its own directory containing ALL related files:
```
argocd/applications/<cluster>/<category>/<app-name>/
├── application.yaml      # ArgoCD Application definition
├── values.yaml          # Helm values (if Helm chart)
└── <other-configs>.yaml # Any additional configs (ClusterIssuers, ConfigMaps, etc.)
```

**Naming Convention:**
- Application name (in YAML): `<cluster>-<app-name>` (e.g., `mgmt-kube-prometheus-stack`)
- Directory name: `<app-name>` (e.g., `kube-prometheus-stack/`)
- Main file: Always named `application.yaml`

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

### 3. Helm Values and Configurations

**Location:** `argocd/applications/<cluster>/<category>/<app-name>/values.yaml`

**Naming Convention:**
- Always named `values.yaml`
- Lives in the same directory as `application.yaml`
- Additional configs (ClusterIssuers, ConfigMaps, etc.) also live here

**Example:**
```
argocd/applications/mgmt/platform/kube-prometheus-stack/
├── application.yaml              # ArgoCD Application
├── values.yaml                   # Helm values
└── grafana-datasource-apps.yaml  # Additional config for Grafana
```

## Common Patterns

### Adding a Helm Chart Application

1. Create app directory:
   ```bash
   mkdir -p argocd/applications/mgmt/platform/grafana
   ```

2. Create Application definition:
   ```bash
   vim argocd/applications/mgmt/platform/grafana/application.yaml
   ```

3. Create Helm values:
   ```bash
   vim argocd/applications/mgmt/platform/grafana/values.yaml
   ```

4. Commit and push:
   ```bash
   git add argocd/applications/mgmt/platform/grafana/
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

2. Create app directory and Application definition:
   ```bash
   mkdir -p argocd/applications/mgmt/services/my-app
   vim argocd/applications/mgmt/services/my-app/application.yaml
   ```

3. Commit and push:
   ```bash
   git add argocd/apps/my-app/
   git add argocd/applications/mgmt/services/my-app/
   git commit -m "Add my-app"
   git push
   ```

## Directory Purposes Summary

| Directory | Purpose | Contains |
|-----------|---------|----------|
| `argocd/bootstrap/` | Bootstrap resources | AppProjects, root Applications |
| `argocd/applications/` | App directories | Each app in its own dir with application.yaml, values.yaml, configs |
| `argocd/apps/` | Non-Helm manifests | Kustomize/plain YAML for apps like nginx-router |
| `bootstrap/` | Cluster setup | Installation scripts, root-app.yaml, ArgoCD install config |
| `docs/` | Documentation | Runbooks, guides, references |
| `examples/` | Sample apps | Example deployments for learning |

## Best Practices

1. **Keep it organized:**
   - All ArgoCD-related files under `argocd/`
   - Each app in its own directory
   - All app-related files together (no hunting!)

2. **Naming consistency:**
   - Application names (in YAML): `<cluster>-<app-name>`
   - Directory names: `<app-name>/`
   - Main file: Always `application.yaml`
   - Values file: Always `values.yaml`

3. **Separate concerns:**
   - Platform components in `platform/`
   - User services in `services/`
   - Helm apps: Everything in app directory
   - Non-Helm apps: Manifests in `argocd/apps/`, Application def in `argocd/applications/`

4. **Documentation:**
   - Update CHANGELOG.md for significant changes
   - Keep runbooks current
   - Comment complex configurations

## Quick Reference

```bash
# Where do I put...?

# 1. A new Helm chart application?
argocd/applications/<cluster>/<platform|services>/<app>/
├── application.yaml    # Application definition
└── values.yaml        # Helm values

# 2. A non-Helm application?
argocd/applications/<cluster>/<platform|services>/<app>/
└── application.yaml    # Application definition (points to argocd/apps/<app>/)
argocd/apps/<app>/base/
└── *.yaml             # Kubernetes manifests

# 3. Additional app configs (ClusterIssuer, ConfigMaps, IngressRoutes)?
argocd/applications/<cluster>/<platform|services>/<app>/
├── application.yaml
├── values.yaml
└── <config-name>.yaml  # Put it right here with the app!

# 4. Where is app X configured?
# Just look in: argocd/applications/<cluster>/<platform|services>/<app>/
# Everything for that app is in that ONE directory!
```

## See Also

- [argocd/README.md](argocd/README.md) - Detailed ArgoCD usage guide
- [docs/TABLE_OF_CONTENTS.md](docs/TABLE_OF_CONTENTS.md) - Complete documentation index
- [CHANGELOG.md](CHANGELOG.md) - Recent changes and migrations
