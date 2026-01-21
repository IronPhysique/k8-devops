# ArgoCD Configuration

This directory contains all ArgoCD application definitions for the homelab platform.

## Directory Structure

```
argocd/
├── bootstrap/                      # Foundation resources
│   ├── projects.yaml              # AppProjects for mgmt, apps, and applications
│   └── root-app.yaml              # Root applications that bootstrap everything
├── applications/                   # Application definitions (each app in its own directory)
│   ├── mgmt/                      # Management cluster applications
│   │   ├── platform/              # Infrastructure/platform components
│   │   │   ├── kube-prometheus-stack/
│   │   │   │   ├── application.yaml         # ArgoCD Application definition
│   │   │   │   ├── values.yaml              # Helm values
│   │   │   │   └── grafana-datasource-apps.yaml
│   │   │   ├── cert-manager/
│   │   │   │   ├── application.yaml
│   │   │   │   ├── values.yaml
│   │   │   │   └── clusterissuer.yaml
│   │   │   ├── sealed-secrets/
│   │   │   │   ├── application.yaml
│   │   │   │   └── values.yaml
│   │   │   ├── alloy/
│   │   │   │   ├── application.yaml
│   │   │   │   └── values.yaml
│   │   │   └── nginx-router/
│   │   │       └── application.yaml
│   │   └── services/              # Service applications
│   │       └── pihole/
│   │           ├── application.yaml
│   │           ├── values.yaml
│   │           └── traefik.yaml
│   └── apps/                      # Apps cluster applications
│       └── platform/              # Infrastructure/platform components
│           ├── kube-prometheus-stack/
│           │   ├── application.yaml
│           │   ├── values.yaml
│           │   └── ingress.yaml
│           ├── cert-manager/
│           │   ├── application.yaml
│           │   ├── values.yaml
│           │   └── clusterissuer.yaml
│           ├── sealed-secrets/
│           │   ├── application.yaml
│           │   └── values.yaml
│           └── alloy/
│               ├── application.yaml
│               └── values.yaml
└── apps/                          # Raw manifests for non-Helm applications
    └── nginx-router/              # Nginx reverse proxy
        └── base/                  # Kustomize base
            ├── namespace.yaml
            ├── configmap.yaml
            ├── deployment.yaml
            └── kustomization.yaml
```

## Architecture

### App-of-Apps Pattern

This repository uses the **App-of-Apps pattern** for bootstrapping:

1. **Root Application** (`bootstrap/root-app.yaml`) - Entry point that deploys:
   - **mgmt-root** - Syncs all mgmt cluster applications from `applications/mgmt/`
   - **apps-root** - Syncs all apps cluster applications from `applications/apps/`

2. **AppProjects** (`bootstrap/projects.yaml`) - Defines:
   - `mgmt-platform` - For management cluster platform components
   - `apps-platform` - For apps cluster platform components
   - `applications` - For user application workloads

3. **Individual Applications** - Each app has its own directory containing ALL related files:
   - `application.yaml` - ArgoCD Application definition
   - `values.yaml` - Helm values (for Helm charts)
   - Additional configs (ClusterIssuers, ConfigMaps, IngressRoutes, etc.)
   - **Benefits**: No hunting across multiple directories, everything in one place

### Flow Diagram

```
kubectl apply -f bootstrap/root-app.yaml
            ↓
    ┌───────┴────────┐
    ↓                ↓
mgmt-root        apps-root
    ↓                ↓
applications/    applications/
mgmt/           apps/
├─ platform/    └─ platform/
└─ services/
```

## Application Categories

### Platform Applications

Infrastructure components required for cluster operations:

- **sealed-secrets**: Encrypted secrets management
- **cert-manager**: TLS certificate automation
- **kube-prometheus-stack**: Monitoring and alerting (Prometheus, Grafana, AlertManager)
- **alloy**: Log aggregation and forwarding
- **nginx-router**: Reverse proxy for HTTP routing (mgmt only)

### Service Applications

User-facing services:

- **pihole**: DNS and ad-blocking (mgmt only)

## Adding a New Application

### 1. Create App Directory and Files

Choose the appropriate directory based on:
- **Cluster**: `mgmt/` or `apps/`
- **Category**: `platform/` or `services/`

Example: Adding Grafana Loki (Helm chart) to mgmt cluster

```bash
# Create app directory
mkdir -p argocd/applications/mgmt/platform/loki

# Create Application definition
cat > argocd/applications/mgmt/platform/loki/application.yaml <<'EOF'
---
# Grafana Loki for mgmt cluster
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mgmt-loki
  namespace: argocd
  labels:
    cluster: mgmt
    component: platform
spec:
  project: mgmt-platform
  source:
    repoURL: https://grafana.github.io/helm-charts
    chart: loki
    targetRevision: 5.0.0
    helm:
      valueFiles:
        - '$values/argocd/applications/mgmt/platform/loki/values.yaml'
  sources:
    - repoURL: https://grafana.github.io/helm-charts
      chart: loki
      targetRevision: 5.0.0
    - repoURL: git@github.com:IronPhysique/k8-devops.git
      targetRevision: main
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 2m
EOF

# Create Helm values file
cat > argocd/applications/mgmt/platform/loki/values.yaml <<'EOF'
# Loki configuration
loki:
  auth_enabled: false
  storage:
    type: filesystem
EOF
```

### 2. Commit and Push

```bash
git add argocd/applications/mgmt/platform/loki/
git commit -m "Add Grafana Loki to mgmt cluster"
git push origin main
```

ArgoCD will automatically detect and deploy the new application.

