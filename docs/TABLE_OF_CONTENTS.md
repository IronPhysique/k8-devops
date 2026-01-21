# Documentation Table of Contents

Complete guide to your homelab platform.

## Quick Start

1. **[Prerequisites](00-prerequisites.md)** - Hardware, software, network setup
2. **[Quick Start Guide](quickstart.md)** - Get running in 1 hour
3. **[Implementation Summary](IMPLEMENTATION_SUMMARY.md)** - Complete architecture overview

## Installation

### Phase-by-Phase Setup

1. **[Bootstrap Management Cluster](runbooks/01-bootstrap-mgmt.sh)**
   - Install k3s on Raspberry Pi 5
   - Install Argo CD
   - Deploy platform components
   - ~15 minutes

2. **[Bootstrap Apps Cluster](runbooks/02-bootstrap-apps.sh)**
   - Install k3s on Office PC
   - Register with Argo CD
   - Deploy platform components
   - ~15 minutes

3. **[Configure Cross-Cluster Monitoring](runbooks/03-configure-cross-cluster-monitoring.md)**
   - Expose apps Prometheus
   - Configure Grafana datasources
   - ~10 minutes

## Operational Runbooks

### Day-to-Day Operations

- **[Add Node to Apps Cluster](runbooks/add-node.md)**
  - Scale horizontally by adding PCs
  - Exact join commands
  - Validation steps

- **[Validate Cluster Health](runbooks/validate-cluster.sh)**
  - Automated health checks
  - Run after any change
  - Usage: `./validate-cluster.sh {mgmt|apps}`

### Maintenance

- **[Upgrade Strategy](runbooks/upgrade-strategy.md)**
  - k3s upgrades
  - Helm chart upgrades
  - Container image updates
  - Rollback procedures

- **[Rotate Sealed Secrets](runbooks/rotate-sealed-secrets.md)**
  - Key rotation procedure
  - Recommended: quarterly
  - Re-seal all secrets

### Disaster Recovery

- **[Rebuild Management Cluster](runbooks/rebuild-mgmt.md)**
  - Complete mgmt cluster failure
  - Restore from Git + backups
  - RTO: 30-45 minutes

- **[Rebuild Apps Cluster](runbooks/rebuild-apps.md)**
  - Complete apps cluster failure
  - Restore from Git + backups
  - RTO: 20-30 minutes

## Platform Guides

### Security

- **[Secrets Management](secrets-management.md)**
  - Sealed Secrets workflow
  - Creating encrypted secrets
  - GitOps-safe secret storage
  - Backup and restore

### Monitoring

- **Architecture**: Per-cluster Prometheus, central Grafana
- **Cross-Cluster Queries**: Grafana multi-datasource
- **Custom Dashboards**: ConfigMap-based dashboard loading
- **Alerts**: AlertManager configuration (TBD)

### Networking

- **Ingress**: Traefik IngressRoute examples
- **DNS**: Pi-hole configuration
- **TLS**: cert-manager automated certificates
- **LoadBalancer**: k3s servicelb or MetalLB

## Repository Structure

```
homelab/
├── README.md                    # Project overview
├── .gitignore                   # Protect secrets
│
├── bootstrap/                   # Initial installation
│   ├── argocd-install.yaml     # Argo CD setup
│   └── root-app.yaml           # GitOps entry point
│
├── argocd/                      # GitOps configuration
│   ├── projects.yaml           # AppProjects
│   ├── applicationsets/        # Platform components
│   └── applications/           # Individual apps
│
├── clusters/                    # Per-cluster config
│   ├── mgmt/                   # Management cluster
│   │   ├── *-values.yaml       # Helm values
│   │   ├── *-clusterissuer.yaml
│   │   └── *-sealed.yaml       # Encrypted secrets
│   └── apps/                   # Apps cluster
│       ├── *-values.yaml
│       └── app-workloads/      # User applications
│
├── platform/                    # Shared templates (future)
│
├── examples/                    # Example deployments
│   ├── simple-app/             # Nginx demo
│   ├── database-app/           # PostgreSQL + pgAdmin
│   └── monitoring-dashboard/   # Custom Grafana dashboard
│
└── docs/                        # Documentation
    ├── 00-prerequisites.md
    ├── quickstart.md
    ├── secrets-management.md
    ├── IMPLEMENTATION_SUMMARY.md
    ├── TABLE_OF_CONTENTS.md (this file)
    └── runbooks/               # Operational procedures
        ├── 01-bootstrap-mgmt.sh
        ├── 02-bootstrap-apps.sh
        ├── 03-configure-cross-cluster-monitoring.md
        ├── add-node.md
        ├── rebuild-mgmt.md
        ├── rebuild-apps.md
        ├── rotate-sealed-secrets.md
        ├── upgrade-strategy.md
        └── validate-cluster.sh
```

