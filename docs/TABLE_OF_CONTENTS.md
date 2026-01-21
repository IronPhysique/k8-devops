# Documentation

## Getting Started

1. **[Prerequisites](00-prerequisites.md)** - Hardware, software, network requirements
2. **[Quick Start](quickstart.md)** - Deploy in 1 hour
3. **[Repository Structure](../STRUCTURE.md)** - Directory organization

## Setup Scripts

- **[Bootstrap Management Cluster](../bootstrap/01-bootstrap-mgmt.sh)** - Install k3s + ArgoCD on Pi
- **[Bootstrap Apps Cluster](../bootstrap/02-bootstrap-apps.sh)** - Install k3s on PC
- **[Configure Cross-Cluster Monitoring](runbooks/03-configure-cross-cluster-monitoring.md)** - Connect Grafana to apps Prometheus

## Operational Runbooks

### Day-to-Day
- **[Add Node](runbooks/add-node.md)** - Scale apps cluster
- **[Validate Cluster Health](runbooks/validate-cluster.sh)** - Health checks

### Maintenance
- **[Upgrade Strategy](runbooks/upgrade-strategy.md)** - k3s, Helm charts, images
- **[Rotate Sealed Secrets](runbooks/rotate-sealed-secrets.md)** - Key rotation

### Disaster Recovery
- **[Rebuild Management Cluster](runbooks/rebuild-mgmt.md)** - RTO: 30-45 min
- **[Rebuild Apps Cluster](runbooks/rebuild-apps.md)** - RTO: 20-30 min

## Platform Guides

- **[Secrets Management](secrets-management.md)** - Sealed Secrets workflow
- **[ArgoCD Guide](../argocd/README.md)** - App management, troubleshooting

## Repository Files

- **[README.md](../README.md)** - Project overview
- **[STRUCTURE.md](../STRUCTURE.md)** - Repository organization
- **[CHANGELOG.md](../CHANGELOG.md)** - Recent changes
- **[NETWORK.md](../NETWORK.md)** - Network configuration

## Quick Reference

```bash
# Where are the...?
Bootstrap scripts:     bootstrap/
ArgoCD apps:          argocd/applications/
Helm values:          argocd/applications/<cluster>/<category>/<app>/values.yaml
Runbooks:             docs/runbooks/
Examples:             examples/
```

## External Links

- [k3s Documentation](https://docs.k3s.io)
- [Argo CD Documentation](https://argo-cd.readthedocs.io)
- [Prometheus Documentation](https://prometheus.io/docs)
- [Grafana Documentation](https://grafana.com/docs)
