# 🚀 START HERE

## Setup

```bash
# 1. Create config.env (update with YOUR IPs)
cp config.env.example config.env
vim config.env
```

```bash
# 2. Add to /etc/hosts (use YOUR IPs from config.env)
192.168.1.10   controller.local argocd.mgmt.local grafana.mgmt.local
192.168.1.20   server.local
192.168.1.53   pihole.local
```

```bash
# 3. Update and commit
source config.env
find . -name "*.yaml" -exec sed -i "s/YOUR_USERNAME/${GITHUB_USERNAME}/g" {} +
git add . && git commit -m "Configure homelab" && git push
```

## Bootstrap Clusters

```bash
./docs/runbooks/01-bootstrap-mgmt.sh
./docs/runbooks/02-bootstrap-apps.sh
```

## Verify

```bash
kubectl get nodes
kubectl get applications -n argocd
open http://controller.local  # Argo CD (admin/see bootstrap output)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
open http://localhost:3000  # Grafana (admin/admin)
```

## Done

You now have:
- Management cluster (controller.local) with Argo CD, Grafana, Pi-hole
- Apps cluster (server.local) ready for workloads
- GitOps workflow for all config

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for common commands.
