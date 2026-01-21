# Upgrade Strategy

This runbook covers upgrading all components of the homelab platform.

## Components to Upgrade

1. **k3s** (Kubernetes distribution)
2. **Argo CD**
3. **Helm charts** (platform components)
4. **Container images**

---

## General Principles

- **Test in apps cluster first** (less critical than mgmt)
- **One component at a time** (avoid cascading failures)
- **Always check release notes** (breaking changes)
- **Backup before upgrade** (sealed-secrets keys, PVs)
- **GitOps-first**: Update Git, let Argo sync

---

## 1. Upgrading k3s

### Check Current Version

```bash
# mgmt cluster
ssh ubuntu@192.168.1.10 'k3s --version'

# apps cluster
ssh ubuntu@192.168.1.20 'k3s --version'
```

### Upgrade Procedure

**For single-node clusters:**

```bash
# mgmt cluster (Pi 5)
ssh ubuntu@192.168.1.10

# Download specific version
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.30.0+k3s1 sh -

# Verify
sudo systemctl status k3s
kubectl get nodes
```

**For multi-node apps cluster:**

```bash
# 1. Upgrade control plane first
ssh ubuntu@192.168.1.20
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.30.0+k3s1 sh -

# 2. Upgrade workers one-by-one
ssh ubuntu@192.168.1.21

# Drain node first
kubectl drain apps-pc2 --ignore-daemonsets --delete-emptydir-data

# Upgrade
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.30.0+k3s1 sh -

# Uncordon
kubectl uncordon apps-pc2

# Verify
kubectl get pods -A -o wide | grep apps-pc2
```

### Rollback k3s

```bash
# k3s doesn't support easy rollback
# Best practice: restore from backup or rebuild

# Download specific older version
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.29.5+k3s1 sh -
```

---

## 2. Upgrading Argo CD

Argo CD upgrades are applied via new manifest.

### Check Current Version

```bash
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Upgrade Procedure

```bash
# 1. Check release notes
# https://github.com/argoproj/argo-cd/releases

# 2. Update to new version
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.0/manifests/install.yaml

# 3. Verify
kubectl rollout status deployment argocd-server -n argocd
kubectl get applications -n argocd  # All should remain Synced
```

### Rollback Argo CD

```bash
# Apply previous version manifest
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/manifests/install.yaml
```

---

## 3. Upgrading Helm Charts (Platform Components)

All platform charts are managed via ApplicationSets in Git.

### Check Current Versions

```bash
# List applications and chart versions
kubectl get applications -n argocd -o json | \
  jq -r '.items[] | "\(.metadata.name): \(.spec.source.targetRevision)"'

# Example output:
# mgmt-kube-prometheus-stack: 67.7.0
# mgmt-sealed-secrets: 2.16.2
# apps-kube-prometheus-stack: 67.7.0
```

### Upgrade Procedure

**Example: Upgrade kube-prometheus-stack**

```bash
cd ~/homelab

# 1. Check for new chart version
helm search repo prometheus-community/kube-prometheus-stack --versions | head

# 2. Update ApplicationSet in Git
vim argocd/applicationsets/mgmt-platform.yaml

# Change:
#   version: 67.7.0
# To:
#   version: 68.0.0

# 3. Commit and push
git add argocd/applicationsets/mgmt-platform.yaml
git commit -m "Upgrade kube-prometheus-stack to 68.0.0"
git push origin main

# 4. Argo CD auto-syncs (or force sync)
kubectl patch application mgmt-kube-prometheus-stack -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# 5. Watch upgrade
kubectl get pods -n monitoring -w
```

### Upgrade All Charts

To upgrade all platform charts to latest versions:

```bash
# Update all chart versions in ApplicationSets
vim argocd/applicationsets/mgmt-platform.yaml
vim argocd/applicationsets/apps-platform.yaml

# Commit
git add argocd/applicationsets/
git commit -m "Upgrade all platform charts"
git push origin main

# Sync all
argocd app sync -l component=platform
```

### Rollback Chart Version

```bash
# Revert Git commit
git revert HEAD
git push origin main

# Argo auto-syncs rollback
# Or force sync:
argocd app sync mgmt-kube-prometheus-stack
```

---

## 4. Upgrading Container Images

### Platform Images

Most platform images are managed by Helm chart versions.

For custom image tags in values files:

```bash
cd ~/homelab

# Update image tag in values
vim clusters/mgmt/prometheus-values.yaml

# Example:
# prometheus:
#   prometheusSpec:
#     image:
#       tag: v2.56.2  # Change to v2.57.0

