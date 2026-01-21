# Quick Start Guide

Get your homelab up and running in under 1 hour.

## Prerequisites Checklist

- [ ] Raspberry Pi 5 with Ubuntu 22.04/24.04 installed
- [ ] Office PC with Ubuntu 22.04/24.04 installed
- [ ] Static IPs assigned (192.168.1.10 for Pi, 192.168.1.20 for PC)
- [ ] SSH access to both machines
- [ ] Git configured on your workstation
- [ ] Fork/clone this repository

---

## Step 1: Update Configuration (5 minutes)

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# Update your GitHub username in all files
find . -type f -name "*.yaml" -exec sed -i 's/YOUR_USERNAME/your-github-username/g' {} +

# Update IP addresses in these files:
# - clusters/mgmt/pihole-traefik.yaml (line 18)
# - clusters/mgmt/grafana-datasource-apps.yaml (line 16)
# - docs/runbooks/*.sh (MGMT_IP, APPS_IP variables)

# Commit changes
git add .
git commit -m "Configure homelab for my environment"
git push origin main
```

---

## Step 2: Bootstrap Management Cluster (15 minutes)

```bash
# Run bootstrap script
cd docs/runbooks
./01-bootstrap-mgmt.sh

# Wait for script to complete
# Save the Argo CD password shown at the end
```

**What this does:**
- Installs k3s on Raspberry Pi
- Installs Argo CD
- Deploys all platform components via GitOps
- Exposes Argo CD UI

**Validation:**
```bash
# Check all applications synced
kubectl get applications -n argocd

# All should show: Synced, Healthy
```

---

## Step 3: Bootstrap Apps Cluster (15 minutes)

```bash
# Run apps cluster bootstrap
./02-bootstrap-apps.sh

# Wait for script to complete
```

**What this does:**
- Installs k3s on Office PC
- Registers apps cluster with Argo CD
- Deploys all apps platform components via GitOps

**Validation:**
```bash
# Check both clusters
kubectl get nodes --context=default         # mgmt cluster
kubectl get nodes --context=apps-cluster    # apps cluster

# Check apps applications synced
kubectl get applications -n argocd | grep apps-
```

---

## Step 4: Configure Cross-Cluster Monitoring (10 minutes)

```bash
# Get apps cluster Traefik IP
kubectl --context=apps-cluster get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Update Grafana datasource
kubectl --context=default apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-apps
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  apps-prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus-apps
        type: prometheus
        access: proxy
        url: http://192.168.1.20:9090  # UPDATE with your apps IP
        isDefault: false
        editable: true
        jsonData:
          timeInterval: 30s
          httpMethod: POST
EOF

# Restart Grafana
kubectl --context=default rollout restart deployment kube-prometheus-stack-grafana -n monitoring
```

**Validation:**
```bash
# Port-forward Grafana
kubectl --context=default port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / (password from Step 2)
# Check Configuration → Data Sources
# Should see: Prometheus-mgmt (default), Prometheus-apps
```

---

## Step 5: Access Services (5 minutes)

### Argo CD

```bash
# Get mgmt cluster IP
MGMT_IP=192.168.1.10

# Open browser
echo "Argo CD: http://$MGMT_IP"

# Login: admin / <password from Step 2>
```

### Grafana

```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open browser: http://localhost:3000
# Login: admin / admin (change in clusters/mgmt/prometheus-values.yaml)
```

### Pi-hole

```bash
# Get Pi-hole LoadBalancer IP
kubectl get svc -n pihole pihole-dns-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Open browser: http://<PIHOLE_IP>/admin
# Login password: From clusters/mgmt/pihole-values.yaml (change this!)
```

---

## Step 6: Deploy Your First App (5 minutes)

```bash
# Create application namespace
kubectl create namespace demo --context=apps-cluster

# Deploy nginx example
kubectl apply -f - << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
  namespace: demo
spec:
  selector:
    app: nginx-demo
  ports:
  - port: 80
    targetPort: 80
EOF

# Verify
kubectl get pods -n demo --context=apps-cluster
```

**Check in Prometheus:**
- Grafana → Explore
- Datasource: Prometheus-apps
- Query: `up{namespace="demo"}`

---

## What You Have Now

✅ **mgmt cluster (Raspberry Pi 5)**
- Argo CD (GitOps control plane)
- Prometheus (self-monitoring)
- Grafana (central dashboards)
- Pi-hole (DNS + ad blocking)
- cert-manager (TLS certificates)
- Sealed Secrets (secret management)

✅ **apps cluster (Office PC)**
- Prometheus (self-monitoring)
- cert-manager (TLS certificates)
- Sealed Secrets (secret management)
- Ready for application workloads

✅ **GitOps Workflow**
- All config in Git
- Argo CD auto-syncs changes
- Easy rollback with `git revert`

✅ **Multi-Cluster Monitoring**
- Grafana queries both clusters
- Unified dashboards
- Per-cluster Prometheus instances

---

## Next Steps

### Security Hardening

```bash
# Change default passwords
# Edit these files and commit to Git:
vim clusters/mgmt/prometheus-values.yaml  # Grafana admin password
vim clusters/mgmt/pihole-values.yaml      # Pi-hole admin password

# Create SealedSecrets (see docs/secrets-management.md)
```

### Add More Nodes to Apps Cluster

See [docs/runbooks/add-node.md](runbooks/add-node.md)

### Deploy Production Applications

```bash
# Create GitOps-managed application
mkdir -p clusters/apps/app-workloads/myapp
vim clusters/apps/app-workloads/myapp/deployment.yaml
vim clusters/apps/app-workloads/myapp/service.yaml

git add clusters/apps/app-workloads/myapp/
git commit -m "Add myapp deployment"
git push origin main

# Argo CD auto-syncs to apps cluster
```

### Configure Pi-hole as LAN DNS

1. Get Pi-hole LoadBalancer IP:
   ```bash
   kubectl get svc -n pihole pihole-dns-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```

2. Configure your router DHCP to use this IP as DNS server

3. All devices on LAN now use Pi-hole for DNS

### Setup Backups

See [docs/runbooks/rebuild-mgmt.md](runbooks/rebuild-mgmt.md#prevention-backup-critical-data)

---

## Troubleshooting

### Argo CD application stuck syncing

```bash
# Force refresh
kubectl patch application <app-name> -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Pod not starting

```bash
# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl describe pod <pod-name> -n <namespace>
```

### Can't access services

```bash
# Check Traefik
kubectl get svc traefik -n traefik

# Check IngressRoutes
kubectl get ingressroute -A
```

### Run validation script

```bash
./docs/runbooks/validate-cluster.sh mgmt
./docs/runbooks/validate-cluster.sh apps
```

---

## Support

- **Documentation**: See `docs/` directory
- **Runbooks**: See `docs/runbooks/`
- **Issues**: https://github.com/YOUR_USERNAME/homelab/issues

---

## Summary

You now have a production-grade homelab with:
- **GitOps**: Everything in Git, auto-deployed
- **Multi-cluster**: Separate mgmt and apps clusters
- **Monitoring**: Per-cluster Prometheus, central Grafana
- **Scalable**: Add nodes with one command
- **Rebuildable**: Restore from Git in 30 minutes

**Total setup time:** ~50 minutes

**Maintenance time:** ~5 minutes/week (mostly Git commits)

Welcome to the future of homelab management!
