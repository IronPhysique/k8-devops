# Quick Start Guide

Get your homelab running in under 1 hour.

## Prerequisites Checklist

- [ ] Raspberry Pi 5 with Ubuntu 22.04/24.04 (hostname: controller.local)
- [ ] Office PC with Ubuntu 22.04/24.04 (hostname: server.local)
- [ ] Static IPs assigned via DHCP
- [ ] SSH access to both machines
- [ ] Git configured on workstation
- [ ] Fork/clone this repository

See [00-prerequisites.md](00-prerequisites.md) for detailed setup.

## Step 1: Update Configuration (5 min)

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# Update GitHub username
find . -type f -name "*.yaml" -exec sed -i 's/YOUR_USERNAME/your-github-username/g' {} +

# Commit
git add .
git commit -m "Configure homelab for my environment"
git push origin main
```

## Step 2: Bootstrap Management Cluster (15 min)

```bash
# Run bootstrap script
./bootstrap/01-bootstrap-mgmt.sh

# Save ArgoCD password shown at end
```

**Installs:** k3s, ArgoCD, platform components (Prometheus, cert-manager, sealed-secrets, Pi-hole)

**Validate:**
```bash
kubectl get applications -n argocd
# All should show: Synced, Healthy
```

## Step 3: Bootstrap Apps Cluster (15 min)

```bash
# Run apps cluster bootstrap
./bootstrap/02-bootstrap-apps.sh
```

**Installs:** k3s, registers with ArgoCD, deploys platform components

**Validate:**
```bash
kubectl get nodes --context=default         # mgmt cluster
kubectl get nodes --context=apps-cluster    # apps cluster
kubectl get applications -n argocd | grep apps-
```

## Step 4: Access Services

### ArgoCD

```bash
# Get mgmt cluster IP
MGMT_IP=192.168.1.10  # Update with your IP

# Open browser
echo "ArgoCD: http://$MGMT_IP"
# Login: admin / <password from Step 2>
```

### Grafana

```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Open: http://localhost:3000
# Login: admin / prom-operator
```

### Pi-hole

```bash
# Open: http://pihole.local/admin
# Or: http://<mgmt-ip>/admin
```

## What You Have

✅ **mgmt cluster (Raspberry Pi):**
- ArgoCD, Prometheus, Grafana, Pi-hole, cert-manager, sealed-secrets

✅ **apps cluster (PC):**
- Prometheus, cert-manager, sealed-secrets (ready for workloads)

✅ **GitOps Workflow:**
- All config in Git, ArgoCD auto-syncs, easy rollback

## Next Steps

### Deploy Your First App

```bash
# Create app directory
mkdir -p argocd/applications/apps/services/myapp

# Add application.yaml and manifests
# See argocd/README.md for examples

# Commit and push
git add argocd/applications/apps/services/myapp/
git commit -m "Add myapp"
git push
```

### Harden Security

```bash
# Change Grafana password
vim argocd/applications/mgmt/platform/kube-prometheus-stack/values.yaml

# Change Pi-hole password
vim argocd/applications/mgmt/services/pihole/values.yaml

# Use Sealed Secrets for sensitive data
# See docs/secrets-management.md
```

### Configure Pi-hole as LAN DNS

Get Pi-hole IP and configure router DHCP to use it as DNS server.

## Troubleshooting

### Application stuck syncing

```bash
argocd app sync <app-name> --prune
```

### Pod not starting

```bash
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

### Validation script

```bash
./docs/runbooks/validate-cluster.sh mgmt
./docs/runbooks/validate-cluster.sh apps
```

## References

- [STRUCTURE.md](../STRUCTURE.md) - Repository organization
- [TABLE_OF_CONTENTS.md](TABLE_OF_CONTENTS.md) - Complete documentation index
- [secrets-management.md](secrets-management.md) - Managing secrets
