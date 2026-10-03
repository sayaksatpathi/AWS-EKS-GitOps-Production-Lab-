locals {
  cluster_name = "${var.project}-${var.environment}"
  common_tags  = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.cluster_name
  cluster_name       = local.cluster_name
  cidr_block         = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "${var.project}-api"
  tags            = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = local.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  tags                = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  prefix             = local.cluster_name
  github_org         = var.github_org
  github_repo        = var.github_repo
  ecr_repository_arn = module.ecr.repository_arn
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_issuer_url    = module.eks.cluster_oidc_issuer_url
  tags               = local.common_tags
}
