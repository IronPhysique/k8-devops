# Add New PC Node to Apps Cluster

This runbook provides exact steps to add a new PC as a worker node to the apps cluster.

## Prerequisites

- New PC with Ubuntu 22.04/24.04 LTS installed
- Static IP assigned (e.g., `192.168.1.21`)
- SSH access configured
- Hostnames in `/etc/hosts`:
  ```
  192.168.1.20  apps-pc1
  192.168.1.21  apps-pc2  # New node
  ```

## Architecture After Node Addition

```
apps cluster:
├── apps-pc1 (control-plane + worker)  # Existing
└── apps-pc2 (worker)                  # New node
```

New node will automatically:
- Join the cluster
- Get monitored by Prometheus (node-exporter DaemonSet)
- Ship logs via Promtail (DaemonSet)
- Run application workloads (if scheduled)

---

## Step 1: Get k3s Join Token

On the **existing control-plane node** (apps-pc1):

```bash
ssh ubuntu@192.168.1.20

# Get join token
sudo cat /var/lib/rancher/k3s/server/node-token

# Output will be something like:
# K10abc123def456ghi789jkl012mno345pqr678stu901vwx234yz::server:abc123def456
```

**Save this token** - you'll need it in Step 2.

---

## Step 2: Install k3s on New Node

On the **new node** (apps-pc2):

```bash
NEW_NODE_IP="192.168.1.21"
NEW_NODE_HOSTNAME="apps-pc2"
CONTROL_PLANE_IP="192.168.1.20"  # apps-pc1
K3S_TOKEN="<PASTE_TOKEN_HERE>"   # From Step 1

# SSH to new node
ssh ubuntu@${NEW_NODE_IP}

# Set hostname (optional but recommended)
sudo hostnamectl set-hostname ${NEW_NODE_HOSTNAME}

# System prep
sudo apt update
sudo apt install -y curl

# Install k3s agent (worker mode)
curl -sfL https://get.k3s.io | K3S_URL=https://${CONTROL_PLANE_IP}:6443 \
  K3S_TOKEN="${K3S_TOKEN}" \
  sh -s - agent \
  --node-label "homelab/cluster=apps" \
  --node-label "homelab/workload=true" \
  --node-label "kubernetes.io/arch=amd64"

# Wait for node to join
echo "Waiting for k3s agent to start..."
until systemctl is-active --quiet k3s-agent; do
  sleep 5
done

echo "k3s agent started successfully"
```

---

## Step 3: Verify Node Joined Cluster

From your **workstation**:

```bash
# Check nodes in apps cluster
kubectl get nodes --context=apps-cluster

# Expected output:
# NAME       STATUS   ROLES                  AGE   VERSION
# apps-pc1   Ready    control-plane,master   7d    v1.28.5+k3s1
# apps-pc2   Ready    <none>                 30s   v1.28.5+k3s1

# Check node labels
kubectl get node apps-pc2 --show-labels --context=apps-cluster

# Should include:
# homelab/cluster=apps
# homelab/workload=true
# kubernetes.io/arch=amd64
```

---

## Step 4: Verify Monitoring and Logging

GitOps-managed DaemonSets automatically deploy to new nodes.

### Check DaemonSets Running

```bash
# Node exporter (Prometheus metrics)
kubectl get pods -n monitoring -o wide --context=apps-cluster | grep node-exporter
# Should show pod running on apps-pc2

# Promtail (log shipping)
kubectl get pods -n monitoring -o wide --context=apps-cluster | grep promtail
# Should show pod running on apps-pc2
```

### Verify Metrics in Prometheus

```bash
# Port-forward to apps Prometheus
kubectl --context=apps-cluster port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open browser: http://localhost:9090
# Execute query:
up{instance=~"apps-pc2.*"}

# Should return metrics from new node
```

### Verify Logs in Loki (if deployed)

```bash
# Query Loki for logs from new node
kubectl --context=apps-cluster port-forward -n monitoring svc/loki 3100:3100

# Use Grafana Explore or logcli:
logcli query '{node="apps-pc2"}' --addr=http://localhost:3100
```

---

## Step 5: Label Node for Workload Scheduling (Optional)

Add custom labels for workload placement:

