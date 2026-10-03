# GitOps with Argo CD

## The GitOps Model

```
Developer pushes code
        │
        ▼
GitHub Actions CI
  - runs tests
  - scans for vulnerabilities
  - builds Docker image
  - pushes to ECR
  - updates gitops/overlays/dev/kustomization.yaml
  - commits and pushes to git
        │
        ▼
Git repository (the source of truth)
  gitops/overlays/dev/kustomization.yaml
    images:
      - newTag: "sha-abc1234"   ← updated by CI
        │
        ▼
Argo CD detects diff between
  desired state (git)
  actual state (cluster)
        │
        ▼
Argo CD applies Kubernetes manifests
  kubectl apply is run by Argo CD
  GitHub Actions NEVER runs kubectl apply for deployments
        │
        ▼
EKS rolls out the new pods
```

## Directory Structure

```
gitops/
├── base/                    # Environment-agnostic Kubernetes manifests
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── pdb.yaml
│   ├── servicemonitor.yaml
│   └── kustomization.yaml
│
├── overlays/
│   └── dev/                 # Dev-specific overrides
│       ├── kustomization.yaml   ← IMAGE TAG UPDATED HERE BY CI
│       └── replica-patch.yaml
│
└── argocd/
    ├── application.yaml     # Argo CD Application resource
    └── project.yaml         # Argo CD Project resource
```

## How Argo CD Is Installed

```bash
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

## How the Application Is Registered

```bash
# Apply the Argo CD project first
kubectl apply -f gitops/argocd/project.yaml

# Then apply the Application
kubectl apply -f gitops/argocd/application.yaml
```

The Application CR tells Argo CD:
- Source: `https://github.com/sayaksatpathi/AWS-EKS-GitOps-Production-Lab-`
- Path: `gitops/overlays/dev`
- Destination: `https://kubernetes.default.svc` / namespace `cloudlaunch`
- Sync policy: `automated` with `selfHeal: true` and `prune: true`

## Reconciliation Loop

1. Argo CD polls the git repository every 3 minutes (or on webhook)
2. It computes the desired state by rendering `kustomize build gitops/overlays/dev`
3. It compares desired state with actual cluster state
4. If they differ, it applies the diff with `kubectl apply`
5. It monitors the rollout until pods are healthy or timeout

## Detecting Drift

Drift occurs when the cluster state differs from git. This can happen if someone
runs `kubectl edit` or `kubectl delete` directly.

```bash
# Introduce drift manually
kubectl scale deployment cloudlaunch-api -n cloudlaunch --replicas=0

# Watch Argo CD self-heal (within ~3 minutes)
kubectl get pods -n cloudlaunch -w
# Argo CD will restore replicas to 2
```

## Rollback

Rollback is a git operation, not a `kubectl rollout undo`:

```bash
# Revert to a previous commit
git log --oneline gitops/overlays/dev/kustomization.yaml

# Revert the specific commit
git revert <commit-hash>
git push

# Or directly edit the tag
sed -i 's/newTag: "2.0.0"/newTag: "1.0.0"/' gitops/overlays/dev/kustomization.yaml
git add gitops/
git commit -m "chore(gitops): rollback to v1.0.0"
git push
```

Argo CD will detect the git change and reconcile, restoring the previous deployment.