## Component Documentation

### Management Cluster Components

| Component | Version | Documentation | Config File |
|-----------|---------|---------------|-------------|
| k3s | v1.28+ | https://docs.k3s.io | N/A (script install) |
| Argo CD | v2.12+ | https://argo-cd.readthedocs.io | bootstrap/argocd-install.yaml |
| kube-prometheus-stack | 67.7.0 | https://github.com/prometheus-community/helm-charts | clusters/mgmt/prometheus-values.yaml |
| Sealed Secrets | v0.27.4 | https://sealed-secrets.netlify.app | clusters/mgmt/sealed-secrets-values.yaml |
| cert-manager | v1.16.2 | https://cert-manager.io/docs | clusters/mgmt/cert-manager-values.yaml |
| Pi-hole | 2024.07.0 | https://docs.pi-hole.net | clusters/mgmt/pihole-values.yaml |
| Traefik | v3.0+ | https://doc.traefik.io/traefik | Bundled with k3s |

### Apps Cluster Components

| Component | Version | Documentation | Config File |
|-----------|---------|---------------|-------------|
| k3s | v1.28+ | https://docs.k3s.io | N/A (script install) |
| kube-prometheus-stack | 67.7.0 | https://github.com/prometheus-community/helm-charts | clusters/apps/prometheus-values.yaml |
| Sealed Secrets | v0.27.4 | https://sealed-secrets.netlify.app | clusters/apps/sealed-secrets-values.yaml |
| cert-manager | v1.16.2 | https://cert-manager.io/docs | clusters/apps/cert-manager-values.yaml |
| Traefik | v3.0+ | https://doc.traefik.io/traefik | Bundled with k3s |

## GitOps Patterns

### App-of-Apps Pattern

```
root Application (syncs argocd/ directory)
├── projects.yaml (AppProjects)
├── ApplicationSets (generate multiple apps)
│   ├── mgmt-platform (sealed-secrets, cert-manager, prometheus, promtail)
│   └── apps-platform (sealed-secrets, cert-manager, prometheus, promtail)
└── Individual Applications (pihole, etc.)
```

**Benefit:** Single `kubectl apply -f bootstrap/root-app.yaml` deploys everything.

### ApplicationSet Pattern

```yaml
# Defines list of components
elements:
  - name: sealed-secrets
    chart: sealed-secrets
    version: 2.16.2
  - name: cert-manager
    chart: cert-manager
    version: v1.16.2
```

**Benefit:** Add component to list → Argo auto-creates Application.

## Troubleshooting

### Common Issues

#### Argo CD Application Stuck Syncing

**Symptom:** Application shows "Syncing" indefinitely

**Solutions:**
```bash
# Check application status
kubectl get application <app-name> -n argocd -o yaml

# Force refresh
argocd app sync <app-name> --prune

# Delete and recreate
kubectl delete application <app-name> -n argocd
kubectl apply -f argocd/applicationsets/...
```

#### Pod Not Starting

**Symptom:** Pod in CrashLoopBackOff or Pending

**Solutions:**
```bash
# Check logs
kubectl logs <pod-name> -n <namespace>

# Check events
kubectl describe pod <pod-name> -n <namespace>

# Check resource quotas
kubectl describe node

# Common fixes:
# - Resource limits too low
# - Image pull error (check imagePullSecrets)
# - Volume mount issue (check PVCs)
```

