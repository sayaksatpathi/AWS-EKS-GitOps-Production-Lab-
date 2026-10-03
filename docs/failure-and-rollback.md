# Failure Injection and Rollback Demonstration

## Overview

This document describes the controlled failure injection and rollback procedure
used to demonstrate real-world deployment failure handling with Argo CD GitOps.

## How the Failure Is Implemented

The application has two environment variables that control failure modes:

| Variable | Default | Effect |
|----------|---------|--------|
| `FAIL_READY` | `false` | When `true`, `/ready` returns HTTP 503 |
| `FAIL_STARTUP` | `false` | When `true`, the app raises RuntimeError on startup |

Setting `FAIL_READY=true` simulates the common case where a new version
passes CI but fails readiness checks in production — its pods never become
ready, the service stops routing traffic to them, and the rolling update stalls.

## Step-by-Step Failure and Rollback Sequence

### Phase 1: Healthy Baseline (v1.0.0)

```bash
# Confirm v1.0.0 is running and healthy
kubectl get pods -n cloudlaunch
# NAME                              READY   STATUS    RESTARTS   AGE
# cloudlaunch-api-xxx-aaa   1/1     Running   0          5m
# cloudlaunch-api-xxx-bbb   1/1     Running   0          5m

# Confirm Argo CD says Healthy + Synced
kubectl get application cloudlaunch-api -n argocd
# STATUS   HEALTH
# Synced   Healthy

# Confirm the application responds
ALB=$(kubectl get ingress cloudlaunch-api -n cloudlaunch -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$ALB/
# {"service":"cloudlaunch-api","version":"1.0.0",...}
```

### Phase 2: Introduce Failure (v2.0.0-bad)

Edit `gitops/base/configmap.yaml` to enable FAIL_READY:
```yaml
data:
  FAIL_READY: "true"
```

Also update the image tag in `gitops/overlays/dev/kustomization.yaml`:
```yaml
images:
  - name: REGISTRY/cloudlaunch-api
    newTag: "2.0.0-bad"
```

Push the changes:
```bash
git add gitops/
git commit -m "feat: deploy v2.0.0-bad (failure demo)"
git push
```

### Phase 3: Observe Failure

Argo CD detects the change and begins rolling update:
```bash
# Watch the rolling update
watch kubectl get pods -n cloudlaunch

# v2 pods will show as Running but 0/1 READY
# NAME                              READY   STATUS    RESTARTS   AGE
# cloudlaunch-api-new-xxx   0/1     Running   0          30s
# cloudlaunch-api-old-aaa   1/1     Running   0          10m
# cloudlaunch-api-old-bbb   1/1     Running   0          10m
```

The rolling update is blocked because:
- `maxUnavailable: 0` means old pods are kept until new ones are ready
- New pods fail readiness checks → never marked Ready
- Old pods remain serving traffic

Check the readiness probe failure:
```bash
kubectl describe pod -n cloudlaunch -l app=cloudlaunch-api | grep -A5 "Readiness"
# Readiness probe failed: HTTP probe failed with statuscode: 503
```

Check Argo CD application health:
```bash
kubectl get application cloudlaunch-api -n argocd
# STATUS    HEALTH
# Synced    Degraded
```

Check Prometheus alert firing:
```bash
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 -- \
  wget -qO- http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname == "CloudLaunchNoHealthyPods")'
```

### Phase 4: Rollback

Revert the GitOps state to v1.0.0:
```bash
# Option A: Use the rollback script
bash scripts/rollback.sh 1.0.0

# Option B: Manual revert
git revert HEAD
git push

# Option C: Direct edit
sed -i 's/FAIL_READY: "true"/FAIL_READY: "false"/' gitops/base/configmap.yaml
sed -i 's/newTag: "2.0.0-bad"/newTag: "1.0.0"/' gitops/overlays/dev/kustomization.yaml
git add gitops/
git commit -m "chore(gitops): rollback to v1.0.0"
git push
```

### Phase 5: Observe Recovery

```bash
# Watch pods recover
watch kubectl get pods -n cloudlaunch
# NAME                              READY   STATUS    RESTARTS   AGE
# cloudlaunch-api-new-xxx   1/1     Running   0          45s
# cloudlaunch-api-old-aaa   Terminating

# Confirm healthy
curl http://$ALB/
# {"service":"cloudlaunch-api","version":"1.0.0",...}

# Confirm Argo CD
kubectl get application cloudlaunch-api -n argocd
# STATUS   HEALTH
# Synced   Healthy
```

## Why This Demonstrates Real GitOps Practices

1. **CI does not directly deploy** — GitHub Actions only pushes to ECR and updates the GitOps manifest
2. **Argo CD is the single source of truth** — it reconciles whatever is in `gitops/overlays/dev/`
3. **Rollback is a git operation** — rolling back means reverting/committing to git, not running `kubectl rollout undo`
4. **The deployment strategy is safe** — `maxUnavailable: 0` ensures traffic is never dropped during a bad deploy
5. **The failure is observable** — Prometheus alerts fire, Grafana shows degraded health, logs show the 503s

## Evidence to Capture

When performing this demonstration, capture:
1. `kubectl get pods -n cloudlaunch` showing 0/1 READY for v2 pods
2. Argo CD UI showing "Degraded" health
3. Grafana showing pod count drop / readiness failure
4. ALB still returning 200s (old pods still serving)
5. Git commit reverting the change
6. Argo CD UI showing "Healthy" again
7. `kubectl get pods` showing all pods running
