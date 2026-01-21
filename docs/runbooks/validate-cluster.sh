#!/bin/bash
set -euo pipefail

################################################################################
# Cluster Validation Script
#
# Usage:
#   ./validate-cluster.sh mgmt
#   ./validate-cluster.sh apps
################################################################################

CLUSTER="${1:-}"
CONTEXT=""

if [[ "$CLUSTER" == "mgmt" ]]; then
  CONTEXT="default"
elif [[ "$CLUSTER" == "apps" ]]; then
  CONTEXT="apps-cluster"
else
  echo "Usage: $0 {mgmt|apps}"
  exit 1
fi

echo "=========================================="
echo "Validating $CLUSTER cluster (context: $CONTEXT)"
echo "=========================================="
echo ""

FAILED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  echo -e "${RED}✗${NC} $1"
  FAILED=$((FAILED + 1))
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

info() {
  echo "ℹ $1"
}

################################################################################
# 1. Cluster Connectivity
################################################################################

echo "[1/10] Cluster Connectivity"

if kubectl cluster-info --context="$CONTEXT" &>/dev/null; then
  pass "Cluster API accessible"
else
  fail "Cannot reach cluster API"
  exit 1
fi

################################################################################
# 2. Node Health
################################################################################

echo ""
echo "[2/10] Node Health"

NODES=$(kubectl get nodes --context="$CONTEXT" --no-headers 2>/dev/null | wc -l)
READY_NODES=$(kubectl get nodes --context="$CONTEXT" --no-headers 2>/dev/null | grep -c " Ready " || true)

if [[ $NODES -eq $READY_NODES ]] && [[ $NODES -gt 0 ]]; then
  pass "All $NODES node(s) Ready"
else
  fail "Node health issue: $READY_NODES/$NODES Ready"
fi

# Check node labels
if kubectl get nodes --context="$CONTEXT" -o jsonpath='{.items[*].metadata.labels.homelab/cluster}' | grep -q "$CLUSTER"; then
  pass "Node labels correct (homelab/cluster=$CLUSTER)"
else
  warn "Node labels may be missing or incorrect"
fi

################################################################################
# 3. System Pods
################################################################################

echo ""
echo "[3/10] System Pods"

