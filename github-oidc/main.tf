# ============================================================================
# GitHub Actions OIDC Setup
# ============================================================================
# GitHub Actions가 AWS에 접근할 수 있도록 OIDC 설정
#
# 사용법:
#   cd github-oidc
#   terraform init
#   terraform apply
#
# ⚠️ 이 파일은 infra-terragrunt 배포 전에 먼저 실행해야 합니다!
# ============================================================================

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
  region = "ap-northeast-2"
}

# ============================================================================
# Variables
# ============================================================================
variable "github_org" {
  description = "GitHub Organization 또는 Username"
  type        = string
}

variable "github_repo" {
  description = "GitHub Repository 이름 (platform-dev)"
  type        = string
}

variable "petclinic_repo" {
  description = "GitHub Repository 이름 (petclinic-dev)"
  type        = string
  default     = "petclinic-dev"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

# ============================================================================
# GitHub OIDC Provider
# ============================================================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name      = "github-actions-oidc"
    ManagedBy = "terraform"
  }
}

# ============================================================================
# IAM Role for GitHub Actions
# ============================================================================
resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "github-actions-terraform"
    ManagedBy = "terraform"
  }
}

# ============================================================================
# IAM Policy - AdministratorAccess (또는 필요한 권한만)
# ============================================================================
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ============================================================================
# IAM Role for Petclinic CI/CD (ECR Push + GitOps)
# ============================================================================
resource "aws_iam_role" "petclinic_cicd" {
  name = "github-actions-petclinic-cicd"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.petclinic_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name      = "github-actions-petclinic-cicd"
    Purpose   = "Petclinic MSA CI/CD"
    ManagedBy = "terraform"
  }
}

# ============================================================================
# IAM Policy - Petclinic ECR Push (최소 권한)
# ============================================================================
resource "aws_iam_policy" "petclinic_ecr" {
  name        = "github-actions-petclinic-ecr"
  description = "Petclinic CI/CD - ECR Push permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:ap-northeast-2:${var.aws_account_id}:repository/petclinic-msa/*"
      }
    ]
  })

  tags = {
    Name      = "github-actions-petclinic-ecr"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "petclinic_ecr" {
  role       = aws_iam_role.petclinic_cicd.name
  policy_arn = aws_iam_policy.petclinic_ecr.arn
}

# ============================================================================
# Outputs
# ============================================================================
output "terraform_role_arn" {
  description = "platform-dev용 Role ARN (Terraform 인프라)"
  value       = aws_iam_role.github_actions.arn
}

output "petclinic_role_arn" {
  description = "petclinic-dev용 Role ARN (CI/CD)"
  value       = aws_iam_role.petclinic_cicd.arn
}

output "setup_instructions" {
  description = "설정 가이드"
  value       = <<-EOT

  ============================================
  ✅ GitHub Actions OIDC 설정 완료!
  ============================================

  [ platform-dev 레포 설정 ]
  GitHub → Settings → Secrets → Actions
  ┌─────────────────────────────────────────┐
  │ Name:  AWS_ROLE_ARN                     │
  │ Value: ${aws_iam_role.github_actions.arn}
  └─────────────────────────────────────────┘

  [ petclinic-dev 레포 설정 ]
  GitHub → Settings → Secrets → Actions
  ┌─────────────────────────────────────────┐
  │ Name:  AWS_ROLE_ARN                     │
  │ Value: ${aws_iam_role.petclinic_cicd.arn}
  └─────────────────────────────────────────┘
  ┌─────────────────────────────────────────┐
  │ Name:  GITOPS_TOKEN                     │
  │ Value: (GitHub PAT - repo 권한 필요)    │
  └─────────────────────────────────────────┘

  EOT
}