# Rebuild Management Cluster from Scratch

This runbook restores the mgmt cluster to full operational state from Git.

## Disaster Scenario

- Raspberry Pi 5 SD card corrupted
- Complete cluster failure
- Starting from fresh Ubuntu installation

## Recovery Time

- **Estimated:** 30-45 minutes
- **Downtime:** Full mgmt cluster outage (apps cluster continues running)

---

## Prerequisites

- Fresh Ubuntu 22.04/24.04 on Raspberry Pi 5
- Static IP: `192.168.1.10` (same as before)
- SSH access configured
- Git repository accessible

---

## Rebuild Steps

### Step 1: Restore System Configuration

```bash
ssh ubuntu@192.168.1.10

# Set hostname
sudo hostnamectl set-hostname mgmt-rpi5

# Update system
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git
```

### Step 2: Install k3s

```bash
# Same command as initial bootstrap
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --tls-san 192.168.1.10 \
  --node-label "node-role.kubernetes.io/control-plane=true" \
  --node-label "homelab/cluster=mgmt"

# Wait for k3s
until sudo k3s kubectl get nodes | grep -q Ready; do
  sleep 5
done
```

### Step 3: Copy Kubeconfig to Workstation

```bash
# From workstation
scp ubuntu@192.168.1.10:/etc/rancher/k3s/k3s.yaml ~/.kube/config-mgmt
sed -i "s/127.0.0.1/192.168.1.10/g" ~/.kube/config-mgmt
export KUBECONFIG=~/.kube/config-mgmt

kubectl get nodes  # Should show mgmt-rpi5 Ready
```

### Step 4: Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=600s
```

### Step 5: Install Traefik

```bash
kubectl apply -f - << 'EOF'
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
      dns-tcp:
        port: 8053
        exposedPort: 53
        protocol: TCP
      dns-udp:
        port: 8054
        exposedPort: 53
        protocol: UDP
    service:
      type: LoadBalancer
EOF

kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n traefik --timeout=300s
```

### Step 6: Deploy Root Application

```bash
# Clone Git repo if needed
git clone https://github.com/YOUR_USERNAME/homelab.git
cd homelab

# Apply root app
kubectl apply -f bootstrap/root-app.yaml

# Watch applications sync
watch kubectl get applications -n argocd
```

All platform components will automatically deploy:
- ✅ sealed-secrets
- ✅ cert-manager
- ✅ kube-prometheus-stack (Prometheus + Grafana)
- ✅ promtail
- ✅ pihole

---

## Step 7: Restore Sealed Secrets Key (Critical)

**If you have a backup of the sealed-secrets key:**

```bash
# Restore the sealing key from backup
kubectl apply -f /path/to/backup/sealed-secrets-key.yaml -n sealed-secrets

# Restart sealed-secrets controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets
```

**If you DON'T have a backup:**

All existing SealedSecrets will be unusable. You must:

1. Extract the NEW public key:
   ```bash
   kubeseal --fetch-cert --controller-name=sealed-secrets-controller --controller-namespace=sealed-secrets > pub-cert.pem
   ```

2. Re-seal all secrets using the new key:
   ```bash
   # For each secret, re-run kubeseal
   kubectl create secret generic example --dry-run=client --from-literal=password=secret -o yaml | \
     kubeseal --cert=pub-cert.pem -o yaml > example-sealed.yaml
   ```

3. Update Git and commit new SealedSecrets.

---

## Step 8: Re-register Apps Cluster (if needed)

If apps cluster was also lost or credentials changed:

```bash
# Get token from apps cluster
APPS_TOKEN=$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.token}' | base64 -d)
APPS_CA=$(kubectl --context=apps-cluster get secret argocd-manager-token -n kube-system -o jsonpath='{.data.ca\.crt}')

# Register with Argo CD
kubectl apply -f - << EOF
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

---

## Step 9: Validation

```bash
# All applications synced
kubectl get applications -n argocd

# All expected:
# - mgmt-sealed-secrets    Synced  Healthy
# - mgmt-cert-manager      Synced  Healthy
# - mgmt-kube-prometheus   Synced  Healthy
# - mgmt-promtail          Synced  Healthy
# - pihole                 Synced  Healthy
# - apps-sealed-secrets    Synced  Healthy
# - apps-cert-manager      Synced  Healthy
# - apps-kube-prometheus   Synced  Healthy
# - apps-promtail          Synced  Healthy

# Prometheus up
kubectl get pods -n monitoring

# Grafana accessible
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Browser: http://localhost:3000

# Pi-hole accessible
PIHOLE_IP=$(kubectl get svc -n pihole pihole-dns-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://${PIHOLE_IP}/admin/
```

---

## What Gets Restored Automatically (via GitOps)

✅ All platform components (Prometheus, Grafana, cert-manager, etc.)
✅ All configurations (Helm values from Git)
✅ All Argo CD Applications
✅ Dashboards and monitoring config
✅ Network policies, ingress routes

## What Requires Manual Restore

❌ Prometheus metrics history (lost unless backed up)
❌ Grafana dashboards (if not in Git - should be in ConfigMaps)
❌ Sealed Secrets key (requires backup)
❌ Pi-hole configuration (blocklists, custom DNS - use persistence)

---

## Prevention: Backup Critical Data

Create backups of these resources:

```bash
# 1. Sealed Secrets key
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml

# 2. Prometheus data (optional)
# Use velero or manual PV backup

# 3. Pi-hole config (if using hostPath)
ssh ubuntu@192.168.1.10
sudo tar -czf pihole-backup.tar.gz /var/lib/rancher/k3s/storage/...
```

Store backups in:
- Encrypted cloud storage (S3, B2)
- Off-site location
- Encrypted USB drive

---

## Recovery Time Optimization

To speed up future rebuilds:

1. **Pre-download k3s binary:**
   ```bash
   curl -sfL https://get.k3s.io -o k3s-install.sh
   chmod +x k3s-install.sh
   ```

2. **Keep kubeconfigs backed up:**
   Store `~/.kube/config-mgmt` securely

3. **Document custom changes:**
   Any manual tweaks should be in Git or documented

---

## Summary

With GitOps, rebuilding the mgmt cluster is:
1. Install k3s (5 min)
2. Install Argo CD (5 min)
3. Apply root app (1 min)
4. Wait for sync (20 min)
5. Restore sealed-secrets key (2 min)

**Total:** ~30-45 minutes to full operation.

Compare to manual rebuild: **hours to days**.

This is the power of Infrastructure as Code + GitOps.
