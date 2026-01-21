# Example Applications

This directory contains example application deployments to help you get started.

## Available Examples

### 1. Simple App (Nginx)
Basic deployment with service and ingress.
```bash
kubectl apply -k examples/simple-app/
```

### 2. Database App (PostgreSQL + pgAdmin)
Stateful application with persistent storage.
```bash
kubectl apply -k examples/database-app/
```

### 3. Custom Grafana Dashboard
Example of adding custom dashboards to Grafana.
```bash
kubectl apply -f examples/monitoring-dashboard/
```

## GitOps Integration

To deploy via GitOps (recommended):

```bash
# Copy example to app-workloads
cp -r examples/simple-app clusters/apps/app-workloads/myapp

# Customize
vim clusters/apps/app-workloads/myapp/deployment.yaml

# Commit to Git
git add clusters/apps/app-workloads/myapp
git commit -m "Add myapp deployment"
git push

# Argo CD auto-syncs to apps cluster
```

## Best Practices

1. **Use namespace per application**
2. **Add labels for monitoring** (`app: myapp, cluster: apps`)
3. **Define resource limits**
4. **Use ServiceMonitor for metrics**
5. **Store secrets as SealedSecrets**
