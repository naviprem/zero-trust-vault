terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC for EKS
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "zero-trust-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "zero-trust-cluster"
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  # Enable public endpoint access for local kubectl
  cluster_endpoint_public_access = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  cluster_endpoint_private_access = true

  # Node group configuration
  eks_managed_node_groups = {
    workers = {
      min_size     = 3
      max_size     = 3
      desired_size = 3

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"  # Change to SPOT for cost savings

      labels = {
        role = "worker"
      }
    }
  }

  # Enable IRSA for workload identity
  enable_irsa = true
}

# RDS PostgreSQL for Keycloak
resource "aws_db_instance" "keycloak" {
  identifier           = "zero-trust-keycloak"
  engine               = "postgres"
  engine_version       = "16"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_encrypted    = false  # Learning context

  db_name  = "keycloak"
  username = "keycloak"
  password = var.db_password  # Use secrets manager in production

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.keycloak.name

  skip_final_snapshot = true
  publicly_accessible = false

  tags = {
    Name = "keycloak-db"
  }
}

resource "aws_db_subnet_group" "keycloak" {
  name       = "keycloak-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "keycloak-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "keycloak-rds-sg"
  description = "Allow PostgreSQL from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Outputs
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "rds_endpoint" {
  value = aws_db_instance.keycloak.endpoint
}
