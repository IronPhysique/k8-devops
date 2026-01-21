# AMP (Application Management Panel)

Game server management platform for the apps cluster.

## What is AMP?

AMP (by CubeCoders) is a web-based game server management panel that supports:
- Minecraft (Java & Bedrock)
- ARK: Survival Evolved
- Valheim
- Satisfactory
- And many more games

## Access

Once deployed, AMP will be accessible via LoadBalancer IP:

```bash
# Get AMP LoadBalancer IP
kubectl get svc amp -n amp -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Access web UI
echo "http://<LOADBALANCER_IP>:8080"
```

## Default Credentials

**⚠️ CHANGE THESE IMMEDIATELY AFTER FIRST LOGIN!**

- **Username:** `admin`
- **Password:** `CHANGEME_amp_admin_password`

Change in: `argocd/applications/apps/services/amp/manifests/base/deployment.yaml`

## Security Recommendations

1. **Change default password:**
   ```bash
   # Edit deployment
   vim argocd/applications/apps/services/amp/manifests/base/deployment.yaml

   # Update PASSWORD env var
   # Commit and push
   ```

2. **Use Sealed Secrets for credentials:**
   ```bash
   # Create secret
   kubectl create secret generic amp-credentials \
     --namespace=amp \
     --from-literal=username=youradmin \
     --from-literal=password=YourSecurePassword \
     --dry-run=client -o yaml | \
   kubeseal --cert=pub-cert-apps.pem --format=yaml \
     > argocd/applications/apps/services/amp/amp-credentials-sealed.yaml

   # Update deployment to use secret
   ```

## Creating Game Servers

1. Log in to AMP web UI
2. Click "Create Instance"
3. Select game type (Minecraft, ARK, etc.)
4. Configure server settings
5. AMP will download and configure the game server

## Port Configuration

- **8080:** AMP Web UI
- **8081:** AMP Core API
- **25565:** Default Minecraft server port (configurable)
- **25565-25575:** Game server port range

**Note:** You may need to add more port mappings in the Service definition depending on your games.

## Storage

AMP uses a 50Gi persistent volume at `/home/amp` for:
- AMP configuration
- Game server files
- World saves
- Mods/plugins

## Resource Limits

- **Requests:** 500m CPU, 2Gi RAM
- **Limits:** 4 CPU, 8Gi RAM

Adjust based on number/type of game servers in deployment.yaml.

## Troubleshooting

### Check pod status
```bash
kubectl get pods -n amp
kubectl logs -n amp deployment/amp
```

### Check service
```bash
kubectl get svc -n amp
```

### Access logs
```bash
kubectl logs -n amp -l app=amp -f
```

## References

- [AMP Documentation](https://github.com/CubeCoders/AMP)
- [Docker Image](https://hub.docker.com/r/mitchtalmadge/amp-dockerized)