# kube-system namespace
NOT_RUNNING=$(kubectl get pods -n kube-system --context="$CONTEXT" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
if [[ $NOT_RUNNING -eq 0 ]]; then
  pass "All kube-system pods Running"
else
  fail "$NOT_RUNNING pod(s) in kube-system not Running"
  kubectl get pods -n kube-system --context="$CONTEXT" --field-selector=status.phase!=Running
fi

################################################################################
# 4. Argo CD (mgmt cluster only)
################################################################################

if [[ "$CLUSTER" == "mgmt" ]]; then
  echo ""
  echo "[4/10] Argo CD (mgmt cluster only)"

  ARGOCD_READY=$(kubectl get pods -n argocd --context="$CONTEXT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
  if [[ $ARGOCD_READY -ge 7 ]]; then
    pass "Argo CD pods Running ($ARGOCD_READY)"
  else
    fail "Argo CD not fully ready ($ARGOCD_READY pods)"
  fi

  # Check Applications
  TOTAL_APPS=$(kubectl get applications -n argocd --context="$CONTEXT" --no-headers 2>/dev/null | wc -l)
  SYNCED_APPS=$(kubectl get applications -n argocd --context="$CONTEXT" -o jsonpath='{.items[*].status.sync.status}' 2>/dev/null | grep -o "Synced" | wc -l)
  HEALTHY_APPS=$(kubectl get applications -n argocd --context="$CONTEXT" -o jsonpath='{.items[*].status.health.status}' 2>/dev/null | grep -o "Healthy" | wc -l)

  if [[ $SYNCED_APPS -eq $TOTAL_APPS ]]; then
    pass "All $TOTAL_APPS applications Synced"
  else
    warn "$SYNCED_APPS/$TOTAL_APPS applications Synced"
    kubectl get applications -n argocd --context="$CONTEXT" | grep -v Synced | tail -n +2
  fi

  if [[ $HEALTHY_APPS -eq $TOTAL_APPS ]]; then
    pass "All $TOTAL_APPS applications Healthy"
  else
    warn "$HEALTHY_APPS/$TOTAL_APPS applications Healthy"
    kubectl get applications -n argocd --context="$CONTEXT" -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status | grep -v Healthy | tail -n +2
  fi
else
  echo ""
  echo "[4/10] Argo CD (skipped - apps cluster)"
fi

################################################################################
# 5. Sealed Secrets
################################################################################

echo ""
echo "[5/10] Sealed Secrets"

SEALED_READY=$(kubectl get pods -n sealed-secrets --context="$CONTEXT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ $SEALED_READY -ge 1 ]]; then
  pass "Sealed Secrets controller Running"
else
  fail "Sealed Secrets controller not Running"
fi

# Check for sealing key
SEALING_KEYS=$(kubectl get secrets -n sealed-secrets --context="$CONTEXT" -l sealedsecrets.bitnami.com/sealed-secrets-key=active --no-headers 2>/dev/null | wc -l)
if [[ $SEALING_KEYS -ge 1 ]]; then
  pass "Sealing key exists ($SEALING_KEYS)"
else
  fail "No sealing key found"
fi

################################################################################
# 6. cert-manager
################################################################################

echo ""
echo "[6/10] cert-manager"

CERTMGR_READY=$(kubectl get pods -n cert-manager --context="$CONTEXT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ $CERTMGR_READY -ge 3 ]]; then
  pass "cert-manager pods Running ($CERTMGR_READY)"
else
  fail "cert-manager not fully ready ($CERTMGR_READY pods)"
fi

# Check ClusterIssuer
if kubectl get clusterissuer selfsigned-issuer --context="$CONTEXT" &>/dev/null; then
  pass "ClusterIssuer selfsigned-issuer exists"
else
  warn "ClusterIssuer selfsigned-issuer not found"
fi

################################################################################
# 7. Monitoring (kube-prometheus-stack)
################################################################################

echo ""
echo "[7/10] Monitoring"

PROM_READY=$(kubectl get pods -n monitoring --context="$CONTEXT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ $PROM_READY -ge 5 ]]; then
  pass "Monitoring pods Running ($PROM_READY)"
else
  warn "Monitoring may not be fully ready ($PROM_READY pods)"
fi

# Check Prometheus
if kubectl get prometheus -n monitoring --context="$CONTEXT" &>/dev/null; then
  pass "Prometheus custom resource exists"
else
  fail "Prometheus custom resource not found"
fi

# Check ServiceMonitors
SM_COUNT=$(kubectl get servicemonitors -A --context="$CONTEXT" --no-headers 2>/dev/null | wc -l)
if [[ $SM_COUNT -gt 0 ]]; then
  pass "ServiceMonitors configured ($SM_COUNT)"
else
  warn "No ServiceMonitors found"
fi

# Check Grafana (mgmt cluster only)
if [[ "$CLUSTER" == "mgmt" ]]; then
  if kubectl get deployment kube-prometheus-stack-grafana -n monitoring --context="$CONTEXT" &>/dev/null; then
    pass "Grafana deployment exists"
  else
    fail "Grafana deployment not found"
  fi
fi

################################################################################
# 8. Traefik Ingress
################################################################################

echo ""
echo "[8/10] Traefik Ingress"

TRAEFIK_READY=$(kubectl get pods -n traefik --context="$CONTEXT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ $TRAEFIK_READY -ge 1 ]]; then
  pass "Traefik pods Running ($TRAEFIK_READY)"
else
  fail "Traefik not Running"
fi

# Check LoadBalancer service
LB_IP=$(kubectl get svc traefik -n traefik --context="$CONTEXT" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [[ -n "$LB_IP" ]]; then
  pass "Traefik LoadBalancer IP: $LB_IP"
else
  warn "Traefik LoadBalancer IP not assigned (may use NodePort)"
fi

################################################################################
# 9. DaemonSets
################################################################################

echo ""
echo "[9/10] DaemonSets"

# Node exporter
NODE_EXP_DESIRED=$(kubectl get daemonset prometheus-node-exporter -n monitoring --context="$CONTEXT" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
NODE_EXP_READY=$(kubectl get daemonset prometheus-node-exporter -n monitoring --context="$CONTEXT" -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")

if [[ "$NODE_EXP_DESIRED" -eq "$NODE_EXP_READY" ]] && [[ "$NODE_EXP_READY" -gt 0 ]]; then
  pass "Node exporter DaemonSet ready ($NODE_EXP_READY/$NODE_EXP_DESIRED)"
else
  warn "Node exporter not fully ready ($NODE_EXP_READY/$NODE_EXP_DESIRED)"
fi

# Promtail (if deployed)
if kubectl get daemonset promtail -n monitoring --context="$CONTEXT" &>/dev/null; then
  PROMTAIL_DESIRED=$(kubectl get daemonset promtail -n monitoring --context="$CONTEXT" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
  PROMTAIL_READY=$(kubectl get daemonset promtail -n monitoring --context="$CONTEXT" -o jsonpath='{.status.numberReady}' 2>/dev/null)
  if [[ "$PROMTAIL_DESIRED" -eq "$PROMTAIL_READY" ]]; then
    pass "Promtail DaemonSet ready ($PROMTAIL_READY/$PROMTAIL_DESIRED)"
  else
    warn "Promtail not fully ready ($PROMTAIL_READY/$PROMTAIL_DESIRED)"
  fi
fi

################################################################################
# 10. Cluster-Specific Checks
################################################################################

echo ""
echo "[10/10] Cluster-Specific Checks"

if [[ "$CLUSTER" == "mgmt" ]]; then
  # Pi-hole check
  if kubectl get namespace pihole --context="$CONTEXT" &>/dev/null; then
    PIHOLE_READY=$(kubectl get pods -n pihole --context="$CONTEXT" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ $PIHOLE_READY -ge 1 ]]; then
      pass "Pi-hole Running"
    else
      warn "Pi-hole not Running"
    fi
  else
    info "Pi-hole namespace not found (may not be deployed yet)"
  fi

  # Argo CD cluster registrations
  REGISTERED_CLUSTERS=$(kubectl get secrets -n argocd --context="$CONTEXT" -l argocd.argoproj.io/secret-type=cluster --no-headers 2>/dev/null | wc -l)
  if [[ $REGISTERED_CLUSTERS -ge 1 ]]; then
    pass "Apps cluster registered with Argo CD"
  else
    warn "No remote clusters registered (expected apps cluster)"
  fi

elif [[ "$CLUSTER" == "apps" ]]; then
  # Check for workload namespaces
  WORKLOAD_NS=$(kubectl get namespaces --context="$CONTEXT" --no-headers 2>/dev/null | grep -v -E "kube-|default|monitoring|cert-manager|sealed-secrets|traefik" | wc -l)
  if [[ $WORKLOAD_NS -gt 0 ]]; then
    pass "Workload namespaces exist ($WORKLOAD_NS)"
  else
    info "No workload namespaces yet (expected for fresh cluster)"
  fi
fi

################################################################################
# Summary
################################################################################

echo ""
echo "=========================================="
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}✓ Validation PASSED${NC}"
  echo "Cluster $CLUSTER is healthy"
else
  echo -e "${RED}✗ Validation FAILED${NC}"
  echo "$FAILED check(s) failed"
  exit 1
fi
echo "=========================================="
