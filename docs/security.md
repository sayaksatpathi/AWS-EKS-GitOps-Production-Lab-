# Security

## GitHub Actions Authentication — No Long-Lived Keys

GitHub Actions authenticates to AWS using OIDC (OpenID Connect), not
long-lived access keys.

```
GitHub Actions
     │
     │ OIDC JWT token
     ▼
AWS STS (AssumeRoleWithWebIdentity)
     │
     │ Short-lived credentials (1 hour)
     ▼
AWS API calls (ECR push, EKS describe)
```

The IAM trust policy restricts which repository/branch can assume the role:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:sayaksatpathi/AWS-EKS-GitOps-Production-Lab-:*"
    }
  }
}
```

**Required GitHub configuration:** The workflow uses `id-token: write` permission.
No secrets stored for AWS authentication — only `AWS_ROLE_ARN`.

## IAM Least Privilege

| Role | Purpose | Permissions |
|------|---------|-------------|
| GitHub Actions | CI/CD | ECR push, EKS describe only |
| EKS cluster | Control plane | AmazonEKSClusterPolicy |
| EKS nodes | Worker nodes | ECR read, VPC CNI, EKS worker |
| ALB Controller | Load balancer management | Specific EC2/ELB actions only |

## Kubernetes Security

### Container Security Context

All containers run with:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
```

### RBAC

The application ServiceAccount (`cloudlaunch-api`) has no RBAC bindings
beyond the default. It does not have permission to read secrets, deployments,
or any Kubernetes resources.

### Network Security

- Worker nodes are in private subnets
- Only the ALB is internet-facing
- Security groups restrict pod-to-pod and external traffic

## Image Security

### ECR Scan on Push

ECR automatically scans images on push using Amazon Inspector.

### Trivy Scan in CI

GitHub Actions runs Trivy before pushing:
```yaml
- uses: aquasecurity/trivy-action@master
  with:
    severity: CRITICAL,HIGH
    exit-code: "0"    # Reports but does not fail (can be hardened to "1")
```

### Base Image

Uses `python:3.12-slim` (Debian-based slim image).
Multi-stage build ensures the build toolchain is not in the runtime image.

## Secret Management

- No secrets are committed to git
- AWS credentials are never stored — OIDC only
- Application configuration uses Kubernetes ConfigMaps (no sensitive data)
- Kubernetes Secrets would be used for database passwords, API tokens if needed

## Secret Scanning

`.gitignore` excludes:
```
*.tfstate
*.tfstate.*
.terraform/
terraform.tfvars
*.pem
*.key
*.env
.env*
```

GitHub's push protection secret scanning is enabled for the repository.

## Static Analysis

- **Bandit** runs on Python source code in CI
- **Semgrep** runs SAST on Python, Dockerfile, and secrets detection
- **Trivy** scans the built container image
