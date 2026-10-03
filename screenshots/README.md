# Screenshots

This directory contains evidence screenshots from the deployed system.

## Required Screenshots

Capture these after deploying the platform:

| Directory | Screenshot | Description |
|-----------|-----------|-------------|
| `github-actions/` | `ci-green.png` | All CI workflow jobs passing |
| `github-actions/` | `docker-push.png` | Docker build + ECR push workflow success |
| `ecr/` | `repository.png` | ECR repository with pushed images |
| `ecr/` | `scan-results.png` | Image vulnerability scan results |
| `eks/` | `cluster.png` | EKS cluster ACTIVE status |
| `eks/` | `nodes.png` | Worker nodes Ready |
| `eks/` | `pods.png` | cloudlaunch-api pods Running |
| `argocd/` | `synced-healthy.png` | Argo CD showing Synced + Healthy |
| `argocd/` | `app-tree.png` | Argo CD application resource tree |
| `grafana/` | `dashboard.png` | CloudLaunch API dashboard |
| `grafana/` | `metrics.png` | Request rate and latency graphs |
| `failure/` | `stuck-pods.png` | Pods at 0/1 READY during bad deploy |
| `failure/` | `argocd-degraded.png` | Argo CD showing Degraded health |
| `rollback/` | `git-revert.png` | Git commit reverting the failure |
| `rollback/` | `recovery.png` | Pods returning to 1/1 READY |

## Capture Instructions

```bash
# Get ALB endpoint
ALB=$(kubectl get ingress cloudlaunch-api -n cloudlaunch \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB"

# Test the application
curl http://$ALB/
curl http://$ALB/health
curl http://$ALB/ready
curl http://$ALB/metrics | head -20

# Port-forward Grafana for dashboard screenshots
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Port-forward Argo CD for UI screenshots  
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

**Note:** Screenshots in this directory are from the actual deployed system.
They are not generated or fabricated.