```bash
# Example: Label for GPU workloads
kubectl label node apps-pc2 homelab/gpu=nvidia-rtx4090 --context=apps-cluster

# Example: Label for high-memory workloads
kubectl label node apps-pc2 homelab/memory=high --context=apps-cluster

# Verify labels
kubectl get node apps-pc2 --show-labels --context=apps-cluster
```

Use these labels in Deployments:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        homelab/gpu: nvidia-rtx4090
```

---

## Step 6: Taint Node for Specialized Workloads (Optional)

If this node should ONLY run specific workloads:

```bash
# Taint node to prevent general workloads
kubectl taint node apps-pc2 workload=gpu:NoSchedule --context=apps-cluster

# Only pods with this toleration will schedule:
# tolerations:
#   - key: "workload"
#     operator: "Equal"
#     value: "gpu"
#     effect: "NoSchedule"
```

---

## Step 7: Validation Checklist

Run these checks to confirm node is fully operational:

```bash
# 1. Node is Ready
kubectl get node apps-pc2 --context=apps-cluster | grep Ready

# 2. Core components running
kubectl get pods -A -o wide --context=apps-cluster | grep apps-pc2

# Expected pods on new node:
# - kube-system: kube-proxy, coredns (maybe)
# - monitoring: node-exporter, promtail

# 3. Prometheus scraping node
kubectl --context=apps-cluster port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Query: up{job="node-exporter",instance=~"apps-pc2.*"}
# Should return: 1 (up)

# 4. Node resources available
kubectl top node apps-pc2 --context=apps-cluster

# 5. Schedule test workload
kubectl run nginx-test --image=nginx --context=apps-cluster --overrides='
{
  "spec": {
    "nodeSelector": {
      "kubernetes.io/hostname": "apps-pc2"
    }
  }
}'

kubectl get pod nginx-test -o wide --context=apps-cluster
# Should show: Running on apps-pc2

# Cleanup
kubectl delete pod nginx-test --context=apps-cluster
```

---

## Troubleshooting

### Node stuck in NotReady

```bash
# Check k3s agent logs on new node
ssh ubuntu@192.168.1.21
sudo journalctl -u k3s-agent -f

# Common issues:
# - Firewall blocking ports 6443, 10250
# - Incorrect join token
# - Network connectivity to control plane
```

### Node joined but no DaemonSet pods

```bash
# Check DaemonSet status
kubectl get daemonsets -A --context=apps-cluster

# Check if node has taints preventing scheduling
kubectl describe node apps-pc2 --context=apps-cluster | grep -A5 Taints

# If unwanted taint exists:
kubectl taint node apps-pc2 node.kubernetes.io/not-ready:NoSchedule- --context=apps-cluster
```

### Prometheus not scraping new node

```bash
# Check ServiceMonitor for node-exporter
kubectl get servicemonitor -n monitoring --context=apps-cluster

# Check Prometheus targets
kubectl --context=apps-cluster port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Browser: http://localhost:9090/targets
# Look for node-exporter target with new node IP
```

### Node has old k3s version

```bash
# Upgrade k3s on new node to match control plane
ssh ubuntu@192.168.1.21

# Get control plane version first
kubectl version --short --context=apps-cluster

# Upgrade agent
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.28.5+k3s1 sh -s - agent
```

---

## Node Removal (Bonus)

To remove a node from the cluster:

```bash
# 1. Drain node (evict workloads)
kubectl drain apps-pc2 --ignore-daemonsets --delete-emptydir-data --context=apps-cluster

# 2. Delete node from cluster
kubectl delete node apps-pc2 --context=apps-cluster

# 3. On the node itself, uninstall k3s
ssh ubuntu@192.168.1.21
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

---

## Summary

After completing these steps:

✅ New node joined apps cluster
✅ DaemonSets deployed (monitoring, logging)
✅ Node appears in Prometheus metrics
✅ Node ready to accept workload scheduling

**Repeat this runbook for each additional PC** you add to the apps cluster.

For horizontal scaling, simply:
1. Provision new PC with Ubuntu
2. Assign static IP
3. Run Steps 2-7 above

No GitOps changes needed - all platform components auto-deploy via DaemonSets.