# Commit
git add clusters/mgmt/prometheus-values.yaml
git commit -m "Upgrade Prometheus image to v2.57.0"
git push origin main
```

### Application Images

For your own app deployments:

```bash
# Update image in app manifest
vim clusters/apps/app-workloads/myapp.yaml

# Change:
# image: myapp:v1.0.0
# To:
# image: myapp:v1.1.0

# Commit
git add clusters/apps/app-workloads/myapp.yaml
git commit -m "Upgrade myapp to v1.1.0"
git push origin main
```

---

## 5. Upgrade Testing

Before upgrading production:

### Test Chart Upgrades Locally

```bash
# Render chart with new version
helm template test-release prometheus-community/kube-prometheus-stack \
  --version 68.0.0 \
  --values clusters/mgmt/prometheus-values.yaml \
  > /tmp/new-prometheus.yaml

# Compare with current
helm get manifest kube-prometheus-stack -n monitoring > /tmp/current-prometheus.yaml
diff /tmp/current-prometheus.yaml /tmp/new-prometheus.yaml
```

### Use Argo CD Diff

Before syncing:

```bash
# See what will change
argocd app diff mgmt-kube-prometheus-stack

# Review output before confirming sync
```

---

## 6. Breaking Changes Checklist

Before any upgrade, check:

### k3s Upgrades

- [ ] Read release notes: https://github.com/k3s-io/k3s/releases
- [ ] Check Kubernetes version skew policy (max 1 minor version jump)
- [ ] Verify container runtime compatibility
- [ ] Test custom CNI/networking plugins

### Argo CD Upgrades

- [ ] Read upgrade notes: https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/
- [ ] Check API deprecations
- [ ] Verify CRD changes
- [ ] Test ApplicationSet functionality

### Helm Chart Upgrades

- [ ] Read chart changelog
- [ ] Check for values.yaml breaking changes
- [ ] Verify CRD updates (may require manual apply)
- [ ] Test on non-prod cluster first

---

## 7. Scheduled Maintenance Windows

Recommended upgrade schedule:

### Quarterly (Every 3 Months)

- k3s minor version updates
- Helm chart updates (platform)
- Security patches

### Monthly

- Container image updates (security patches)
- Application deployments

### As Needed

- Critical security vulnerabilities (CVEs)
- Bug fixes affecting operations

---

## 8. Emergency Rollback

If an upgrade breaks the cluster:

### Option 1: Git Revert (Preferred)

```bash
# Revert the commit
git revert HEAD
git push origin main

# Force sync
argocd app sync --prune -l component=platform
```

### Option 2: Manual Rollback

```bash
# Rollback specific deployment
kubectl rollout undo deployment <name> -n <namespace>

# Example
kubectl rollout undo deployment kube-prometheus-stack-operator -n monitoring
```

### Option 3: Restore from Backup

See [rebuild-mgmt.md](rebuild-mgmt.md) or [rebuild-apps.md](rebuild-apps.md)

---

## 9. Post-Upgrade Validation

After every upgrade:

```bash
# Run validation script
./docs/runbooks/validate-cluster.sh mgmt
./docs/runbooks/validate-cluster.sh apps

# Check all applications synced
kubectl get applications -n argocd

# Check all pods healthy
kubectl get pods -A | grep -v Running

# Check monitoring
kubectl get servicemonitors -A
kubectl get podmonitors -A

# Test Grafana dashboards
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000 and verify dashboards load

# Check Pi-hole (mgmt cluster)
curl -s http://pihole.mgmt.local/admin/ | grep -q "Pi-hole"
```

---

## 10. Upgrade Log Template

Keep a log of upgrades:

```markdown
## Upgrade Log

### 2024-01-15: k3s v1.29.5 → v1.30.0

**Cluster:** apps
**Reason:** Security patches
**Downtime:** 5 minutes
**Issues:** None
**Rollback:** N/A

### 2024-01-20: kube-prometheus-stack 67.7.0 → 68.0.0

**Cluster:** mgmt, apps
**Reason:** Feature update
**Downtime:** None (rolling update)
**Issues:** None
**Rollback:** N/A
```

Store in `docs/upgrade-log.md`

---

## Summary

**Upgrade Order:**

1. Test in apps cluster first
2. Upgrade apps cluster k3s
3. Upgrade apps cluster charts
4. Validate apps cluster
5. Upgrade mgmt cluster k3s
6. Upgrade mgmt cluster charts
7. Validate mgmt cluster

**Always:**
- Backup before upgrading
- Read release notes
- Test diff before sync
- Validate after upgrade
- Document changes

**GitOps Advantage:**
- Single source of truth
- Easy rollback (git revert)
- Audit trail (git log)
- Reproducible upgrades
