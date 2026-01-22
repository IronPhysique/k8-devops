# Sealed Secrets Quick Guide

Sealed Secrets allows you to store encrypted secrets in Git safely.

## Creating a Sealed Secret

```bash
# Install kubeseal CLI
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.4/kubeseal-0.27.4-linux-amd64.tar.gz
tar -xvzf kubeseal-0.27.4-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal

# Create a normal secret
kubectl create secret generic my-secret \
  --from-literal=username=admin \
  --from-literal=password=changeme \
  --dry-run=client -o yaml > secret.yaml

# Seal it (for mgmt cluster)
kubeseal --format=yaml < secret.yaml > sealed-secret.yaml

# For apps cluster, use the apps cluster context
kubeseal --format=yaml --context=apps-cluster < secret.yaml > sealed-secret-apps.yaml

# Commit the sealed secret to Git
git add sealed-secret.yaml
git commit -m "Add sealed secret"
git push
```

## Using Sealed Secrets

The sealed-secrets controller automatically decrypts SealedSecret resources into regular Secrets.

```yaml
# This goes in Git (safe to commit)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
  namespace: default
spec:
  encryptedData:
    username: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
    password: AgBy8i6OSWS+PiTySYZZA9rO43cGDEq...

# The controller creates this automatically (never commit)
apiVersion: v1
kind: Secret
metadata:
  name: my-secret
  namespace: default
data:
  username: YWRtaW4=
  password: Y2hhbmdlbWU=
```

## Key Rotation

To rotate the encryption key:

```bash
# 1. Backup current key
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > backup-$(date +%Y%m%d).yaml

# 2. Generate new key
kubectl -n sealed-secrets create secret tls sealed-secrets-key-$(date +%Y%m%d) \
  --cert=/dev/null --key=/dev/null --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets

# 4. Re-seal all secrets with new key
# Use kubeseal to re-encrypt all your secrets

# 5. Remove old key after verifying all secrets work
kubectl delete secret -n sealed-secrets <old-key-name>
```

## Troubleshooting

**Secret not decrypting:**
```bash
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller
```

**Wrong cluster:**
Each cluster has its own key. Make sure you're using the correct context with kubeseal.
