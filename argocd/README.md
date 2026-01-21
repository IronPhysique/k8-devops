# ArgoCD Configuration

All ArgoCD application definitions for the homelab platform.

## Directory Structure

```
argocd/
├── bootstrap/                # Foundation resources
│   ├── projects.yaml        # AppProjects (mgmt-platform, apps-platform, applications)
│   └── root-app.yaml        # Root applications (mgmt-root, apps-root)
└── applications/             # Application definitions
    ├── mgmt/                # Management cluster apps
    │   ├── platform/        # Infrastructure (prometheus, cert-manager, etc.)
    │   └── services/        # Services (pihole)
    └── apps/                # Apps cluster apps
        └── platform/        # Infrastructure
```

**Each app directory contains ALL related files:**
- `application.yaml` - ArgoCD Application definition
- `values.yaml` - Helm values (for Helm charts)
- `manifests/base/` - Kubernetes manifests (for non-Helm apps)
- Additional configs (ClusterIssuers, ConfigMaps, etc.)

## Bootstrap Flow

```
kubectl apply -f bootstrap/root-app.yaml
            ↓
    Syncs argocd/bootstrap/
            ↓
    ┌───────┴────────┐
    ↓                ↓
projects.yaml    root-app.yaml
                     ↓
    ┌────────────────┴────────────────┐
    ↓                                 ↓
mgmt-root                         apps-root
(syncs applications/mgmt/)        (syncs applications/apps/)
    ↓                                 ↓
Deploys all mgmt apps             Deploys all apps apps
```

## Adding a New Helm Application

Example: Adding Grafana Loki to mgmt cluster

```bash
# 1. Create app directory
mkdir -p argocd/applications/mgmt/platform/loki

# 2. Create Application definition
cat > argocd/applications/mgmt/platform/loki/application.yaml <<'EOF'
---
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
EOF

# 3. Create values file
cat > argocd/applications/mgmt/platform/loki/values.yaml <<'EOF'
loki:
  auth_enabled: false
  storage:
    type: filesystem
EOF

# 4. Commit and push
git add argocd/applications/mgmt/platform/loki/
git commit -m "Add Grafana Loki"
git push
```

ArgoCD auto-detects and deploys the new application.

## Adding a Non-Helm Application

Example: nginx-router with raw manifests

```bash
# 1. Create app directory with manifests
mkdir -p argocd/applications/mgmt/platform/nginx-router/manifests/base

# 2. Create Kubernetes manifests
cat > argocd/applications/mgmt/platform/nginx-router/manifests/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-router
  namespace: nginx-router
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-router
  template:
    metadata:
      labels:
        app: nginx-router
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
EOF

# Create kustomization.yaml
cat > argocd/applications/mgmt/platform/nginx-router/manifests/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
EOF

# 3. Create Application definition
cat > argocd/applications/mgmt/platform/nginx-router/application.yaml <<'EOF'
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mgmt-nginx-router
  namespace: argocd
spec:
  project: mgmt-platform
  source:
    repoURL: git@github.com:IronPhysique/k8-devops.git
    path: argocd/applications/mgmt/platform/nginx-router/manifests/base
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: nginx-router
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# 4. Commit and push
git add argocd/applications/mgmt/platform/nginx-router/
git commit -m "Add nginx-router"
git push
```

## Common Tasks

### Upgrade Chart Version

```bash
# Edit application.yaml
vim argocd/applications/mgmt/platform/kube-prometheus-stack/application.yaml

# Change targetRevision
targetRevision: 68.0.0  # Was 67.7.0

# Commit
git add argocd/applications/mgmt/platform/kube-prometheus-stack/application.yaml
git commit -m "Upgrade kube-prometheus-stack to 68.0.0"
git push
```

### Update Configuration

```bash
# Edit values file
vim argocd/applications/mgmt/platform/kube-prometheus-stack/values.yaml

# Make changes, commit
git add argocd/applications/mgmt/platform/kube-prometheus-stack/values.yaml
git commit -m "Update Prometheus retention"
git push
```

### Delete Application

```bash
# Remove app directory
git rm -r argocd/applications/mgmt/platform/loki/
git commit -m "Remove Loki"
git push
```

ArgoCD auto-prunes the application and resources.

## Troubleshooting

### Application Won't Sync

```bash
# Check status
kubectl describe application <app-name> -n argocd

# Force refresh
argocd app sync <app-name> --prune
```

### Application Stuck in Progressing

```bash
# Check pods
kubectl get pods -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Best Practices

1. **One app per directory** - Everything related in one place
2. **Naming:** `<cluster>-<app-name>` for metadata (e.g., `mgmt-kube-prometheus-stack`)
3. **Files:** Always use `application.yaml` and `values.yaml`
4. **Labels:** Include `cluster` and `component` labels
5. **Automated sync:** Enable `automated: {prune: true, selfHeal: true}`
6. **Keep together:** All app files (values, configs) in app directory

## References

For complete details, see:
- [STRUCTURE.md](../STRUCTURE.md) - Full repository structure guide
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