**Note:** Everything for Loki is now in `argocd/applications/mgmt/platform/loki/` - no need to hunt across multiple directories!

### Adding a Non-Helm Application (Raw Manifests/Kustomize)

For applications that don't use Helm charts, store manifests in `argocd/apps/`:

**Example: Adding a custom web service**

1. **Create manifest directory:**
   ```bash
   mkdir -p argocd/apps/my-web-service/base
   ```

2. **Create Kubernetes manifests:**
   ```bash
   # Create your manifests
   cat > argocd/apps/my-web-service/base/deployment.yaml <<EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: my-web-service
   spec:
     replicas: 2
     selector:
       matchLabels:
         app: my-web-service
     template:
       metadata:
         labels:
           app: my-web-service
       spec:
         containers:
         - name: web
           image: nginx:alpine
           ports:
           - containerPort: 80
   EOF

   # Create kustomization.yaml
   cat > argocd/apps/my-web-service/base/kustomization.yaml <<EOF
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - namespace.yaml
     - deployment.yaml
     - service.yaml
   EOF
   ```

3. **Create app directory and Application definition:**
   ```bash
   mkdir -p argocd/applications/mgmt/services/my-web-service

   cat > argocd/applications/mgmt/services/my-web-service/application.yaml <<EOF
   ---
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: mgmt-my-web-service
     namespace: argocd
     labels:
       cluster: mgmt
       component: service
   spec:
     project: mgmt-platform
     source:
       repoURL: git@github.com:IronPhysique/k8-devops.git
       path: argocd/apps/my-web-service/base
       targetRevision: main
     destination:
       server: https://kubernetes.default.svc
       namespace: my-web-service
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   EOF
   ```

4. **Commit and push:**
   ```bash
   git add argocd/apps/my-web-service/
   git add argocd/applications/mgmt/services/my-web-service/
   git commit -m "Add my-web-service"
   git push origin main
   ```

## Updating Applications

### Upgrade Chart Version

Edit the application.yaml file:

```bash
vim argocd/applications/mgmt/platform/kube-prometheus-stack/application.yaml
```

Change `targetRevision`:
```yaml
targetRevision: 68.0.0  # Was 67.7.0
```

Commit and push:
```bash
git add argocd/applications/mgmt/platform/kube-prometheus-stack/application.yaml
git commit -m "Upgrade kube-prometheus-stack to 68.0.0"
git push origin main
```

### Update Configuration

Edit the values file (in the same directory as application.yaml):

```bash
vim argocd/applications/mgmt/platform/kube-prometheus-stack/values.yaml
```

Make changes, then commit:
```bash
git add argocd/applications/mgmt/platform/kube-prometheus-stack/values.yaml
git commit -m "Update Prometheus retention to 30 days"
git push origin main
```

## Common Tasks

### View All Applications

```bash
kubectl get applications -n argocd
```

### Check Application Status

```bash
kubectl get application mgmt-kube-prometheus-stack -n argocd -o yaml
```

### Force Sync Application

```bash
argocd app sync mgmt-kube-prometheus-stack
```

### Delete Application

Remove the app directory and commit:

```bash
git rm -r argocd/applications/mgmt/platform/loki/
git commit -m "Remove Loki from mgmt cluster"
git push origin main
```

ArgoCD will automatically prune the application and all its resources.

## Troubleshooting

### Application Won't Sync

1. Check application status:
   ```bash
   kubectl describe application <app-name> -n argocd
   ```

2. View sync errors in ArgoCD UI

3. Force refresh:
   ```bash
   argocd app sync <app-name> --prune
   ```

### Application Stuck in Progressing

1. Check pod status:
   ```bash
   kubectl get pods -n <namespace>
   ```

2. Check pod logs:
   ```bash
   kubectl logs <pod-name> -n <namespace>
   ```

3. Check events:
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

### Chart Version Not Found

Verify chart exists in repository:
```bash
helm search repo <repo-name>/<chart-name> --versions
```

Update repository:
```bash
helm repo update
```

## Best Practices

1. **One app per directory**: Each application gets its own directory with all related files
2. **Meaningful names**: Use format `<cluster>-<app-name>` for Application metadata (e.g., `mgmt-kube-prometheus-stack`)
3. **Consistent file names**: Always use `application.yaml` and `values.yaml`
4. **Labels**: Always include `cluster` and `component` labels
5. **Automated sync**: Enable `automated: {prune: true, selfHeal: true}` for GitOps
6. **Keep it together**: Put ALL app-related files in the app directory (values, configs, etc.)
7. **Test upgrades**: Use `argocd app diff` before syncing major changes

## Migration Notes

### From Centralized to Consolidated Structure

This repository was restructured to consolidate all app files in one place:

**Old structure:**
```
argocd/
├── applications/
│   └── mgmt/platform/
│       └── kube-prometheus-stack.yaml  # Just the Application definition
└── clusters/
    └── mgmt/
        ├── prometheus-values.yaml      # Values elsewhere
        └── grafana-datasource-apps.yaml # Configs elsewhere
```

**New structure:**
```
argocd/
└── applications/
    └── mgmt/platform/
        └── kube-prometheus-stack/      # Everything in ONE place
            ├── application.yaml
            ├── values.yaml
            └── grafana-datasource-apps.yaml
```

**Benefits:**
- **No hunting**: Everything for an app is in ONE directory
- **Easy updates**: Edit all files for an app in one location
- **Better organization**: Clear ownership and boundaries
- **Simpler paths**: `$values/argocd/applications/.../app/values.yaml` instead of `$values/argocd/clusters/.../app-values.yaml`

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
