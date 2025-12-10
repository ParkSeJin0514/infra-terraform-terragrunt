# 🏗️ Terraform + GitOps Infrastructure (Terragrunt)

실무에서 가장 많이 사용되는 **Terragrunt** 기반 IaC 프로젝트입니다.

## 📁 디렉토리 구조

```
infra-terragrunt/
├── terragrunt.hcl        # 공통 설정 (S3 Backend, Provider)
├── env.hcl               # 환경 변수 (이 파일만 수정!)
├── .gitignore            # Git 제외 파일 (keys/ 포함)
│
├── foundation/           # Layer 1: VPC, Subnet
│   └── terragrunt.hcl
│
├── compute/              # Layer 2: EKS, RDS, EC2, IRSA
│   └── terragrunt.hcl    # dependency "foundation" 선언
│
├── bootstrap/            # Layer 3: ArgoCD
│   └── terragrunt.hcl    # dependency "compute" 선언
│
├── modules/              # Terraform 모듈들
│   ├── foundation/
│   ├── compute/
│   ├── bootstrap/
│   ├── network/
│   ├── eks/
│   ├── ec2/
│   └── db/
│
├── github-oidc/          # GitHub Actions OIDC 설정
│   ├── main.tf
│   └── terraform.tfvars
│
├── platform-gitops/      # GitOps Repository (별도 Git 레포로 분리)
│   ├── apps/
│   └── platform/
│
└── keys/                 # SSH Key Pair (⚠️ .gitignore에 포함!)
    ├── test
    └── test.pub
```

---

## 🚀 빠른 시작

### 1. 사전 준비

```bash
# Terragrunt 설치 (macOS)
brew install terragrunt

# Terragrunt 설치 (Linux)
wget https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

# 버전 확인
terragrunt --version
```

### 2. S3 Backend 설정 (처음 1회만)

```bash
# S3 버킷 생성
aws s3 mb s3://petclinic-kr-tfstate --region ap-northeast-2

# DynamoDB 테이블 생성 (State Lock용)
aws dynamodb create-table \
  --table-name petclinic-kr-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

### 3. 환경 설정

```bash
# env.hcl 수정
vim env.hcl

# 수정할 항목:
# - project_name
# - gitops_repo_url (⚠️ 필수!)
```

### 4. SSH Key 생성

```bash
# 키가 없으면 생성
ssh-keygen -t rsa -b 4096 -f keys/test -N ""
```

### 5. 배포

```bash
# 전체 배포 (한 줄!)
terragrunt run-all apply

# 전체 삭제
terragrunt run-all destroy

# Plan 확인
terragrunt run-all plan
```

---

## 📋 주요 명령어

| 명령어 | 설명 |
|--------|------|
| `terragrunt run-all apply` | 전체 배포 (의존성 자동 해결) |
| `terragrunt run-all destroy` | 전체 삭제 (역순 자동) |
| `terragrunt run-all plan` | 전체 Plan 확인 |
| `terragrunt run-all output` | 출력값 확인 |

### 개별 레이어

```bash
cd foundation && terragrunt apply   # VPC, Subnet만
cd compute && terragrunt apply      # EKS, RDS만
cd bootstrap && terragrunt apply    # ArgoCD만
```

---

## 🔐 민감한 정보 관리

### 개요

| 항목 | 저장 위치 | 이유 |
|------|----------|------|
| `db_password` | GitHub Secrets | 비밀번호는 코드에 노출 금지 |
| `keys/` (SSH Key) | .gitignore | 개인키는 Git에 올리면 안 됨 |
| `github_org`, `gitops_repo_url` | env.hcl | 공개 정보라 상관없음 |

### GitHub Secrets 등록

```
GitHub Repo → Settings → Secrets and variables → Actions → New repository secret

등록할 Secret:
┌────────────────────┬─────────────────┐
│ Name               │ Value           │
├────────────────────┼─────────────────┤
│ AWS_ROLE_ARN       │ (OIDC Role ARN) │
│ TF_VAR_db_password │ 123456789       │
└────────────────────┴─────────────────┘
```

### 로컬에서 실행할 때

```bash
# 환경변수 설정 후 실행
export TF_VAR_db_password="123456789"
terragrunt run-all apply

