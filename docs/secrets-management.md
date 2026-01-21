# Secrets Management with Sealed Secrets

This guide covers how to manage secrets securely in GitOps using Sealed Secrets.

## Concept

**Problem:** Kubernetes Secrets are base64-encoded, not encrypted. Storing them in Git exposes credentials.

**Solution:** Sealed Secrets
- **Encryption:** Secrets are encrypted using public key cryptography
- **Controller:** Runs in-cluster, holds private key to decrypt
- **GitOps-Safe:** Encrypted SealedSecrets can be committed to Git
- **Per-Cluster:** Each cluster has its own encryption key

---

## How It Works

```
Developer Workstation              Git Repository              Kubernetes Cluster
┌──────────────────┐              ┌──────────────┐            ┌────────────────────┐
│ Plain Secret     │              │ SealedSecret │            │ Sealed Secrets     │
│ (password: abc)  │──kubeseal──▶│ (encrypted)  │──ArgoCD──▶│ Controller         │
└──────────────────┘              └──────────────┘            │ Decrypts to Secret │
                                                              └────────────────────┘
```

1. Create plain Kubernetes Secret (locally, never commit)
2. Encrypt with `kubeseal` CLI (uses cluster's public cert)
3. Commit encrypted SealedSecret to Git
4. Argo CD syncs to cluster
5. Controller decrypts to plain Secret
6. Applications use plain Secret

---

## Prerequisites

Install `kubeseal` CLI:

```bash
# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.4-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# macOS
brew install kubeseal

# Verify
kubeseal --version
```

---

## Creating Your First SealedSecret

### Example: Grafana Admin Password

#### Step 1: Create Plain Secret

```bash
# Create secret locally (DO NOT COMMIT)
kubectl create secret generic grafana-admin-password \
  --namespace=monitoring \
  --from-literal=admin-password=SuperSecurePassword123 \
  --dry-run=client -o yaml > /tmp/grafana-secret-plain.yaml

# View plain secret (base64 encoded)
cat /tmp/grafana-secret-plain.yaml
```

#### Step 2: Fetch Public Certificate

```bash
# For mgmt cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  --context=default \
  > pub-cert-mgmt.pem

# For apps cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  --context=apps-cluster \
  > pub-cert-apps.pem
```

#### Step 3: Seal the Secret

```bash
# Encrypt with public cert (for mgmt cluster)
kubeseal --cert=pub-cert-mgmt.pem \
  --format=yaml \
  < /tmp/grafana-secret-plain.yaml \
  > clusters/mgmt/grafana-admin-password-sealed.yaml

# View encrypted secret (safe for Git)
cat clusters/mgmt/grafana-admin-password-sealed.yaml
```

#### Step 4: Commit to Git

```bash
git add clusters/mgmt/grafana-admin-password-sealed.yaml
git commit -m "Add Grafana admin password (sealed)"
git push origin main
```

#### Step 5: Apply via Argo CD

**Option A: Let Argo CD auto-sync**

Argo CD will detect the new SealedSecret and sync it.

**Option B: Manual apply**

```bash
kubectl apply -f clusters/mgmt/grafana-admin-password-sealed.yaml
```

#### Step 6: Verify

```bash
# Check SealedSecret resource
kubectl get sealedsecret grafana-admin-password -n monitoring

# Check decrypted Secret (controller creates this)
kubectl get secret grafana-admin-password -n monitoring

# View decrypted value
kubectl get secret grafana-admin-password -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
```

---

## Common Use Cases

### 1. Pi-hole Admin Password

```bash
# Create plain secret
kubectl create secret generic pihole-admin \
  --namespace=pihole \
  --from-literal=password=YourPiholePassword \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-mgmt.pem \
  --format=yaml \
  > clusters/mgmt/pihole-admin-sealed.yaml

# Commit
git add clusters/mgmt/pihole-admin-sealed.yaml
git commit -m "Add Pi-hole admin password (sealed)"
git push
```

Update Pi-hole Helm values to use secret:

```yaml
# clusters/mgmt/pihole-values.yaml
adminPassword:
  existingSecret: pihole-admin
  secretKey: password
```

### 2. Registry Credentials (for private Docker registries)

```bash
# Create docker-registry secret
kubectl create secret docker-registry regcred \
  --namespace=default \
  --docker-server=ghcr.io \
  --docker-username=your-username \
  --docker-password=your-token \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-apps.pem \
  --format=yaml \
  > clusters/apps/regcred-sealed.yaml

git add clusters/apps/regcred-sealed.yaml
git commit -m "Add registry credentials (sealed)"
git push
```

### 3. Database Connection String

```bash
kubectl create secret generic db-connection \
  --namespace=myapp \
  --from-literal=dsn="postgresql://user:pass@db.example.com:5432/mydb?sslmode=require" \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-apps.pem \
  --format=yaml \
  > clusters/apps/app-workloads/myapp/db-connection-sealed.yaml
```

### 4. TLS Certificate

```bash
kubectl create secret tls myapp-tls \
  --namespace=myapp \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-apps.pem \
  --format=yaml \
  > clusters/apps/app-workloads/myapp/tls-sealed.yaml
```

---

## Secret Scopes

SealedSecrets can be sealed with different scopes:

### Strict (default) - namespace + name specific

```bash
# Can ONLY be unsealed in namespace "monitoring" with name "grafana-admin-password"
kubeseal --cert=pub-cert-mgmt.pem \
  --scope=strict \
  < plain-secret.yaml > sealed-secret.yaml
```

### Namespace-wide - any name in namespace

```bash
# Can be renamed, but must stay in same namespace
kubeseal --cert=pub-cert-mgmt.pem \
  --scope=namespace-wide \
  < plain-secret.yaml > sealed-secret.yaml
```

### Cluster-wide - any namespace, any name

```bash
# Can be moved anywhere in cluster (least secure)
kubeseal --cert=pub-cert-mgmt.pem \
  --scope=cluster-wide \
  < plain-secret.yaml > sealed-secret.yaml
```

**Recommendation:** Use `strict` (default) for production.

---

## Updating Secrets

To change a secret value:

```bash
# 1. Create new plain secret with updated value
kubectl create secret generic grafana-admin-password \
  --namespace=monitoring \
  --from-literal=admin-password=NewPassword456 \
  --dry-run=client -o yaml > /tmp/grafana-secret-updated.yaml

# 2. Re-seal
kubeseal --cert=pub-cert-mgmt.pem \
  < /tmp/grafana-secret-updated.yaml \
  > clusters/mgmt/grafana-admin-password-sealed.yaml

# 3. Commit
git add clusters/mgmt/grafana-admin-password-sealed.yaml
git commit -m "Update Grafana admin password"
git push

# 4. Sync (Argo CD auto-syncs)
# Or force: kubectl apply -f clusters/mgmt/grafana-admin-password-sealed.yaml

# 5. Restart pods to pick up new secret
kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring
```

---

## Backup and Recovery

### Backup Sealing Key

**CRITICAL:** Backup your sealing key to restore cluster from scratch.

```bash
# For mgmt cluster
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-mgmt-backup.yaml

# For apps cluster
kubectl --context=apps-cluster get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-apps-backup.yaml

# Encrypt backups
gpg --encrypt --recipient your-email@example.com sealed-secrets-key-mgmt-backup.yaml

# Store securely (S3, 1Password, etc.)
```

### Restore Sealing Key

When rebuilding cluster:

```bash
# Decrypt backup
gpg --decrypt sealed-secrets-key-mgmt-backup.yaml.gpg > sealed-secrets-key-mgmt-backup.yaml

# Apply to cluster
kubectl apply -f sealed-secrets-key-mgmt-backup.yaml

# Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets

# All existing SealedSecrets will now decrypt successfully
```

---

## Security Best Practices

### 1. Never Commit Plain Secrets

```bash
# Add to .gitignore
echo "*-plain.yaml" >> .gitignore
echo "*.pem" >> .gitignore  # Public certs are safe but keep them local
```

### 2. Rotate Keys Regularly

See [rotate-sealed-secrets.md](runbooks/rotate-sealed-secrets.md)

### 3. Limit Access to Clusters

Only users with kubectl access to the cluster can decrypt secrets.

### 4. Use RBAC

```yaml
# Prevent non-admin users from reading secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: no-secrets
  namespace: production
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: []  # No permissions
```

### 5. Audit Secret Usage

```bash
# Find all SealedSecrets in cluster
kubectl get sealedsecrets -A

# Check who accessed secrets (requires audit logging)
kubectl logs -n kube-system kube-apiserver-* | grep "secrets/grafana-admin-password"
```

---

## Troubleshooting

### SealedSecret not decrypting

```bash
# Check controller logs
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller

# Common errors:
# - "no key could decrypt secret": Wrong cluster or key rotated
# - "failed to unseal: context deadline exceeded": Controller not running
```

**Solution:**
```bash
# Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets

# If using wrong key, re-seal with correct cluster cert
kubeseal --fetch-cert --context=<correct-context> > pub-cert-correct.pem
kubeseal --cert=pub-cert-correct.pem < plain.yaml > sealed.yaml
```

### Lost sealing key, SealedSecrets unusable

**Solution:**
1. Generate new sealing key (automatic when sealed-secrets deploys)
2. Re-seal ALL secrets with new key (painful, but necessary)
3. This is why backups are critical

### Public cert expires

Public certs don't expire, but controller may generate new key.

```bash
# Re-fetch cert and re-seal secrets
kubeseal --fetch-cert > pub-cert-new.pem
kubeseal --cert=pub-cert-new.pem < plain.yaml > sealed.yaml
```

---

## Integration with CI/CD

For automated secret creation in CI:

```yaml
# GitHub Actions example
name: Deploy App
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install kubeseal
        run: |
          wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-amd64.tar.gz
          tar -xvzf kubeseal-0.27.4-linux-amd64.tar.gz
          sudo install -m 755 kubeseal /usr/local/bin/kubeseal

      - name: Create SealedSecret
        env:
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
        run: |
          kubectl create secret generic db-creds \
            --from-literal=password=$DB_PASSWORD \
            --dry-run=client -o yaml | \
          kubeseal --cert=pub-cert-apps.pem -o yaml \
            > app/db-creds-sealed.yaml

      - name: Commit and push
        run: |
          git add app/db-creds-sealed.yaml
          git commit -m "Update db credentials"
          git push
```

---

## Comparison to Alternatives

| Solution | Pros | Cons |
|----------|------|------|
| **Sealed Secrets** | Simple, GitOps-native, no external deps | Key management, per-cluster |
| **SOPS** | Flexible, multiple backends | Requires external KMS (AWS/GCP) |
| **External Secrets** | Centralized, cloud-native | Requires external vault |
| **Vault** | Enterprise features, dynamic secrets | Complex, resource-heavy |

**Recommendation:** Sealed Secrets for homelab (simple, free, works offline).

---

## Summary

**Workflow:**
1. Create plain secret locally
2. Seal with `kubeseal`
3. Commit encrypted SealedSecret to Git
4. Argo CD syncs to cluster
5. Controller decrypts to plain Secret

**Key Points:**
- ✅ SealedSecrets safe for Git
- ✅ Per-cluster encryption keys
- ✅ GitOps-friendly
- ⚠️ Backup sealing keys
- ⚠️ Rotate keys regularly

For detailed key rotation, see [rotate-sealed-secrets.md](runbooks/rotate-sealed-secrets.md)
