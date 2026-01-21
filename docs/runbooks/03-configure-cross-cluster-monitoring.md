# Phase 3: Configure Cross-Cluster Monitoring

After both clusters are bootstrapped and platform components are synced, configure Grafana to query apps cluster Prometheus.

## Architecture

```
┌─────────────────────────────────────┐
│  mgmt cluster (Pi 5)                │
│  ┌──────────┐         ┌───────────┐ │
│  │ Grafana  │────────>│Prometheus │ │
│  │          │  local  │   (mgmt)  │ │
│  └────┬─────┘         └───────────┘ │
│       │                              │
│       │ HTTP query                   │
└───────┼──────────────────────────────┘
        │
        │ LAN (192.168.1.x)
        │
┌───────▼──────────────────────────────┐
│  apps cluster (PC)                   │
│  ┌───────────┐      ┌──────────────┐ │
│  │  Traefik  │─────>│ Prometheus   │ │
│  │ Ingress   │      │   (apps)     │ │
│  └───────────┘      └──────────────┘ │
│  Exposed on LAN via IngressRoute     │
└──────────────────────────────────────┘
```

## Step 1: Expose Apps Prometheus

Apps Prometheus is already exposed via Traefik IngressRoute (deployed by GitOps).

Verify:

```bash
# Check IngressRoute exists
kubectl --context=apps-cluster get ingressroute prometheus-external -n monitoring

# Get Traefik LoadBalancer IP
APPS_LB_IP=$(kubectl --context=apps-cluster get svc traefik -n traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Apps Traefik IP: $APPS_LB_IP"

# Test Prometheus API
curl -s http://${APPS_LB_IP}:80/api/v1/status/config | jq .status
```

If you don't have a LoadBalancer (MetalLB/k3s servicelb), use NodePort:

```bash
# Use node IP + port
APPS_IP="192.168.1.20"
APPS_PROM_PORT=$(kubectl --context=apps-cluster get svc kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.spec.ports[0].nodePort}')
curl -s http://${APPS_IP}:${APPS_PROM_PORT}/api/v1/status/config | jq .status
```

## Step 2: Create Grafana Datasource for Apps Prometheus

### Option A: Direct IP (Simplest)

```bash
# Update datasource ConfigMap
kubectl --context=default apply -f - << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasource-apps
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  apps-prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus-apps
        type: prometheus
        access: proxy
        url: http://192.168.1.20:9090  # UPDATE with your apps cluster IP
        isDefault: false
        editable: true
        jsonData:
          timeInterval: 30s
          httpMethod: POST
EOF

# Restart Grafana to pick up new datasource
kubectl --context=default rollout restart deployment kube-prometheus-stack-grafana -n monitoring
```

### Option B: Service Name (Requires DNS)

If you have split-horizon DNS or mDNS:

```yaml
url: http://prometheus-apps.monitoring.svc.cluster.local:9090
```

### Option C: Traefik Ingress (Production)

```yaml
url: http://prometheus-apps.local  # Requires /etc/hosts or DNS entry
```

## Step 3: Verify in Grafana

1. Port-forward Grafana:
   ```bash
   kubectl --context=default port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   ```

2. Open browser: http://localhost:3000
   - Username: `admin`
   - Password: From values file or get from secret:
     ```bash
     kubectl --context=default get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d
     ```

3. Navigate to **Configuration → Data Sources**

4. You should see:
   - ✅ Prometheus-mgmt (default)
   - ✅ Prometheus-apps

5. Click **Prometheus-apps** → **Test** → Should show "Data source is working"

## Step 4: Import Multi-Cluster Dashboards

```bash
# Import Kubernetes cluster monitoring dashboard
kubectl --context=default apply -f - << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: multi-cluster-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  multi-cluster.json: |
    {
      "dashboard": {
        "title": "Multi-Cluster Overview",
        "panels": [
          {
            "datasource": "Prometheus-mgmt",
            "targets": [
              {
                "expr": "up{cluster=\"mgmt\"}",
                "legendFormat": "mgmt - {{job}}"
              }
            ]
          },
          {
            "datasource": "Prometheus-apps",
            "targets": [
              {
                "expr": "up{cluster=\"apps\"}",
                "legendFormat": "apps - {{job}}"
              }
            ]
          }
        ]
      }
    }
EOF
```

Grafana sidecar will auto-load this dashboard.

## Step 5: Validation

Run these queries in Grafana Explore:

### Query mgmt cluster (Prometheus-mgmt):
```promql
up{cluster="mgmt"}
node_memory_MemAvailable_bytes{cluster="mgmt"}
```

### Query apps cluster (Prometheus-apps):
```promql
up{cluster="apps"}
node_memory_MemAvailable_bytes{cluster="apps"}
```

### Cross-cluster query (using federation):
Not supported directly; use separate queries per datasource.

## Troubleshooting

### Datasource test fails

```bash
# Check connectivity from mgmt to apps
kubectl --context=default run curl-test --rm -it --image=curlimages/curl -- \
  curl -v http://192.168.1.20:9090/api/v1/status/config

# Check Prometheus is accessible
kubectl --context=apps-cluster get svc -n monitoring
```

### Grafana doesn't pick up new datasource

```bash
# Force restart
kubectl --context=default delete pod -l app.kubernetes.io/name=grafana -n monitoring
```

### "Unauthorized" error

If using authentication (recommended for production), create a bearer token:

```bash
# In apps cluster
kubectl --context=apps-cluster get secret grafana-prometheus-token -n monitoring -o jsonpath='{.data.token}' | base64 -d

# Add to datasource:
# jsonData:
#   httpHeaderName1: "Authorization"
# secureJsonData:
#   httpHeaderValue1: "Bearer <TOKEN>"
```

---

**Next:** Deploy applications or configure Pi-hole
