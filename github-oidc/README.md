# GitHub Actions OIDC Setup

GitHub Actions에서 AWS에 접근하기 위한 OIDC 설정을 관리합니다.

## 구성 요소

| Role | 용도 | 권한 |
|------|------|------|
| `github-actions-terraform` | platform-dev 인프라 배포 | AdministratorAccess |
| `github-actions-petclinic-cicd` | petclinic-dev CI/CD | ECR Push (최소 권한) |

## 사용법

```bash
cd github-oidc
terraform init
terraform plan
terraform apply
```

## GitHub Secrets 설정

### platform-dev 레포
| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | `terraform output -raw terraform_role_arn` |

### petclinic-dev 레포
| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | `terraform output -raw petclinic_role_arn` |
| `GITOPS_TOKEN` | GitHub PAT (repo 권한 필요) |

## 아키텍처

```
GitHub Actions                     AWS
┌─────────────┐                   ┌─────────────────────┐
│ Workflow    │── OIDC Token ───► │ IAM OIDC Provider   │
└─────────────┘                   └──────────┬──────────┘
      │                                      │
      │         AssumeRole                   ▼
      │◄─────────────────────────  ┌─────────────────────┐
      │                            │ IAM Role            │
      ▼                            │ (레포별 권한 분리)   │
┌─────────────┐                   └─────────────────────┘
│ AWS 작업    │
│ (ECR Push)  │
└─────────────┘
```

## 새 레포 추가 시

1. `main.tf`에 새 IAM Role 추가
2. `terraform.tfvars`에 변수 추가
3. `terraform apply` 실행
4. 해당 레포에 `AWS_ROLE_ARN` Secret 등록
