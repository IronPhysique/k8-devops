# Implementation Summary

Complete implementation of a production-grade two-cluster Kubernetes homelab with GitOps.

---

## Architecture

### Clusters

**Management Cluster (mgmt)**
- **Hardware:** Raspberry Pi 5 (ARM64)
- **IP:** 192.168.1.10
- **Role:** GitOps control plane, central observability, DNS
- **Components:**
  - Argo CD (manages both clusters)
  - Grafana (central dashboards)
  - Prometheus (self-monitoring)
  - Pi-hole (DNS + ad blocking)
  - cert-manager, Sealed Secrets

**Applications Cluster (apps)**
- **Hardware:** Office PC(s) (AMD64)
- **IP:** 192.168.1.20+ (scales horizontally)
- **Role:** Application workloads
- **Components:**
  - Prometheus (self-monitoring)
  - cert-manager, Sealed Secrets
  - Traefik Ingress
  - Application workloads

### Key Design Decisions

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **K8s Distro** | k3s | Lightweight, ARM64 support, single binary |
| **GitOps** | Argo CD | Industry standard, ApplicationSets, multi-cluster |
| **Charts** | Helm | Declarative, versioned, parameterized |
| **Ingress** | Traefik | k3s native, TCP/UDP support for Pi-hole |
| **Storage** | local-path | Simple, no external dependencies |
| **Secrets** | Sealed Secrets | GitOps-safe, no external KMS required |
| **Certificates** | cert-manager + self-signed | Automated TLS for internal services |
| **Monitoring** | kube-prometheus-stack | Complete stack: Prometheus + Grafana + AlertManager |

---

## Repository Structure

```
homelab/
├── README.md                           # Project overview
├── .gitignore                          # Protect secrets
├── bootstrap/
│   ├── argocd-install.yaml            # Argo CD installation
│   └── root-app.yaml                  # App-of-Apps pattern entry point
├── argocd/
│   ├── projects.yaml                  # AppProjects (mgmt, apps, applications)
│   ├── applicationsets/
│   │   ├── mgmt-platform.yaml         # Platform for mgmt cluster
│   │   └── apps-platform.yaml         # Platform for apps cluster
│   └── applications/
│       └── pihole.yaml                # Pi-hole Application
├── clusters/
│   ├── mgmt/
│   │   ├── sealed-secrets-values.yaml
│   │   ├── cert-manager-values.yaml
│   │   ├── cert-manager-clusterissuer.yaml
│   │   ├── prometheus-values.yaml     # Grafana enabled here
│   │   ├── promtail-values.yaml
│   │   ├── pihole-values.yaml
│   │   ├── pihole-traefik.yaml        # DNS LoadBalancer
│   │   └── grafana-datasource-apps.yaml  # Cross-cluster monitoring
│   └── apps/
│       ├── sealed-secrets-values.yaml
│       ├── cert-manager-values.yaml
│       ├── cert-manager-clusterissuer.yaml
│       ├── prometheus-values.yaml     # Grafana disabled
│       ├── promtail-values.yaml
│       ├── prometheus-ingress.yaml    # Expose for mgmt Grafana
│       └── app-workloads/             # User applications
├── platform/                           # Shared platform templates (future)
└── docs/
    ├── 00-prerequisites.md
    ├── quickstart.md
    ├── secrets-management.md
    ├── IMPLEMENTATION_SUMMARY.md (this file)
    └── runbooks/
        ├── 01-bootstrap-mgmt.sh       # Bootstrap mgmt cluster
        ├── 02-bootstrap-apps.sh       # Bootstrap apps cluster
        ├── 03-configure-cross-cluster-monitoring.md
        ├── add-node.md                # Add PC to apps cluster
        ├── rebuild-mgmt.md            # Disaster recovery mgmt
        ├── rebuild-apps.md            # Disaster recovery apps
        ├── rotate-sealed-secrets.md   # Key rotation
        ├── upgrade-strategy.md        # Upgrade all components
        └── validate-cluster.sh        # Health check script
```

---

## GitOps Workflow

### Application Deployment Flow

