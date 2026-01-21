# Changelog

All notable changes to this homelab platform.

## [Unreleased] - 2026-01-21

### Added

#### New Services
- **nginx-router**: Reverse proxy for HTTP routing without port numbers
  - Routes `pihole.local` → Pi-hole web UI
  - Routes `argocd.local` → ArgoCD UI
  - Uses hostNetwork to bind directly to port 80
  - Location: `argocd/apps/nginx-router/base/`

#### Documentation
- **argocd/README.md**: Comprehensive guide for ArgoCD structure and usage
  - Directory structure explanation
  - App-of-Apps pattern documentation
  - How to add/update/delete applications
  - Troubleshooting guide
  - Best practices

### Changed

#### DNS Configuration
- **Pi-hole**: Reconfigured to use hostNetwork mode
  - Now binds directly to controller node's port 53
  - Disabled dnsmasq on controller node
  - Updated `argocd/clusters/mgmt/pihole-values.yaml`
  - No longer requires NodePort

#### ArgoCD Structure Reorganization
**Major restructuring for better readability and maintainability**

**Before:**
```
argocd/
├── projects.yaml
├── applicationsets/
│   ├── mgmt-platform.yaml  # All apps in one file
│   └── apps-platform.yaml  # All apps in one file
└── applications/
    └── pihole.yaml
```

**After:**
```
argocd/
├── bootstrap/
│   ├── projects.yaml       # AppProjects
│   └── root-app.yaml       # Root applications
├── applications/
│   ├── mgmt/
│   │   ├── platform/       # Individual app files
│   │   │   ├── sealed-secrets.yaml
│   │   │   ├── cert-manager.yaml
│   │   │   ├── kube-prometheus-stack.yaml
│   │   │   ├── alloy.yaml
│   │   │   └── nginx-router.yaml
│   │   └── services/
│   │       └── pihole.yaml
│   └── apps/
│       └── platform/       # Individual app files
│           ├── sealed-secrets.yaml
│           ├── cert-manager.yaml
│           ├── kube-prometheus-stack.yaml
│           └── alloy.yaml
└── apps/                   # Raw manifests for non-Helm apps
    └── nginx-router/       # Kustomize manifests
        └── base/
```

**Benefits:**
- Each application has its own YAML file for better readability
- Clear separation between platform and service applications
- Easier to maintain and understand
- Better git history (changes to one app don't affect others)
- Clearer structure for scaling

**Files Created:**
- `argocd/bootstrap/projects.yaml` (moved from `argocd/projects.yaml`)
- `argocd/bootstrap/root-app.yaml` (replaces old root app)
- `argocd/applications/mgmt/platform/sealed-secrets.yaml`
- `argocd/applications/mgmt/platform/cert-manager.yaml`
- `argocd/applications/mgmt/platform/kube-prometheus-stack.yaml`
- `argocd/applications/mgmt/platform/alloy.yaml`
- `argocd/applications/mgmt/platform/nginx-router.yaml`
- `argocd/applications/mgmt/services/pihole.yaml` (moved from `argocd/applications/pihole.yaml`)
- `argocd/applications/apps/platform/sealed-secrets.yaml`
- `argocd/applications/apps/platform/cert-manager.yaml`
- `argocd/applications/apps/platform/kube-prometheus-stack.yaml`
- `argocd/applications/apps/platform/alloy.yaml`

#### Bootstrap Scripts
- **bootstrap/01-bootstrap-mgmt.sh**:
  - Updated to deploy AppProjects from new location
  - Now applies `argocd/bootstrap/projects.yaml` before root app
  - Updated step 6 description

#### Documentation Updates
- **docs/TABLE_OF_CONTENTS.md**:
  - Updated directory structure to reflect new ArgoCD layout
  - Updated App-of-Apps pattern explanation
  - Updated troubleshooting examples with new paths

- **docs/runbooks/upgrade-strategy.md**:
  - Replaced all ApplicationSet references with individual Application files
  - Updated all example paths
  - Changed "ApplicationSets" to "individual Application files"

- **docs/IMPLEMENTATION_SUMMARY.md**:
  - Updated ArgoCD directory structure
  - Updated all reference paths

#### Root Application
- **bootstrap/root-app.yaml**: Changed path from `argocd` to `argocd/bootstrap`
  - Now bootstraps from the bootstrap directory
  - Syncs projects and root applications

### Removed

#### Deprecated Files
- `argocd/applicationsets/mgmt-platform.yaml` (replaced by individual files)
- `argocd/applicationsets/apps-platform.yaml` (replaced by individual files)
- `argocd/app-of-apps.yaml` (replaced by `argocd/bootstrap/root-app.yaml`)
- `argocd/projects/` (empty directory, moved to `argocd/bootstrap/`)

#### System Services
- **dnsmasq** on controller node:
  - Stopped and disabled to free port 53 for Pi-hole
  - Pi-hole now handles all DNS queries directly

### Technical Details

#### Network Configuration
- Controller node port 53: Now used by Pi-hole (was dnsmasq)
- Controller node port 80: Now used by nginx-router (hostNetwork)
- DNS resolution: Direct to Pi-hole on controller:53

#### ArgoCD Application Flow
```
kubectl apply -f bootstrap/root-app.yaml
            ↓
    bootstrap/root-app.yaml (syncs argocd/bootstrap/)
            ↓
    ┌───────┴────────┐
    ↓                ↓
mgmt-root        apps-root
    ↓                ↓
applications/    applications/
mgmt/           apps/
├─ platform/    └─ platform/
└─ services/
```

### Migration Guide

#### For Existing Installations

If you have an existing homelab with the old ApplicationSet structure:

1. **Backup current state:**
   ```bash
   kubectl get applications -n argocd -o yaml > backup-applications.yaml
   kubectl get applicationsets -n argocd -o yaml > backup-applicationsets.yaml
   ```

2. **Delete old ApplicationSets:**
   ```bash
   kubectl delete applicationset mgmt-platform -n argocd
   kubectl delete applicationset apps-platform -n argocd
   ```

3. **Pull latest changes:**
   ```bash
   git pull origin main
   ```

4. **Apply new structure:**
   ```bash
   kubectl apply -f argocd/bootstrap/projects.yaml
   kubectl apply -f bootstrap/root-app.yaml
   ```

5. **Verify applications sync:**
   ```bash
   kubectl get applications -n argocd
   ```

All applications should appear with `mgmt-` or `apps-` prefixes and sync automatically.

### Notes

- All changes are backward compatible in terms of deployed resources
- The restructuring only affects how applications are defined in Git
- Actual deployed resources remain unchanged
- ArgoCD will handle the transition smoothly with automated sync

### Contributors

- Homelab automation improvements
- DNS and network optimization
- Documentation enhancements
