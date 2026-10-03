#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# cleanup.sh — Tear down all AWS infrastructure
# ─────────────────────────────────────────────────────────────────────────────

CLUSTER_NAME="${CLUSTER_NAME:-cloudlaunch-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
TF_DIR="terraform/environments/dev"

red()    { echo -e "\033[0;31m$*\033[0m"; }
yellow() { echo -e "\033[0;33m$*\033[0m"; }
green()  { echo -e "\033[0;32m$*\033[0m"; }

yellow "⚠  WARNING: This will DELETE all AWS resources for CloudLaunch."
yellow "⚠  This includes: EKS cluster, VPC, ECR, IAM roles, and NAT Gateway."
echo ""
read -rp "Type 'yes' to confirm: " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  red "Aborted."
  exit 1
fi

echo ""
echo "Step 1: Remove Kubernetes resources managed by controllers (before EKS deletion)"

if kubectl cluster-info &>/dev/null 2>&1; then
  echo "Removing Ingress resources (triggers ALB deletion)..."
  kubectl delete ingress --all -n cloudlaunch --ignore-not-found=true || true

  echo "Removing services with LoadBalancer type..."
  kubectl delete service --all -n cloudlaunch --ignore-not-found=true || true

  echo "Waiting 30s for AWS resources to be removed..."
  sleep 30
fi

echo ""
echo "Step 2: Terraform destroy"
cd "$TF_DIR"
terraform init
terraform destroy -auto-approve

echo ""
green "✔ Cleanup complete. All CloudLaunch AWS resources have been deleted."
echo ""
echo "Note: Check your AWS console to confirm no resources remain."
echo "Resources that may still exist (check manually):"
echo "  - CloudWatch Log Groups (aws/eks/${CLUSTER_NAME}/*)"
echo "  - S3 bucket for Terraform state (if configured)"
echo "  - ECR images (deleted with repository)"