# 또는 한 줄로
TF_VAR_db_password="123456789" terragrunt run-all apply
```

### .gitignore 설정

```gitignore
# 민감한 정보
keys/                    # SSH 개인키
*.auto.tfvars           # 자동 로드되는 변수 파일
secrets.tfvars          # 비밀 변수 파일

# Terraform/Terragrunt
.terraform/
.terragrunt-cache/
*.tfstate
*.tfstate.*
```

---

## 🔄 CI/CD (GitHub Actions)

### 전체 흐름

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. 코드 수정 → git push → PR 생성                                 │
│                     ↓                                            │
│ 2. GitHub Actions: terragrunt plan 자동 실행                      │
│                     ↓                                            │
│ 3. PR 코멘트에 Plan 결과 표시                                      │
│                     ↓                                            │
│ 4. 팀원 리뷰 → Approve                                            │
│                     ↓                                            │
│ 5. Merge → GitHub Actions: terragrunt apply 자동 실행             │
│                     ↓                                            │
│ 6. AWS 인프라 반영 완료! ✅                                        │
└──────────────────────────────────────────────────────────────────┘
```

### CI/CD 설정 방법

#### Step 1: AWS OIDC 설정 (로컬에서 1회 실행)

```bash
cd github-oidc

# terraform.tfvars 수정
vim terraform.tfvars
# github_org = "your-username"
# github_repo = "infra-terragrunt"

# 적용
terraform init
terraform apply

# → role_arn 출력됨 (복사해두기!)
```

#### Step 2: GitHub Secrets 등록

```
GitHub Repo → Settings → Secrets and variables → Actions

New repository secret:
1. AWS_ROLE_ARN       = arn:aws:iam::123456789012:role/github-actions-terraform
2. TF_VAR_db_password = 123456789
```

#### Step 3: 테스트

```bash
# 브랜치 생성
git checkout -b test/cicd

# 아무거나 수정
echo "# test" >> README.md

# Push
git add . && git commit -m "test cicd" && git push -u origin test/cicd

# GitHub에서 PR 생성 → Plan 자동 실행 확인!
```

### PR 화면 예시

```
PR #42: EKS 노드 2개 → 4개 확장

┌─────────────────────────────────────────────┐
│ 🏗️ Terraform Plan 결과                       │
│                                             │
│ Plan: `success`                             │
│                                             │
│ 📋 Plan 상세 보기                            │
│   ~ aws_eks_node_group.workers              │
│       desired_size: 2 → 4                   │
│                                             │
│   Plan: 0 to add, 1 to change, 0 to destroy│
└─────────────────────────────────────────────┘
```

### Workflow 파일

```
.github/workflows/
├── terraform-plan.yml   # PR 시 Plan 실행 + 코멘트
└── terraform-apply.yml  # main merge 시 Apply 실행
```

### 동작 조건

| 이벤트 | 실행 | 조건 |
|--------|------|------|
| PR 생성/업데이트 | Plan | `.tf`, `.hcl`, `modules/**` 변경 시 |
| main Merge | Apply | `.tf`, `.hcl`, `modules/**` 변경 시 |

---

## 🔄 Terragrunt의 마법: 의존성 자동 해결

### 기존 방식
```bash
cd 01-foundation && terraform apply  # 1번
cd 02-compute && terraform apply     # 2번
cd 03-bootstrap && terraform apply   # 3번
# → 순서 틀리면 에러!
```

### Terragrunt 방식
```bash
terragrunt run-all apply
# → Foundation 완료 후 Compute, Compute 완료 후 Bootstrap 자동!
```

### 의존성 선언 (compute/terragrunt.hcl)
```hcl
dependency "foundation" {
  config_path = "../foundation"
}

inputs = {
  vpc_id = dependency.foundation.outputs.vpc_id  # 자동 참조!
}
```

