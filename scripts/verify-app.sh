#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# verify-app.sh — Verify application health in Kubernetes
# ─────────────────────────────────────────────────────────────────────────────

NAMESPACE="${NAMESPACE:-cloudlaunch}"
DEPLOYMENT="${DEPLOYMENT:-cloudlaunch-api}"
PASS=0
FAIL=0

green()  { echo -e "\033[0;32m✔ $*\033[0m"; }
red()    { echo -e "\033[0;31m✗ $*\033[0m"; }
header() { echo -e "\n\033[1;34m═══ $* ═══\033[0m"; }

check() {
  local desc="$1"
  shift
  if "$@" &>/dev/null; then
    green "$desc"
    ((PASS++)) || true
  else
    red "$desc"
    ((FAIL++)) || true
  fi
}

header "Namespace"
check "Namespace exists" kubectl get namespace "$NAMESPACE"

header "Pods"
READY_PODS=$(kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
DESIRED_PODS=$(kubectl get deployment "$DEPLOYMENT" \
  -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [[ "$READY_PODS" -ge 1 ]]; then
  green "Pods ready: $READY_PODS/$DESIRED_PODS"
  ((PASS++)) || true
else
  red "Pods ready: $READY_PODS/$DESIRED_PODS"
  ((FAIL++)) || true
fi

kubectl get pods -n "$NAMESPACE" --selector="app=$DEPLOYMENT" 2>/dev/null || true

header "Service"
check "Service exists" kubectl get service "$DEPLOYMENT" -n "$NAMESPACE"

header "Application Health (port-forward test)"
POD=$(kubectl get pod -n "$NAMESPACE" \
  -l "app=$DEPLOYMENT" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$POD" ]]; then
  kubectl port-forward "pod/$POD" 18080:8080 -n "$NAMESPACE" &>/dev/null &
  PF_PID=$!
  sleep 3

  if curl -sf http://localhost:18080/health &>/dev/null; then
    green "/health endpoint returned 200"
    ((PASS++)) || true
  else
    red "/health endpoint failed"
    ((FAIL++)) || true
  fi

  if curl -sf http://localhost:18080/ready &>/dev/null; then
    green "/ready endpoint returned 200"
    ((PASS++)) || true
  else
    red "/ready endpoint failed (may be FAIL_READY=true scenario)"
    ((FAIL++)) || true
  fi

  if curl -sf http://localhost:18080/metrics | grep -q "cloudlaunch_http"; then
    green "/metrics endpoint returns prometheus data"
    ((PASS++)) || true
  else
    red "/metrics endpoint failed or missing cloudlaunch metrics"
    ((FAIL++)) || true
  fi

  kill $PF_PID 2>/dev/null || true
else
  red "No running pod found in namespace $NAMESPACE"
  ((FAIL++)) || true
fi

header "Summary"
echo "Passed: $PASS  |  Failed: $FAIL"
[[ $FAIL -eq 0 ]] && green "All application checks passed!" || red "Some application checks failed!"
exit $FAIL
