#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# rollback.sh — Rollback to a previous image tag via GitOps
# ─────────────────────────────────────────────────────────────────────────────

TARGET_TAG="${1:-}"
KUSTOMIZATION="gitops/overlays/dev/kustomization.yaml"

if [[ -z "$TARGET_TAG" ]]; then
  echo "Usage: $0 <target-tag>"
  echo "Example: $0 1.0.0"
  exit 1
fi

echo "Rolling back to tag: $TARGET_TAG"

# Update the kustomization image tag
sed -i "s|newTag: .*|newTag: \"${TARGET_TAG}\"|" "$KUSTOMIZATION"

echo "Updated $KUSTOMIZATION to tag: $TARGET_TAG"
grep "newTag" "$KUSTOMIZATION"

echo ""
echo "Commit and push to trigger Argo CD reconciliation:"
echo "  git add $KUSTOMIZATION"
echo "  git commit -m 'chore(gitops): rollback to $TARGET_TAG'"
echo "  git push"
echo ""
echo "Then watch Argo CD sync:"
echo "  watch kubectl get pods -n cloudlaunch"
