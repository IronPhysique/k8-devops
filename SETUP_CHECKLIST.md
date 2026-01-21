# Setup Checklist

## Pre-Install

- [ ] Pi 5 + PC with Ubuntu 22.04/24.04
- [ ] Static IPs: Pi (.10), PC (.20)
- [ ] `kubectl` and `kubeseal` installed
- [ ] config.env created with your IPs
- [ ] Updated YOUR_USERNAME in YAMLs
- [ ] Pushed to GitHub

## Deploy

- [ ] `./docs/runbooks/01-bootstrap-mgmt.sh` (15min)
- [ ] `./docs/runbooks/02-bootstrap-apps.sh` (15min)
- [ ] Configure cross-cluster monitoring (docs/runbooks/03-*)

## Verify

```bash
kubectl get nodes
kubectl get applications -n argocd  # All Synced/Healthy
open http://controller.local        # Argo CD
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
open http://localhost:3000          # Grafana
```

## Done

- [ ] Both clusters healthy
- [ ] Argo CD managing apps
- [ ] Grafana showing metrics from both clusters
- [ ] Pi-hole blocking ads

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for commands.
