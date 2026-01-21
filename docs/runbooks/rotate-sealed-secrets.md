# Rotate Sealed Secrets Encryption Key

This runbook covers rotating the Sealed Secrets controller encryption key for security compliance.

## When to Rotate

- Regular schedule (e.g., every 6-12 months)
- Suspected key compromise
- Employee/contractor offboarding
- Compliance requirements

## Important Notes

- Each cluster (mgmt, apps) has its own sealed-secrets key
- Rotating the key requires re-sealing ALL secrets
- Old SealedSecrets become unusable after rotation
- Plan for maintenance window

---

## Strategy

We'll use **key renewal** rather than replacement:
1. Generate new key alongside old key
2. Re-seal all secrets with new key
3. Commit to Git
4. Remove old key

This allows gradual migration without downtime.

---

## Step 1: Backup Current Key

**CRITICAL:** Always backup before rotation.

```bash
# For mgmt cluster
kubectl get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-mgmt-backup-$(date +%Y%m%d).yaml

# For apps cluster
kubectl --context=apps-cluster get secret -n sealed-secrets \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > sealed-secrets-key-apps-backup-$(date +%Y%m%d).yaml

# Encrypt and store backups securely
# Example: gpg encrypted to S3
gpg --encrypt --recipient your-key sealed-secrets-key-mgmt-backup-*.yaml
aws s3 cp sealed-secrets-key-mgmt-backup-*.yaml.gpg s3://your-backup-bucket/
```

---

## Step 2: Inventory All SealedSecrets

Find all SealedSecrets in your Git repo:

```bash
cd ~/homelab

# List all SealedSecrets
find . -name "*.yaml" -exec grep -l "kind: SealedSecret" {} \;

# Example output:
# ./clusters/mgmt/pihole-sealed-secret.yaml
# ./clusters/apps/app-secrets.yaml
# ./secrets/grafana-admin-password.yaml
```

Create a checklist of secrets to re-seal.

---

## Step 3: Generate New Key

```bash
# For mgmt cluster
kubectl --context=default -n sealed-secrets \
  create secret tls sealed-secrets-key-new-$(date +%Y%m%d) \
  --cert=/dev/null --key=/dev/null \
  --dry-run=client -o yaml | \
  kubectl --context=default apply -f -

# Label it as active (sealed-secrets will use newest key)
kubectl --context=default -n sealed-secrets label secret \
  sealed-secrets-key-new-$(date +%Y%m%d) \
  sealedsecrets.bitnami.com/sealed-secrets-key=active

# Restart controller to pick up new key
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets --context=default
```

Repeat for apps cluster:

```bash
kubectl --context=apps-cluster -n sealed-secrets \
  create secret tls sealed-secrets-key-new-$(date +%Y%m%d) \
  --cert=/dev/null --key=/dev/null \
  --dry-run=client -o yaml | \
  kubectl --context=apps-cluster apply -f -

kubectl --context=apps-cluster -n sealed-secrets label secret \
  sealed-secrets-key-new-$(date +%Y%m%d) \
  sealedsecrets.bitnami.com/sealed-secrets-key=active

kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets --context=apps-cluster
```

---

## Step 4: Fetch New Public Certificates

```bash
# For mgmt cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  --context=default \
  > pub-cert-mgmt-new.pem

# For apps cluster
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  --context=apps-cluster \
  > pub-cert-apps-new.pem
```

---

## Step 5: Re-seal All Secrets

For each secret identified in Step 2:

### Example: Pi-hole Admin Password (mgmt cluster)

```bash
# Create plain secret
kubectl create secret generic pihole-admin \
  --from-literal=password=YourNewSecurePassword \
  --dry-run=client -o yaml > pihole-admin-plain.yaml

# Seal with NEW certificate
kubeseal --cert=pub-cert-mgmt-new.pem \
  -o yaml < pihole-admin-plain.yaml \
  > clusters/mgmt/pihole-admin-sealed.yaml

# Clean up plain secret
rm pihole-admin-plain.yaml
```

### Example: Grafana Password (mgmt cluster)

```bash
kubectl create secret generic grafana-admin \
  --from-literal=admin-password=YourNewGrafanaPassword \
  --dry-run=client -o yaml > grafana-admin-plain.yaml

kubeseal --cert=pub-cert-mgmt-new.pem \
  -o yaml < grafana-admin-plain.yaml \
  > clusters/mgmt/grafana-admin-sealed.yaml

rm grafana-admin-plain.yaml
```

Repeat for all secrets in both clusters.

---

## Step 6: Update Git Repository

```bash
cd ~/homelab

# Review changes
git status
git diff

# Commit re-sealed secrets
git add .
git commit -m "Rotate sealed-secrets keys - $(date +%Y-%m-%d)"
git push origin main
```

---

## Step 7: Trigger Argo CD Sync