---

## 📊 레이어별 역할

| Layer | 리소스 | 변경 빈도 | 담당 |
|-------|--------|----------|------|
| **Foundation** | VPC, Subnet, NAT | 분기 1회 | 인프라팀 |
| **Compute** | EKS, RDS, EC2, IRSA | 월 1회 | 인프라팀 |
| **Bootstrap** | ArgoCD | 연 1회 | 플랫폼팀 |
| **Platform** | ALB, EFS CSI | 주 1회 | GitOps |
| **Application** | PetClinic | 일 수회 | GitOps |

---

## 🌍 멀티 환경 구성

```
infra-terragrunt/
├── dev/
│   ├── env.hcl           # dev 설정 (vpc_cidr = "10.0.0.0/16")
│   ├── foundation/
│   ├── compute/
│   └── bootstrap/
│
├── stg/
│   ├── env.hcl           # stg 설정 (vpc_cidr = "10.1.0.0/16")
│   └── ...
│
└── prd/
    ├── env.hcl           # prd 설정 (vpc_cidr = "10.2.0.0/16")
    └── ...
```

---

## 📤 배포 후 확인

```bash
# 출력값 확인
terragrunt run-all output

# ArgoCD 비밀번호
cd bootstrap && terragrunt output -raw argocd_admin_password

# ArgoCD 접속
kubectl port-forward svc/argocd-server -n argocd 8080:443
# → https://localhost:8080 (admin / 위에서 확인한 비밀번호)
```

---

## 🔗 platform-gitops 설정

`platform-gitops/` 폴더를 **별도 Git Repository**로 Push:

```bash
cd platform-gitops
git init
git remote add origin https://github.com/your-org/platform-gitops.git
git add .
git commit -m "Initial commit"
git push -u origin main
```

### IRSA Role ARN 설정

Compute 배포 후 출력된 Role ARN을 설정:

```bash
# Role ARN 확인
cd compute && terragrunt output

# platform-gitops/platform/alb-controller/values.yaml 수정
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/petclinic-kr-alb-controller
```

---

## ⚠️ 주의사항

1. **S3 Backend 먼저 생성**
   - 버킷과 DynamoDB 테이블이 없으면 에러

2. **gitops_repo_url 수정 필수**
   - `env.hcl`에서 실제 GitOps 레포 URL로 변경

3. **SSH Key 필요**
   - `keys/test`, `keys/test.pub` 파일 필요
   - 없으면: `ssh-keygen -t rsa -b 4096 -f keys/test -N ""`
   - ⚠️ `.gitignore`에 포함되어 Git에 올라가지 않음!

4. **민감한 정보**
   - `db_password`는 GitHub Secrets로 관리
   - 로컬 실행 시 `TF_VAR_db_password` 환경변수 필요

5. **삭제 시 주의**
   - ArgoCD가 생성한 리소스(ALB 등)가 있으면 삭제 지연
   - Bootstrap 삭제 전 ArgoCD Application 먼저 정리 권장

6. **main 브랜치 보호 권장**
   ```
   Settings → Branches → Add rule
   - Branch name pattern: main
   - ✅ Require pull request reviews
   - ✅ Require status checks (terraform-plan)
   ```

---

## 🆚 기존 방식 vs Terragrunt

| 항목 | 기존 (terraform) | Terragrunt |
|------|-----------------|------------|
| 배포 명령 | 3번 반복 | `terragrunt run-all apply` 한 줄 |
| 의존성 | 수동 관리 | 자동 해결 |
| 코드 중복 | provider.tf 복사 | 상속으로 제거 |
| 멀티 환경 | 폴더 복사 | env.hcl만 다르게 |
| State 관리 | 각각 설정 | 자동 생성 |

---

## 📚 참고 자료

- [Terragrunt 공식 문서](https://terragrunt.gruntwork.io/docs/)
- [Terraform AWS Modules](https://registry.terraform.io/namespaces/terraform-aws-modules)
- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

# CI/CD Test
