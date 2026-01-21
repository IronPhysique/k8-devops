# Rebuild Apps Cluster from Scratch

This runbook restores the apps cluster to full operational state from Git.

## Disaster Scenario

- Apps cluster failure
- PC hardware replacement
- Starting from fresh Ubuntu installation

## Recovery Time

- **Estimated:** 20-30 minutes
- **Downtime:** Apps cluster only (mgmt cluster unaffected)

---

## Prerequisites

- Fresh Ubuntu 22.04/24.04 on PC
- Static IP: `192.168.1.20` (same as before)
- SSH access configured
- Mgmt cluster operational

---

## Rebuild Steps

### Step 1: Restore System Configuration

```bash
ssh ubuntu@192.168.1.20

# Set hostname
sudo hostnamectl set-hostname apps-pc1

# Update system
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl
```

### Step 2: Install k3s

```bash
# Same command as initial bootstrap
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --tls-san 192.168.1.20 \
  --node-label "node-role.kubernetes.io/control-plane=true" \
  --node-label "homelab/cluster=apps" \
  --node-label "homelab/workload=true"

# Wait for k3s
until sudo k3s kubectl get nodes | grep -q Ready; do
  sleep 5
done
```

### Step 3: Copy Kubeconfig to Workstation

```bash
# From workstation
scp ubuntu@192.168.1.20:/etc/rancher/k3s/k3s.yaml ~/.kube/config-apps
sed -i "s/127.0.0.1/192.168.1.20/g" ~/.kube/config-apps
sed -i "s/default/apps-cluster/g" ~/.kube/config-apps

# Merge with existing kubeconfig
export KUBECONFIG=~/.kube/config-mgmt:~/.kube/config-apps
kubectl config view --flatten > ~/.kube/config
export KUBECONFIG=~/.kube/config

kubectl get nodes --context=apps-cluster  # Should show apps-pc1 Ready
```

### Step 4: Install Traefik

```bash
kubectl --context=apps-cluster apply -f - << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: traefik
---
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: traefik
  namespace: kube-system
spec:
  repo: https://traefik.github.io/charts
  chart: traefik
  targetNamespace: traefik
  valuesContent: |-
    ports:
      web:
        exposedPort: 80
      websecure:
        exposedPort: 443
    service:
      type: LoadBalancer
EOF

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --context=apps-cluster --timeout=300s
```

### Step 5: Re-register with Argo CD

```bash
# Create service account for Argo CD
kubectl --context=apps-cluster apply -f - << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: argocd-manager
  namespace: kube-system
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: argocd-manager
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-manager-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: argocd-manager
    namespace: kube-system
EOF

# Wait for token
sleep 5

# Get credentials
APPS_TOKEN=$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
APPS_CA=$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.ca\.crt}')

# Register with mgmt cluster Argo CD
kubectl --context=default apply -f - << EOF
apiVersion: v1
kind: Secret
metadata:
  name: apps-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: apps-cluster
  server: https://192.168.1.20:6443
  config: |
    {
      "bearerToken": "${APPS_TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${APPS_CA}"
      }
    }
EOF
```

### Step 6: Wait for GitOps to Deploy Platform

Argo CD will automatically deploy all platform components:

```bash
# Watch applications sync
watch kubectl get applications -n argocd --context=default

# Expected apps-* applications:
# - apps-sealed-secrets
# - apps-cert-manager
# - apps-kube-prometheus-stack
# - apps-promtail

# Wait for all to be Synced and Healthy (5-10 minutes)
```

---

## Step 7: Restore Sealed Secrets Key (if backed up)

```bash
# If you have a backup of the apps cluster sealed-secrets key
kubectl apply -f /path/to/backup/apps-sealed-secrets-key.yaml -n sealed-secrets --context=apps-cluster

# Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets --context=apps-cluster
```

---

## Step 8: Re-add Worker Nodes (if multi-node)

If your apps cluster had additional worker nodes:

```bash
# Get new join token from rebuilt control plane
ssh ubuntu@192.168.1.20
sudo cat /var/lib/rancher/k3s/server/node-token

# On each worker node, rejoin cluster
ssh ubuntu@192.168.1.21  # apps-pc2
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.1.20:6443 \
  K3S_TOKEN="<NEW_TOKEN>" \
  sh -s - agent \
  --node-label "homelab/cluster=apps" \
  --node-label "homelab/workload=true"
```

See [add-node.md](add-node.md) for detailed steps.

---

## Step 9: Validation

```bash
# All apps-* applications synced
kubectl get applications -n argocd --context=default | grep apps-

# All platform pods running
kubectl get pods -A --context=apps-cluster

# Prometheus up
kubectl get pods -n monitoring --context=apps-cluster | grep prometheus

# Node exporter running
kubectl get daemonset -n monitoring --context=apps-cluster

# Test workload deployment
kubectl run nginx-test --image=nginx --context=apps-cluster
kubectl get pod nginx-test --context=apps-cluster  # Should be Running

# Cleanup
kubectl delete pod nginx-test --context=apps-cluster
```

---

## Step 10: Update Grafana Datasource (if IP changed)

If apps cluster IP changed, update Grafana datasource in mgmt cluster:

```bash
# Edit datasource ConfigMap
kubectl edit configmap grafana-datasource-apps -n monitoring --context=default

# Update URL to new IP:
# url: http://192.168.1.20:9090  # NEW IP

# Restart Grafana
kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring --context=default
```

---

## What Gets Restored Automatically (via GitOps)

✅ All platform components (Prometheus, cert-manager, etc.)
✅ All configurations (Helm values from Git)
✅ DaemonSets (node-exporter, promtail)
✅ Network policies, ingress routes

## What Requires Manual Restore

❌ Prometheus metrics history (lost unless backed up)
❌ Sealed Secrets key (requires backup)
❌ Application data (depends on storage solution)
❌ Persistent volumes (lost if using local-path without backup)

---

## Prevention: Backup Critical Data

```bash
# 1. Sealed Secrets key
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml --context=apps-cluster > apps-sealed-secrets-key-backup.yaml

# 2. Application PVs (use Velero or manual backup)
# Example: backup all PVs in apps cluster
kubectl get pv --context=apps-cluster -o yaml > apps-pvs-backup.yaml

# 3. Application manifests (should be in Git)
# Ensure all app deployments are in clusters/apps/app-workloads/
```

---

## Recovery Time Optimization

To speed up future rebuilds:

1. **Keep join token backed up** (securely):
   ```bash
   # Backup token from apps-pc1
   ssh ubuntu@192.168.1.20
   sudo cat /var/lib/rancher/k3s/server/node-token > ~/apps-cluster-token.txt
   # Store securely off-cluster
   ```

2. **Use persistent storage backend:**
   - NFS for shared storage
   - Longhorn for distributed storage
   - External NAS for critical data

3. **Document all manual changes:**
   Anything not in Git should be documented in `docs/manual-changes.md`

---

## Summary

With GitOps, rebuilding the apps cluster is:
1. Install k3s (5 min)
2. Re-register with Argo CD (2 min)
3. Wait for GitOps sync (10 min)
4. Re-add worker nodes if multi-node (5 min each)

**Total:** ~20-30 minutes to full operation.

The mgmt cluster (Argo CD) orchestrates the entire rebuild automatically.

---

## Multiple Node Clusters

If rebuilding a multi-node apps cluster:

1. Rebuild control-plane node (apps-pc1) using this runbook
2. Wait for all platform apps to sync
3. Add worker nodes one-by-one using [add-node.md](add-node.md)

All platform components (DaemonSets) auto-deploy to new nodes.
