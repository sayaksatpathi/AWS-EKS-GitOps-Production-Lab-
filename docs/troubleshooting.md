# Troubleshooting

## Common Issues

### Pods stuck in Pending

```bash
kubectl describe pod -n cloudlaunch <pod-name>
```

Possible causes:
- Node not schedulable: `kubectl describe node <node>`
- Insufficient resources: check `kubectl top nodes`
- Image pull failure: check `events` for `ErrImagePull` or `ImagePullBackOff`

### Pods stuck in CrashLoopBackOff

```bash
kubectl logs -n cloudlaunch <pod-name> --previous
kubectl describe pod -n cloudlaunch <pod-name> | grep -A10 "State:"
```

Common causes:
- `FAIL_STARTUP=true` in ConfigMap
- OOM kill: `kubectl describe pod` shows `OOMKilled`
- Application startup error: check previous logs

### ALB not provisioned

```bash
kubectl describe ingress -n cloudlaunch cloudlaunch-api
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

Common causes:
- ALB controller not installed or not running
- IAM role not attached or wrong trust policy
- Subnet missing `kubernetes.io/role/elb` tags

### Argo CD application stuck in Degraded

```bash
kubectl get application cloudlaunch-api -n argocd -o yaml | grep -A20 "conditions:"
```

Common causes:
- Bad image tag (ECR image doesn't exist)
- FAIL_READY=true in ConfigMap
- Kubernetes resource validation failure

### ECR push failing in GitHub Actions

Check:
1. `AWS_ROLE_ARN` secret is set correctly
2. IAM trust policy includes the repository
3. ECR repository name matches `ECR_REPOSITORY` env var in workflow

### Prometheus not scraping application

```bash
kubectl get servicemonitor -n cloudlaunch
kubectl exec -n monitoring prometheus-... -- wget -qO- http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.namespace == "cloudlaunch")'
```

Ensure `release: prometheus` label is on the ServiceMonitor.

## Diagnostic Commands

```bash
# Cluster overview
kubectl get nodes -o wide
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Application health
kubectl get pods,svc,ingress -n cloudlaunch
kubectl rollout status deployment/cloudlaunch-api -n cloudlaunch

# Argo CD
kubectl get applications -n argocd
argocd app get cloudlaunch-api  # (if argocd CLI installed)

# Observability
kubectl get pods -n monitoring
kubectl get prometheusrule -n monitoring

# Recent events
kubectl get events -n cloudlaunch --sort-by='.lastTimestamp' | tail -20
```

## High Error Rate

1. Check pod logs: `kubectl logs -n cloudlaunch -l app=cloudlaunch-api --tail=50`
2. Check recent deployments: `kubectl rollout history deployment/cloudlaunch-api -n cloudlaunch`
3. Check Grafana error rate dashboard
4. If caused by bad deployment: [rollback](./failure-and-rollback.md)

## No Healthy Pods

1. Check pod status: `kubectl get pods -n cloudlaunch -w`
2. Check readiness probe: `kubectl describe pod -n cloudlaunch <pod> | grep -A10 Readiness`
3. If FAIL_READY=true in ConfigMap: update ConfigMap and rollout restart
   ```bash
   kubectl patch configmap cloudlaunch-config -n cloudlaunch \
     -p '{"data":{"FAIL_READY":"false"}}'
   kubectl rollout restart deployment/cloudlaunch-api -n cloudlaunch
   ```
4. Or rollback via GitOps: see [failure-and-rollback.md](./failure-and-rollback.md)