```
Developer → Git Commit → GitHub → Argo CD → Kubernetes Cluster
   │                                  │
   │                                  ├─→ mgmt cluster (Pi 5)
   │                                  └─→ apps cluster (PC)
   │
   └─→ One commit deploys to both clusters
```

### ApplicationSet Pattern

```yaml
# argocd/applicationsets/mgmt-platform.yaml
# Defines ALL platform components for mgmt cluster
# - sealed-secrets
# - cert-manager
# - kube-prometheus-stack
# - promtail

# Changes to list auto-create/update Argo Applications
```

### App-of-Apps Pattern

```
root Application (bootstrap/root-app.yaml)
├── projects.yaml
├── mgmt-platform ApplicationSet
│   ├── mgmt-sealed-secrets
│   ├── mgmt-cert-manager
│   ├── mgmt-kube-prometheus-stack
│   └── mgmt-promtail
├── apps-platform ApplicationSet
│   ├── apps-sealed-secrets
│   ├── apps-cert-manager
│   ├── apps-kube-prometheus-stack
│   └── apps-promtail
└── pihole Application
```

---

## Multi-Cluster Monitoring

### Architecture

```
┌─────────────────────────────────────────┐
│  mgmt cluster (192.168.1.10)            │
│  ┌────────────┐      ┌───────────────┐  │
│  │  Grafana   │─────→│ Prometheus    │  │
│  │ (central)  │ local│ (mgmt metrics)│  │
│  └─────┬──────┘      └───────────────┘  │
│        │                                 │
└────────┼─────────────────────────────────┘
         │
         │ HTTP query (port 9090)
         │
┌────────▼─────────────────────────────────┐
│  apps cluster (192.168.1.20)             │
│  ┌──────────────┐   ┌────────────────┐   │
│  │   Traefik    │──→│  Prometheus    │   │
│  │ IngressRoute │   │ (apps metrics) │   │
│  └──────────────┘   └────────────────┘   │
│  Exposed on LAN                          │
└──────────────────────────────────────────┘
```

### Datasource Configuration

