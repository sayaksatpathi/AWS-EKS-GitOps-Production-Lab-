# Deployment Guide

## Prerequisites

| Tool | Minimum Version | Install |
|------|----------------|---------|
| AWS CLI | 2.x | `brew install awscli` |
| Terraform | 1.6+ | `brew install terraform` |
| kubectl | 1.28+ | `brew install kubectl` |
| Helm | 3.x | `brew install helm` |
| Docker | 24+ | Docker Desktop |
| Git | 2.x | System package |

## Initial Setup

### 1. Configure AWS credentials

```bash
aws configure
# Enter: AWS Access Key ID, Secret, Region (us-east-1), output format (json)
```

### 2. Clone repository

```bash
git clone https://github.com/sayaksatpathi/AWS-EKS-GitOps-Production-Lab-
cd AWS-EKS-GitOps-Production-Lab-
```

### 3. Deploy Infrastructure with Terraform

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform fmt
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Key outputs to save:
```bash
terraform output eks_cluster_name
terraform output ecr_repository_url
terraform output github_actions_role_arn
```

### 4. Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name cloudlaunch-dev
kubectl get nodes
```

### 5. Install AWS Load Balancer Controller

```bash
# Install cert-manager first
kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

# Add EKS helm repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get ALB controller role ARN from Terraform output
ALB_ROLE_ARN=$(cd terraform/environments/dev && terraform output -raw alb_controller_role_arn)

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cloudlaunch-dev \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller
```

### 6. Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server

# Access Argo CD UI (port-forward)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### 7. Register the Argo CD Project and Application

```bash
kubectl apply -f gitops/argocd/project.yaml
kubectl apply -f gitops/argocd/application.yaml
```

### 8. Install Observability Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring

# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

# Install Loki + Promtail
helm install loki grafana/loki-stack \
  -n monitoring \
  --set loki.enabled=true \
  --set promtail.enabled=true

# Apply PrometheusRule alerts
kubectl apply -f monitoring/alerts/cloudlaunch-alerts.yaml
```

### 9. Configure GitHub Actions Secrets

In your GitHub repository Settings → Secrets and variables → Actions:

```
AWS_ROLE_ARN = <output from: terraform output github_actions_role_arn>
```

The repository already has the ECR repository name and region hardcoded in
`.github/workflows/docker.yml`. Only the role ARN is secret.

### 10. Build and Push First Image

Trigger the Docker workflow:
```bash
git tag v1.0.0
git push origin v1.0.0
```

Or push to main branch to trigger the workflow automatically.

### 11. Verify

```bash
# Verify infrastructure
bash scripts/verify-infra.sh

# Wait for Argo CD to sync
kubectl -n argocd get application cloudlaunch-api -w

# Verify application
bash scripts/verify-app.sh

# Verify GitOps
bash scripts/verify-gitops.sh

# Get ALB endpoint
kubectl get ingress -n cloudlaunch cloudlaunch-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