#### Sealed Secret Not Decrypting

**Symptom:** SealedSecret exists but Secret not created

**Solutions:**
```bash
# Check controller logs
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller

# Common errors:
# - "no key could decrypt secret": Re-seal with correct cluster cert
# - Controller not running: Check pod status

# Re-seal with correct cert
kubeseal --fetch-cert --context=<correct-cluster> > cert.pem
kubeseal --cert=cert.pem < plain.yaml > sealed.yaml
```

#### Cross-Cluster Monitoring Not Working

**Symptom:** Grafana can't query apps Prometheus

**Solutions:**
```bash
# Test connectivity
kubectl --context=default run curl-test --rm -it --image=curlimages/curl -- \
  curl -v http://192.168.1.20:9090/api/v1/status/config

# Check datasource config
kubectl get configmap grafana-datasource-apps -n monitoring -o yaml

# Restart Grafana
kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
```

## Advanced Topics

### Multi-Architecture Support

This homelab supports mixed architectures:
- **mgmt cluster**: ARM64 (Raspberry Pi 5)
- **apps cluster**: AMD64 (Office PCs)

All platform components use multi-arch images. When deploying custom apps:

```yaml
# Specify architecture
nodeSelector:
  kubernetes.io/arch: amd64  # or arm64

# Or use multi-arch images
image: nginx:latest  # Official images support both
```

### Storage Considerations

**Default:** local-path (k3s bundled)
- **Pros:** Simple, no external deps
- **Cons:** Node-pinned, data lost if node fails

**Upgrades:**
- **NFS:** Shared storage across nodes
- **Longhorn:** Distributed block storage
- **Rook/Ceph:** Full distributed storage cluster

### Network Policies

Add namespace-level network policies:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### Resource Quotas

Limit namespace resource usage:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
```

## External Resources

### Official Documentation

- **k3s**: https://docs.k3s.io
- **Argo CD**: https://argo-cd.readthedocs.io
- **Helm**: https://helm.sh/docs
- **Kubernetes**: https://kubernetes.io/docs

### Community

- **k3s GitHub**: https://github.com/k3s-io/k3s
- **Argo CD GitHub**: https://github.com/argoproj/argo-cd
- **Homelab Subreddit**: https://reddit.com/r/homelab
- **Self-Hosted**: https://reddit.com/r/selfhosted

### Learning Resources

- **Kubernetes Basics**: https://kubernetes.io/docs/tutorials/kubernetes-basics/
- **GitOps Guide**: https://www.gitops.tech
- **Prometheus**: https://prometheus.io/docs/introduction/overview/
- **Grafana**: https://grafana.com/docs/grafana/latest/

## Support

### Getting Help

1. **Check documentation** in `docs/` directory
2. **Run validation script**: `./docs/runbooks/validate-cluster.sh`
3. **Review Argo CD UI** for sync errors
4. **Check logs**: `kubectl logs -n <namespace> <pod>`
5. **Search issues**: https://github.com/YOUR_USERNAME/homelab/issues

### Contributing

Found a bug or have an improvement?

```bash
# Create feature branch
git checkout -b feature/my-improvement

# Make changes
vim clusters/mgmt/something.yaml

# Commit
git commit -am "Improve something"

# Push and create PR
git push origin feature/my-improvement
```

---

## Summary

This documentation covers:

✅ Installation (quick start + detailed phases)
✅ Operations (add nodes, validate, upgrade)
✅ Disaster recovery (rebuild from Git)
✅ Security (secrets management, TLS)
✅ Monitoring (Prometheus, Grafana)
✅ Troubleshooting (common issues)
✅ Examples (sample deployments)

**Next Steps:**
1. Follow [Quick Start Guide](quickstart.md) to get running
2. Bookmark this Table of Contents
3. Explore examples in `examples/` directory

Welcome to production-grade homelab! 🎉
