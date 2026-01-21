# Secrets Management with Sealed Secrets

Secure secrets management for GitOps using Sealed Secrets.

## Concept

**Problem:** Kubernetes Secrets are base64-encoded, not encrypted. Unsafe for Git.

**Solution:** Sealed Secrets encrypts secrets with public key cryptography. Only the in-cluster controller can decrypt them.

## Install kubeseal CLI

```bash
# macOS
brew install kubeseal

# Linux
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.4-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Quick Start

### 1. Fetch Cluster Certificate

```bash
# For mgmt cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  > pub-cert-mgmt.pem

# For apps cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  --context=apps-cluster \
  > pub-cert-apps.pem
```

### 2. Create and Seal Secret

```bash
# Create plain secret (DO NOT COMMIT)
kubectl create secret generic my-secret \
  --namespace=myapp \
  --from-literal=password=SuperSecret123 \
  --dry-run=client -o yaml > /tmp/plain-secret.yaml

# Encrypt with kubeseal
kubeseal --cert=pub-cert-mgmt.pem \
  --format=yaml \
  < /tmp/plain-secret.yaml \
  > argocd/applications/mgmt/services/myapp/sealed-secret.yaml

# Clean up
rm /tmp/plain-secret.yaml
```

### 3. Commit and Deploy

```bash
git add argocd/applications/mgmt/services/myapp/sealed-secret.yaml
git commit -m "Add myapp secret (sealed)"
git push
```

ArgoCD syncs the SealedSecret, controller decrypts it to a plain Secret.

### 4. Verify

```bash
# Check SealedSecret
kubectl get sealedsecret my-secret -n myapp

# Check decrypted Secret
kubectl get secret my-secret -n myapp

# View value
kubectl get secret my-secret -n myapp -o jsonpath='{.data.password}' | base64 -d
```

## Common Patterns

### Docker Registry Credentials

```bash
kubectl create secret docker-registry regcred \
  --namespace=default \
  --docker-server=ghcr.io \
  --docker-username=your-username \
  --docker-password=your-token \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-apps.pem --format=yaml \
  > argocd/applications/apps/platform/regcred-sealed.yaml
```

### TLS Certificate

```bash
kubectl create secret tls myapp-tls \
  --namespace=myapp \
  --cert=/path/to/cert.pem \
  --key=/path/to/key.pem \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-apps.pem --format=yaml \
  > argocd/applications/apps/services/myapp/tls-sealed.yaml
```

### Database Connection String

```bash
kubectl create secret generic db-connection \
  --namespace=myapp \
  --from-literal=dsn="postgresql://user:pass@db:5432/mydb" \
  --dry-run=client -o yaml | \
kubeseal --cert=pub-cert-apps.pem --format=yaml \
  > argocd/applications/apps/services/myapp/db-sealed.yaml
```

## Updating Secrets

```bash
# 1. Create updated plain secret
kubectl create secret generic my-secret \
  --namespace=myapp \
  --from-literal=password=NewPassword456 \
  --dry-run=client -o yaml > /tmp/updated-secret.yaml

# 2. Re-seal
kubeseal --cert=pub-cert-mgmt.pem \
  < /tmp/updated-secret.yaml \
  > argocd/applications/mgmt/services/myapp/sealed-secret.yaml

# 3. Commit
git add argocd/applications/mgmt/services/myapp/sealed-secret.yaml
git commit -m "Update myapp secret"
git push

# 4. Restart pods to pick up new secret
kubectl rollout restart deployment myapp -n myapp
```

## Backup Sealing Key

**CRITICAL:** Backup your sealing key to restore cluster from scratch.

```bash
# Backup
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-backup.yaml

# Encrypt and store securely (1Password, S3, etc.)
gpg --encrypt --recipient your-email@example.com sealed-secrets-key-backup.yaml
```

### Restore Sealing Key

```bash
# Decrypt backup
gpg --decrypt sealed-secrets-key-backup.yaml.gpg > sealed-secrets-key-backup.yaml

# Apply to new cluster
kubectl apply -f sealed-secrets-key-backup.yaml

# Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets
```

## Security Best Practices

### .gitignore

```bash
# Never commit plain secrets
echo "*-plain.yaml" >> .gitignore
echo "*.pem" >> .gitignore
```

### Secret Scopes

- **Strict (default)**: Specific namespace + name only (most secure)
- **Namespace-wide**: Can rename, must stay in namespace
- **Cluster-wide**: Can move anywhere (least secure)

**Recommendation:** Use strict (default) for production.

### RBAC

Only users with kubectl access to the cluster can decrypt secrets. Use RBAC to limit secret access.

## Troubleshooting

### SealedSecret Not Decrypting

```bash
# Check controller logs
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller

# Common errors:
# - "no key could decrypt secret": Wrong cluster cert or key rotated
# - "failed to unseal": Controller not running

# Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets
```

### Lost Sealing Key

**Solution:** This is why backups are critical! Without the key:
1. Generate new sealing key (automatic when sealed-secrets redeploys)
2. Re-seal ALL secrets with new key
3. Commit and push

## Summary

**Workflow:**
1. Create plain secret locally → 2. Seal with `kubeseal` → 3. Commit to Git → 4. ArgoCD syncs → 5. Controller decrypts

**Key Points:**
- ✅ SealedSecrets safe for Git
- ✅ Per-cluster encryption keys
- ⚠️ Backup sealing keys before cluster rebuild
- ⚠️ See [rotate-sealed-secrets.md](runbooks/rotate-sealed-secrets.md) for key rotation
