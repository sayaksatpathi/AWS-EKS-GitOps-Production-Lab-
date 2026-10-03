#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# verify-gitops.sh — Verify Argo CD GitOps state
# ─────────────────────────────────────────────────────────────────────────────

APP_NAME="${APP_NAME:-cloudlaunch-api}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
PASS=0
FAIL=0

green()  { echo -e "\033[0;32m✔ $*\033[0m"; }
red()    { echo -e "\033[0;31m✗ $*\033[0m"; }
yellow() { echo -e "\033[0;33m⚠ $*\033[0m"; }
header() { echo -e "\n\033[1;34m═══ $* ═══\033[0m"; }

header "Argo CD Namespace"
if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
  green "Namespace $ARGOCD_NAMESPACE exists"
  ((PASS++)) || true
else
  red "Namespace $ARGOCD_NAMESPACE missing — Argo CD not installed"
  ((FAIL++)) || true
  exit 1
fi

header "Argo CD Pods"
ARGOCD_PODS=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --field-selector=status.phase=Running \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w || echo 0)
if [[ "$ARGOCD_PODS" -ge 3 ]]; then
  green "Argo CD running pods: $ARGOCD_PODS"
  ((PASS++)) || true
else
  red "Argo CD running pods: $ARGOCD_PODS (expected >= 3)"
  ((FAIL++)) || true
fi

header "Argo CD Application"
APP_STATUS=$(kubectl get application "$APP_NAME" \
  -n "$ARGOCD_NAMESPACE" \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NotFound")
HEALTH_STATUS=$(kubectl get application "$APP_NAME" \
  -n "$ARGOCD_NAMESPACE" \
  -o jsonpath='{.status.health.status}' 2>/dev/null || echo "NotFound")

if [[ "$APP_STATUS" == "Synced" ]]; then
  green "Sync status: Synced"
  ((PASS++)) || true
else
  red "Sync status: $APP_STATUS (expected Synced)"
  ((FAIL++)) || true
fi

if [[ "$HEALTH_STATUS" == "Healthy" ]]; then
  green "Health status: Healthy"
  ((PASS++)) || true
else
  red "Health status: $HEALTH_STATUS (expected Healthy)"
  ((FAIL++)) || true
fi

header "Current Image Tag"
CURRENT_IMAGE=$(kubectl get deployment cloudlaunch-api \
  -n cloudlaunch \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
green "Current image: $CURRENT_IMAGE"

header "Summary"
echo "Passed: $PASS  |  Failed: $FAIL"
[[ $FAIL -eq 0 ]] && green "GitOps checks passed!" || red "Some GitOps checks failed!"
exit $FAIL