Grafana in mgmt cluster has two Prometheus datasources:
- **Prometheus-mgmt**: Local (http://kube-prometheus-stack-prometheus.monitoring.svc:9090)
- **Prometheus-apps**: Remote (http://192.168.1.20:9090)

Both datasources can be queried independently or compared in multi-query panels.

---

## Horizontal Scaling (Add PC Nodes)

### Process

1. **Provision new PC** with Ubuntu 22.04/24.04
2. **Assign static IP** (e.g., 192.168.1.21)
3. **Run join command** on new PC:
   ```bash
   curl -sfL https://get.k3s.io | K3S_URL=https://192.168.1.20:6443 \
     K3S_TOKEN="<token>" sh -s - agent
   ```
4. **Automatic GitOps deployment**:
   - node-exporter DaemonSet deploys (Prometheus scrapes)
   - promtail DaemonSet deploys (ships logs)
   - Workloads can now schedule on new node

**No Git changes required** - DaemonSets auto-deploy to new nodes.

See [docs/runbooks/add-node.md](runbooks/add-node.md) for detailed steps.

---

## Disaster Recovery

### Rebuild mgmt Cluster

**Time:** ~30-45 minutes
**Downtime:** mgmt cluster only (apps continues running)

```bash
1. Install k3s on Pi
2. Install Argo CD
3. Apply root app (bootstrap/root-app.yaml)
4. Restore sealed-secrets key from backup
5. Wait for GitOps sync
```

**Result:** Full mgmt cluster restored from Git + backup key.

See [docs/runbooks/rebuild-mgmt.md](runbooks/rebuild-mgmt.md)

### Rebuild apps Cluster

**Time:** ~20-30 minutes
**Downtime:** apps cluster only

```bash
1. Install k3s on PC
2. Re-register with Argo CD
3. Wait for GitOps sync
4. Re-add worker nodes
```

**Result:** Full apps cluster restored from Git.

See [docs/runbooks/rebuild-apps.md](runbooks/rebuild-apps.md)

---

## Security

### Secrets Management

**Sealed Secrets:**
- Encrypted with cluster public key
- Safe to commit to Git
- Decrypted by controller in-cluster
- Per-cluster keys (mgmt and apps have different keys)

**Workflow:**
```bash
# Create plain secret
kubectl create secret generic myapp-creds --from-literal=password=secret --dry-run=client -o yaml > plain.yaml

# Seal it
kubeseal --cert=pub-cert.pem < plain.yaml > sealed.yaml

# Commit sealed version to Git
git add sealed.yaml && git commit -m "Add credentials (sealed)" && git push

# Argo CD syncs, controller decrypts
```

See [docs/secrets-management.md](secrets-management.md)

### Network Security

- **Firewall:** ufw configured on all nodes (ports 6443, 10250, 8472)
- **TLS:** cert-manager provides automated TLS for internal services
- **RBAC:** Argo CD service account with cluster-admin (can be scoped down)
- **Network Policies:** Can be added per namespace (not implemented by default)

### Audit Trail

- **Git history:** Every change tracked in Git commits
- **Argo CD sync status:** Shows what changed when
- **Sealed Secrets rotation:** Documented in [docs/runbooks/rotate-sealed-secrets.md](runbooks/rotate-sealed-secrets.md)

---

## Platform Components

### Management Cluster (mgmt)

| Component | Version | Purpose | Resource Usage |
|-----------|---------|---------|----------------|
| k3s | v1.28+ | Kubernetes distro | Minimal |
| Argo CD | v2.12+ | GitOps controller | ~500MB RAM |
| Traefik | v3.0+ | Ingress controller | ~100MB RAM |
| kube-prometheus-stack | 67.7.0 | Monitoring stack | ~2GB RAM |
| Sealed Secrets | v0.27.4 | Secret encryption | ~128MB RAM |
| cert-manager | v1.16.2 | Certificate management | ~256MB RAM |
| Pi-hole | 2024.07.0 | DNS + ad blocking | ~512MB RAM |
| Promtail | 3.2.1 | Log shipping | ~128MB RAM |

**Total:** ~4GB RAM usage (Pi 5 8GB recommended)

### Apps Cluster (apps)

| Component | Version | Purpose | Resource Usage |
|-----------|---------|---------|----------------|
| k3s | v1.28+ | Kubernetes distro | Minimal |
| Traefik | v3.0+ | Ingress controller | ~200MB RAM |
| kube-prometheus-stack | 67.7.0 | Monitoring (no Grafana) | ~1.5GB RAM |
| Sealed Secrets | v0.27.4 | Secret encryption | ~128MB RAM |
| cert-manager | v1.16.2 | Certificate management | ~256MB RAM |
| Promtail | 3.2.1 | Log shipping | ~128MB RAM |

**Total:** ~2.2GB RAM for platform (leaves room for workloads)

---

## Upgrade Strategy

### Quarterly Upgrades

1. **k3s:** Minor version bumps
2. **Helm charts:** Update versions in ApplicationSets
3. **Container images:** Update in values files

### Process

```bash
# Update chart version in Git
vim argocd/applicationsets/mgmt-platform.yaml
# Change version: 67.7.0 → 68.0.0

# Commit
git commit -am "Upgrade kube-prometheus-stack to 68.0.0"
git push

# Argo CD auto-syncs upgrade
```

### Rollback

```bash
# Revert Git commit
git revert HEAD
git push

# Argo CD auto-syncs rollback
```

See [docs/runbooks/upgrade-strategy.md](runbooks/upgrade-strategy.md)

---

## Validation

Run validation script after any change:

```bash
./docs/runbooks/validate-cluster.sh mgmt
./docs/runbooks/validate-cluster.sh apps
```

Checks:
- ✅ Cluster connectivity
- ✅ Node health
- ✅ System pods running
- ✅ Argo CD applications synced (mgmt only)
- ✅ Platform components healthy
- ✅ Monitoring operational
- ✅ DaemonSets deployed

---

## Operational Runbooks

All runbooks located in `docs/runbooks/`:

| Runbook | Purpose | Frequency |
|---------|---------|-----------|
| 01-bootstrap-mgmt.sh | Initial mgmt cluster setup | Once |
| 02-bootstrap-apps.sh | Initial apps cluster setup | Once |
| 03-configure-cross-cluster-monitoring.md | Grafana datasources | Once |
| add-node.md | Add PC to apps cluster | As needed |
| rebuild-mgmt.md | Disaster recovery mgmt | Emergency |
| rebuild-apps.md | Disaster recovery apps | Emergency |
| rotate-sealed-secrets.md | Key rotation | Quarterly |
| upgrade-strategy.md | Component upgrades | Quarterly |
| validate-cluster.sh | Health check | After changes |

---

## What You Get

### Production Features

✅ **GitOps:** Single source of truth in Git
✅ **Multi-Cluster:** Separate mgmt and apps clusters
✅ **Monitoring:** Per-cluster Prometheus, central Grafana
✅ **Secrets:** Encrypted SealedSecrets in Git
✅ **TLS:** Automated certificate management
✅ **DNS:** Pi-hole for network-wide ad blocking
✅ **Scalability:** Add nodes with one command
✅ **Rebuildability:** Restore from Git in 30 minutes
✅ **Audit Trail:** Git history of all changes
✅ **Rollback:** `git revert` for any change

### Developer Experience

- **One command deploys:** `git push` → Argo CD syncs
- **No manual kubectl:** All changes via Git
- **Visual UI:** Argo CD dashboard shows sync status
- **Validation:** Automated health checks
- **Documentation:** Complete runbooks for all operations

### Operations

- **Maintenance:** ~5 minutes/week (mostly Git commits)
- **Monitoring:** Unified Grafana dashboards for both clusters
- **Alerts:** Prometheus AlertManager (configure as needed)
- **Backups:** Sealed Secrets key backup is critical
- **Upgrades:** GitOps-driven, easy rollback

---

## Next Steps

After completing quick start:

1. **Secure Secrets:**
   - Change default passwords (Grafana, Pi-hole)
   - Create SealedSecrets for credentials
   - Backup sealed-secrets keys

2. **Deploy Applications:**
   - Add deployments to `clusters/apps/app-workloads/`
   - Commit to Git
   - Argo CD auto-syncs

3. **Add Nodes:**
   - Follow `docs/runbooks/add-node.md`
   - Scale apps cluster horizontally

4. **Configure Pi-hole:**
   - Set router DNS to Pi-hole LoadBalancer IP
   - Configure blocklists
   - Monitor DNS queries

5. **Customize Monitoring:**
   - Add custom Grafana dashboards
   - Configure AlertManager rules
   - Set up notification channels

6. **Implement Backups:**
   - Backup sealed-secrets keys
   - Consider Velero for PV backups
   - Document restore procedures

---

## Support & Maintenance

### Weekly Tasks

- Check Argo CD for sync status
- Review Grafana dashboards for anomalies
- Update application images (if needed)

### Monthly Tasks

- Update Helm chart versions
- Review and rotate secrets (if policy requires)
- Check for k3s security updates

### Quarterly Tasks

- Upgrade platform components (see upgrade-strategy.md)
- Rotate sealed-secrets keys (see rotate-sealed-secrets.md)
- Review and update documentation

### Annual Tasks

- Review architecture for scaling needs
- Audit RBAC permissions
- Update hardware if needed

---

## Metrics

**Setup Time:**
- Initial implementation: ~50 minutes
- Add node to apps cluster: ~10 minutes
- Deploy new application: ~5 minutes (Git commit)

**Resource Usage:**
- mgmt cluster: ~4GB RAM (Pi 5 8GB recommended)
- apps cluster platform: ~2GB RAM (leaves room for workloads)

**Reliability:**
- Recovery time objective (RTO): 30-45 minutes (from Git + backups)
- Recovery point objective (RPO): Last Git commit (minutes)

**Cost:**
- Raspberry Pi 5 8GB: ~$80
- Office PC: Repurposed existing hardware
- Total new cost: ~$80 + SD card

---

## Conclusion

This implementation provides a **production-grade Kubernetes homelab** with:

- **Enterprise patterns:** GitOps, multi-cluster, observability
- **Developer-friendly:** All changes via Git
- **Operations-ready:** Complete runbooks, automated validation
- **Cost-effective:** Runs on homelab hardware
- **Scalable:** Add nodes horizontally
- **Maintainable:** ~5 minutes/week ongoing effort

**The result:** A platform that teaches real-world Kubernetes while being practical for home use.

Enjoy your homelab! 🚀