```bash
# Force sync all applications
argocd app sync --context=default -l cluster=mgmt
argocd app sync --context=default -l cluster=apps

# Or manually in UI:
# http://argocd.mgmt.local → Sync All
```

---

## Step 8: Verify New Secrets Work

```bash
# Check SealedSecret resources
kubectl get sealedsecrets -A --context=default
kubectl get sealedsecrets -A --context=apps-cluster

# Check decrypted secrets exist
kubectl get secrets -n pihole --context=default
kubectl get secrets -n monitoring --context=apps-cluster

# Test services using secrets
kubectl get pods -n pihole --context=default  # Should be Running
kubectl get pods -n monitoring --context=default  # Should be Running
```

---

## Step 9: Remove Old Keys (After Validation)

**Wait 7 days** to ensure everything works, then remove old keys:

```bash
# List all sealed-secrets keys
kubectl get secrets -n sealed-secrets --context=default | grep sealed-secrets-key

# Delete old keys (keep only newest)
kubectl delete secret sealed-secrets-key-old-20240101 -n sealed-secrets --context=default

# Repeat for apps cluster
kubectl get secrets -n sealed-secrets --context=apps-cluster | grep sealed-secrets-key
kubectl delete secret sealed-secrets-key-old-20240101 -n sealed-secrets --context=apps-cluster
```

---

## Step 10: Cleanup

```bash
# Remove public cert files (don't commit these)
rm pub-cert-mgmt-new.pem
rm pub-cert-apps-new.pem

# Securely delete backup files if no longer needed
# (Keep encrypted backups in S3/vault)
shred -u sealed-secrets-key-*-backup-*.yaml
```

---

## Automation (Advanced)

Script to rotate keys quarterly:

```bash
#!/bin/bash
# rotate-sealed-secrets.sh

set -euo pipefail

CLUSTER_CONTEXT="${1:-default}"
NAMESPACE="sealed-secrets"

echo "Rotating sealed-secrets key for context: $CLUSTER_CONTEXT"

# Backup
kubectl --context=$CLUSTER_CONTEXT get secret -n $NAMESPACE \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > backup-$(date +%Y%m%d)-$CLUSTER_CONTEXT.yaml

# Generate new key
kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE \
  create secret tls sealed-secrets-key-$(date +%Y%m%d) \
  --cert=/dev/null --key=/dev/null \
  --dry-run=client -o yaml | kubectl --context=$CLUSTER_CONTEXT apply -f -

# Label new key
kubectl --context=$CLUSTER_CONTEXT -n $NAMESPACE label secret \
  sealed-secrets-key-$(date +%Y%m%d) \
  sealedsecrets.bitnami.com/sealed-secrets-key=active

# Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n $NAMESPACE --context=$CLUSTER_CONTEXT

echo "Key rotated. Fetch new cert with: kubeseal --fetch-cert --context=$CLUSTER_CONTEXT"
```

---

## Rollback Procedure

If something breaks after rotation:

```bash
# 1. Restore old key from backup
kubectl apply -f sealed-secrets-key-mgmt-backup-20240101.yaml

# 2. Restart controller
kubectl rollout restart deployment sealed-secrets-controller -n sealed-secrets

# 3. Revert Git changes
git revert HEAD
git push origin main

# 4. Sync Argo CD
argocd app sync --context=default -l cluster=mgmt
```

---

## Best Practices

1. **Test in non-prod first**: If you have a dev cluster, test rotation there
2. **Rotate during maintenance window**: Plan for potential downtime
3. **Keep backups encrypted**: Store in multiple locations (S3, vault, offline)
4. **Document passwords**: Use password manager for new secret values
5. **Rotate regularly**: Set calendar reminder for quarterly rotation
6. **Audit access**: Review who has access to sealed-secrets keys

---

## Troubleshooting

### SealedSecret fails to decrypt after rotation

```bash
# Check controller logs
kubectl logs -n sealed-secrets deployment/sealed-secrets-controller

# Common issue: old SealedSecret still in Git
# Solution: Re-seal with new cert
```

### New key not being used

```bash
# Check key labels
kubectl get secrets -n sealed-secrets --show-labels

# Ensure newest key has label:
# sealedsecrets.bitnami.com/sealed-secrets-key=active
```

### Lost backup key

If you lose the backup and need to decrypt old SealedSecrets:
- Old SealedSecrets are **unrecoverable** without the key
- You must create new plain secrets and re-seal them
- This is why backups are critical

---

## Summary

Key rotation workflow:
1. ✅ Backup current key
2. ✅ Generate new key
3. ✅ Fetch new public cert
4. ✅ Re-seal all secrets
5. ✅ Commit to Git
6. ✅ Sync Argo CD
7. ✅ Verify
8. ✅ Remove old key (after 7 days)

**Frequency:** Quarterly or as required by security policy.

**Time:** 1-2 hours for manual rotation (depends on number of secrets).
