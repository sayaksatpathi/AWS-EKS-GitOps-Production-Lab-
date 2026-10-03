#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# verify-infra.sh — Verify AWS infrastructure health
# ─────────────────────────────────────────────────────────────────────────────

CLUSTER_NAME="${CLUSTER_NAME:-cloudlaunch-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PASS=0
FAIL=0

green()  { echo -e "\033[0;32m✔ $*\033[0m"; }
red()    { echo -e "\033[0;31m✗ $*\033[0m"; }
yellow() { echo -e "\033[0;33m⚠ $*\033[0m"; }
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

header "AWS Connectivity"
check "AWS CLI configured" aws sts get-caller-identity
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
green "Account ID: $ACCOUNT_ID"

header "EKS Cluster"
check "EKS cluster exists" aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION"

CLUSTER_STATUS=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.status' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
  green "Cluster status: ACTIVE"
  ((PASS++)) || true
else
  red "Cluster status: $CLUSTER_STATUS (expected ACTIVE)"
  ((FAIL++)) || true
fi

header "ECR Repository"
check "ECR repository exists" aws ecr describe-repositories \
  --repository-names "cloudlaunch-api" \
  --region "$AWS_REGION"

IMAGE_COUNT=$(aws ecr list-images \
  --repository-name "cloudlaunch-api" \
  --region "$AWS_REGION" \
  --query 'length(imageIds)' \
  --output text 2>/dev/null || echo "0")
green "ECR image count: $IMAGE_COUNT"

header "VPC Resources"
VPC_ID=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text 2>/dev/null || echo "")

if [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]]; then
  green "VPC ID: $VPC_ID"
  ((PASS++)) || true
else
  red "Could not determine VPC ID"
  ((FAIL++)) || true
fi

header "Summary"
echo "Passed: $PASS  |  Failed: $FAIL"
[[ $FAIL -eq 0 ]] && green "All infrastructure checks passed!" || red "Some infrastructure checks failed!"
exit $FAIL
