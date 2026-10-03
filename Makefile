.PHONY: help test lint docker-build docker-run terraform-fmt terraform-validate \
        terraform-plan infra-up infra-down verify logs clean

CLUSTER_NAME ?= cloudlaunch-dev
AWS_REGION   ?= us-east-1
ECR_REPO     ?= cloudlaunch-api
IMAGE_TAG    ?= local

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# ─── Application ──────────────────────────────────────────────────────────────

test: ## Run application unit tests
	cd app && pip install -q -r requirements.txt -r requirements-dev.txt && \
	pytest tests/ -v --cov=src --cov-report=term-missing

lint: ## Lint Python source code
	cd app && flake8 src/ tests/ --max-line-length=120

docker-build: ## Build Docker image locally
	docker build -t $(ECR_REPO):$(IMAGE_TAG) app/

docker-run: ## Run the Docker container locally
	docker run --rm -p 8080:8080 \
	  -e APP_VERSION=$(IMAGE_TAG) \
	  $(ECR_REPO):$(IMAGE_TAG)

docker-scan: ## Scan Docker image with Trivy
	trivy image $(ECR_REPO):$(IMAGE_TAG)

# ─── Terraform ────────────────────────────────────────────────────────────────

terraform-fmt: ## Format Terraform code
	terraform fmt -recursive terraform/

terraform-validate: ## Validate Terraform configuration
	cd terraform/environments/dev && terraform init -backend=false && terraform validate

terraform-plan: ## Plan Terraform changes (requires AWS credentials)
	cd terraform/environments/dev && terraform init && terraform plan

infra-up: ## Deploy AWS infrastructure (requires AWS credentials)
	cd terraform/environments/dev && terraform init && terraform apply -auto-approve

infra-down: ## Destroy AWS infrastructure (WARNING: deletes everything)
	bash scripts/cleanup.sh

# ─── Kubernetes ───────────────────────────────────────────────────────────────

k8s-validate: ## Validate Kubernetes manifests with kubeconform
	kubeconform -strict -ignore-missing-schemas gitops/base/*.yaml

kubeconfig: ## Update kubeconfig for the EKS cluster
	aws eks update-kubeconfig --region $(AWS_REGION) --name $(CLUSTER_NAME)

# ─── Verification ─────────────────────────────────────────────────────────────

verify-infra: ## Verify AWS infrastructure health
	bash scripts/verify-infra.sh

verify-app: ## Verify application health in Kubernetes
	bash scripts/verify-app.sh

verify-gitops: ## Verify Argo CD GitOps state
	bash scripts/verify-gitops.sh

verify: verify-infra verify-app verify-gitops ## Run all verification checks

# ─── Observability ────────────────────────────────────────────────────────────

logs: ## Tail application logs
	kubectl logs -n cloudlaunch -l app=cloudlaunch-api -f --tail=100

grafana: ## Port-forward Grafana to localhost:3000
	kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

prometheus: ## Port-forward Prometheus to localhost:9090
	kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090

argocd: ## Port-forward Argo CD to localhost:8080
	kubectl port-forward svc/argocd-server -n argocd 8080:443

# ─── GitOps ───────────────────────────────────────────────────────────────────

rollback: ## Rollback to a previous version (usage: make rollback TAG=1.0.0)
	bash scripts/rollback.sh $(TAG)

# ─── Maintenance ──────────────────────────────────────────────────────────────

clean: ## Remove local build artifacts
	find . -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
	find . -name '*.pyc' -delete 2>/dev/null || true
	find . -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
	find . -name 'coverage.xml' -delete 2>/dev/null || true
