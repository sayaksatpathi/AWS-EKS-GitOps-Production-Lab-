# Architecture

## Overview

CloudLaunch is a production-style AWS EKS GitOps platform built to demonstrate
real DevOps/SRE engineering skills. It implements the full lifecycle from code
commit to deployed, monitored application with controlled failure and rollback.

## Architecture Diagram

```
Developer Workstation
        │
        │ git push
        ▼
┌───────────────────────────────────────────────────────┐
│                     GitHub                            │
│                                                       │
│  ┌─────────────────┐    ┌──────────────────────────┐  │
│  │  App Source     │    │   GitOps Manifests       │  │
│  │  app/           │    │   gitops/overlays/dev/   │  │
│  └────────┬────────┘    └──────────────┬───────────┘  │
│           │                            │              │
└───────────┼────────────────────────────┼──────────────┘
            │                            │
            ▼                            │
┌───────────────────────────────────┐    │
│       GitHub Actions CI/CD        │    │
│                                   │    │
│  1. Test (pytest)                 │    │
│  2. Lint (flake8)                 │    │
│  3. K8s manifest validation       │    │
│  4. Terraform fmt/validate        │    │
│  5. SAST (Bandit, Semgrep)        │    │
│  6. Docker build                  │    │
│  7. Container scan (Trivy)        │    │
│  8. ECR push (via OIDC)           │    │
│  9. GitOps image tag update ──────┼────┘
└───────────────────────────────────┘
                                        │
                                        ▼ (git commit to gitops/)
                              ┌─────────────────┐
                              │    Argo CD      │
                              │  Watches repo   │
                              │  Reconciles     │
                              │  cluster state  │
                              └────────┬────────┘
                                       │
                                       ▼
         ┌─────────────────────────────────────────────────┐
         │                  Amazon EKS                     │
         │                                                 │
         │  Namespace: cloudlaunch                        │
         │  ┌──────────────────────────────────────────┐  │
         │  │  Deployment: cloudlaunch-api (2 replicas)│  │
         │  │  ┌──────────┐   ┌──────────┐             │  │
         │  │  │  Pod 1   │   │  Pod 2   │             │  │
         │  │  │ :8080    │   │ :8080    │             │  │
         │  │  └──────────┘   └──────────┘             │  │
         │  └──────────────────┬───────────────────────┘  │
         │                     │                          │
         │  Service (ClusterIP)│                          │
         │  ┌──────────────────▼───────────────────────┐  │
         │  │        cloudlaunch-api:80                │  │
         │  └──────────────────┬───────────────────────┘  │
         │                     │                          │
         │  Ingress (AWS ALB)  │                          │
         │  ┌──────────────────▼───────────────────────┐  │
         │  │  ALB Controller → Application Load Balancer│ │
         │  └──────────────────────────────────────────┘  │
         └─────────────────────────────────────────────────┘
                              │
                              ▼
                          Internet

┌─────────────────────────────────────────────────────────┐
│                   Observability Stack                   │
│  Namespace: monitoring                                  │
│                                                         │
│  Prometheus ──scrapes──► cloudlaunch pods (/metrics)   │
│  Alertmanager ◄── alerts from Prometheus               │
│  Grafana ──queries──► Prometheus & Loki                │
│  Loki + Promtail ──collects──► pod logs                │
└─────────────────────────────────────────────────────────┘
```

## AWS Infrastructure

### VPC
- CIDR: 10.0.0.0/16
- 2 public subnets (ALB lives here)
- 2 private subnets (worker nodes live here)
- Internet Gateway for public egress
- NAT Gateway for private subnet egress
- Route tables per subnet class

### EKS
- Managed control plane (Kubernetes 1.30)
- Managed node group (t3.medium, 2 nodes by default)
- OIDC provider for IRSA (IAM Roles for Service Accounts)
- Control plane logging enabled

### ECR
- Image scanning on push
- Immutable tags enforced
- Lifecycle policy: keeps last 10 tagged, removes untagged after 1 day

### IAM
- GitHub Actions OIDC role (no long-lived keys)
- EKS cluster role
- EKS node role
- ALB Controller IRSA role

## Network Flow

```
Internet → ALB (public subnet) → Service (ClusterIP) → Pods (private subnet)
```

Worker nodes run in private subnets. Outbound traffic routes through NAT Gateway.
The ALB is internet-facing and terminates HTTP (80). HTTPS via ACM is an optional enhancement.
