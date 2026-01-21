# Quick Reference

## Configuration (config.env)

```bash
MGMT_IP="192.168.1.10"    # UPDATE: Your Pi IP
APPS_IP="192.168.1.20"    # UPDATE: Your PC IP
PIHOLE_LB_IP="192.168.1.53"
```

## /etc/hosts (Use your actual IPs)

```
192.168.1.10   controller.local argocd.mgmt.local grafana.mgmt.local
192.168.1.20   server.local
192.168.1.53   pihole.local
```

## Access

```bash
# SSH
ssh ubuntu@controller.local
ssh ubuntu@server.local

# Services
http://controller.local       # Argo CD
http://localhost:3000         # Grafana (port-forward)
http://pihole.local/admin     # Pi-hole
```

## Bootstrap

```bash
# 1. Configure
source config.env
find . -name "*.yaml" -exec sed -i "s/YOUR_USERNAME/${GITHUB_USERNAME}/g" {} +
git add . && git commit -m "Configure homelab" && git push

# 2. Deploy clusters
./docs/runbooks/01-bootstrap-mgmt.sh
./docs/runbooks/02-bootstrap-apps.sh
```

## Verify

```bash
kubectl get nodes
kubectl get applications -n argocd
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

## Troubleshooting

```bash
source config.env && ping $MGMT_IP
kubectl logs -n <namespace> <pod>
argocd app sync <app-name>
```
