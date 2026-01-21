# ArgoCD Configuration

This directory contains all ArgoCD application definitions for the homelab platform.

## Directory Structure

```
argocd/
├── bootstrap/                      # Foundation resources
│   ├── projects.yaml              # AppProjects for mgmt, apps, and applications
│   └── root-app.yaml              # Root applications that bootstrap everything
├── applications/                   # Application definitions organized by cluster
│   ├── mgmt/                      # Management cluster applications
│   │   ├── platform/              # Infrastructure/platform components
│   │   │   ├── sealed-secrets.yaml
│   │   │   ├── cert-manager.yaml
│   │   │   ├── kube-prometheus-stack.yaml
│   │   │   ├── alloy.yaml
│   │   │   └── nginx-router.yaml
│   │   └── services/              # Service applications
│   │       └── pihole.yaml
│   └── apps/                      # Apps cluster applications
│       └── platform/              # Infrastructure/platform components
│           ├── sealed-secrets.yaml
│           ├── cert-manager.yaml
│           ├── kube-prometheus-stack.yaml
│           └── alloy.yaml
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

3. **Individual Applications** - Each app has its own YAML file for:
   - Better readability
   - Easier maintenance
   - Clear separation of concerns

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

### 1. Create Application YAML

Choose the appropriate directory based on:
- **Cluster**: `mgmt/` or `apps/`
- **Category**: `platform/` or `services/`

Example: Adding Grafana Loki (Helm chart) to mgmt cluster

```bash
# Create Application file
touch argocd/applications/mgmt/platform/loki.yaml
```

```yaml
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
        - '$values/argocd/clusters/mgmt/loki-values.yaml'
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
```

### 2. Create Values File

Create corresponding Helm values file:

```bash
touch argocd/clusters/mgmt/loki-values.yaml
```

### 3. Commit and Push

```bash
git add argocd/applications/mgmt/platform/loki.yaml
git add argocd/clusters/mgmt/loki-values.yaml
git commit -m "Add Grafana Loki to mgmt cluster"
git push origin main
```

ArgoCD will automatically detect and deploy the new application.

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

3. **Create Application definition:**
   ```bash
   cat > argocd/applications/mgmt/services/my-web-service.yaml <<EOF
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
   git add argocd/applications/mgmt/services/my-web-service.yaml
   git commit -m "Add my-web-service"
   git push origin main
   ```

## Updating Applications

### Upgrade Chart Version

Edit the specific application file:

```bash
vim argocd/applications/mgmt/platform/kube-prometheus-stack.yaml
```

Change `targetRevision`:
```yaml
targetRevision: 68.0.0  # Was 67.7.0
```

Commit and push:
```bash
git add argocd/applications/mgmt/platform/kube-prometheus-stack.yaml
git commit -m "Upgrade kube-prometheus-stack to 68.0.0"
git push origin main
```

### Update Configuration

Edit the values file:

```bash
vim argocd/clusters/mgmt/prometheus-values.yaml
```

Make changes, then commit:
```bash
git add argocd/clusters/mgmt/prometheus-values.yaml
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

Remove the YAML file and commit:

```bash
git rm argocd/applications/mgmt/platform/loki.yaml
git commit -m "Remove Loki from mgmt cluster"
git push origin main
```

ArgoCD will automatically prune the application.

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

1. **One app per file**: Each application gets its own YAML file
2. **Meaningful names**: Use format `<cluster>-<app-name>` (e.g., `mgmt-prometheus`)
3. **Labels**: Always include `cluster` and `component` labels
4. **Automated sync**: Enable `automated: {prune: true, selfHeal: true}` for GitOps
5. **Values in argocd/clusters/**: Keep Helm values in `argocd/clusters/` directory, not inline
6. **Test upgrades**: Use `argocd app diff` before syncing major changes

## Migration Notes

### From ApplicationSets to Individual Applications

This repository was restructured from ApplicationSets to individual Application files for:
- **Better readability**: Each app is self-contained
- **Easier maintenance**: Update one file vs. editing list entries
- **Clearer structure**: Platform vs. services separation
- **Better git history**: Changes to one app don't touch others

Old structure:
```
argocd/
├── applicationsets/
│   ├── mgmt-platform.yaml  # All mgmt platform apps in one file
│   └── apps-platform.yaml  # All apps platform apps in one file
```

New structure:
```
argocd/
└── applications/
    ├── mgmt/platform/      # Individual files per app
    └── apps/platform/      # Individual files per app
```

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ApplicationSet Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/)
- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
