# 🏗️ Platform-Dev (Terragrunt)

AWS EKS 인프라를 위한 Terragrunt 기반 IaC 프로젝트

## 🏛️ 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3: Bootstrap   │ ArgoCD                                   │
├─────────────────────────────────────────────────────────────────┤
│ Layer 2: Compute     │ EKS, RDS, EC2, IRSA, Karpenter IAM      │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: Foundation  │ VPC, Subnets, NAT Gateway                │
└─────────────────────────────────────────────────────────────────┘
```

### 🔄 노드 운영 아키텍처 (Karpenter 포함)

```
┌─────────────────────────────────────────────────────────────────┐
│                     EKS Cluster (petclinic-kr-eks)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────────┐    ┌─────────────────────────────┐ │
│  │  Managed Node Group     │    │      Karpenter Nodes        │ │
│  │  (시스템 컴포넌트 전용)    │    │     (워크로드용, 동적)        │ │
│  ├─────────────────────────┤    ├─────────────────────────────┤ │
│  │ • t3.medium × 2대       │    │ • t3.medium ~ t3.2xlarge   │ │
│  │ • ON_DEMAND (고정)      │    │ • Spot 우선 + ON_DEMAND    │ │
│  │ • Karpenter Controller  │    │ • 0 ~ 100 vCPU 동적 확장   │ │
│  │ • CoreDNS, ALB LBC      │    │ • Petclinic 등 앱 실행      │ │
│  │ • ArgoCD, EFS CSI       │    │ • 자동 스케일 인/아웃        │ │
│  └─────────────────────────┘    └─────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 📁 디렉토리 구조

```
├── terragrunt.hcl      # 공통 설정 (S3 Backend)
├── env.hcl             # 환경 변수 (★ 수정 필요)
├── foundation/         # Layer 1: 네트워크
├── compute/            # Layer 2: EKS, RDS, EC2, Karpenter IAM
├── bootstrap/          # Layer 3: ArgoCD
├── modules/            # Terraform 모듈
│   └── compute/
│       ├── main.tf         # EKS, EC2, RDS
│       ├── iam.tf          # IRSA (ALB, EFS, External Secrets)
│       └── karpenter.tf    # ★ Karpenter IAM, SQS, EventBridge
├── github-oidc/        # GitHub Actions OIDC 설정
├── keys/               # SSH Key Pair (.gitignore)
└── .github/workflows/  # CI/CD 워크플로우
    ├── terraform-apply.yml     # Plan & Apply
    ├── terraform-plan.yml      # PR Plan
    └── terraform-all-destroy.yml # Destroy (Karpenter 정리 포함)
```

## 🚀 사용법

```bash
# 전체 배포
TF_VAR_db_password="your-password" terragrunt run-all apply

# 전체 삭제 (수동)
./delete.sh                       # EKS 리소스 사전 정리
terragrunt run-all destroy        # 인프라 삭제

# 개별 레이어
cd foundation && terragrunt apply
cd compute && terragrunt apply
cd bootstrap && terragrunt apply
```

## 📋 사전 준비

```bash
# S3 Backend
aws s3 mb s3://petclinic-kr-tfstate --region ap-northeast-2
aws dynamodb create-table --table-name petclinic-kr-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# SSH Key 생성
ssh-keygen -t rsa -b 4096 -f keys/test -N ""

# env.hcl 수정 (gitops_repo_url 필수!)
```

## ⚙️ CI/CD (GitHub Actions)

| 워크플로우 | 트리거 | 동작 |
|-----------|--------|------|
| `terraform-plan.yml` | PR | Plan 실행 |
| `terraform-apply.yml` | Push to main | Apply 실행 |
| `terraform-all-destroy.yml` | 수동 (workflow_dispatch) | Pre-cleanup → Destroy |

### 🔧 설정 방법

1. `github-oidc/` 실행하여 OIDC Role 생성
2. GitHub Secrets 등록: `AWS_ROLE_ARN`, `TF_VAR_db_password`
3. PR 생성 시 자동 Plan, Merge 시 자동 Apply

### 🗑️ Destroy 워크플로우

```
GitHub Actions → Run workflow → confirm: "destroy" 입력

┌─────────────────────────────────────────────────────────────────┐
│ 1. confirm         │ 'destroy' 입력 확인                        │
├─────────────────────────────────────────────────────────────────┤
│ 2. pre-cleanup     │ EKS 리소스 사전 정리 (★ 핵심)              │
│    ├── ArgoCD Application Finalizer 제거                        │
│    ├── ArgoCD CRD 삭제                                          │
│    ├── External Secrets 정리                                    │
│    ├── ★ Karpenter NodeClaim/NodePool/EC2NodeClass 정리        │
│    ├── ★ Karpenter가 프로비저닝한 EC2 인스턴스 종료            │
│    ├── Ingress 삭제 (ALB 트리거)                                │
│    ├── Namespace Finalizer 제거                                 │
│    └── AWS ALB/Target Group 삭제                                │
├─────────────────────────────────────────────────────────────────┤
│ 3. destroy         │ Terragrunt destroy 실행                    │
│    ├── Bootstrap (ArgoCD)                                       │
│    ├── Compute (EKS, RDS, EC2, Karpenter IAM)                  │
│    └── Foundation (VPC)                                         │
└─────────────────────────────────────────────────────────────────┘
```

## 📦 리소스 목록

| Layer | 리소스 |
|-------|--------|
| Foundation | VPC, Public/Private Subnets, NAT, IGW |
| Compute | EKS Cluster, Node Group, RDS MySQL, Bastion EC2, IRSA Roles, **Karpenter IAM** |
| Bootstrap | ArgoCD (Helm), Root Application (App of Apps) |

## 🔐 IRSA Roles

| Role | 용도 |
|------|------|
| ALB Controller | AWS Load Balancer Controller |
| EFS CSI Driver | EFS 볼륨 마운트 |
| External Secrets | Secrets Manager 접근 |
| **Karpenter Controller** | EC2 인스턴스 프로비저닝/삭제 |

## 🎯 Karpenter 리소스 (Terraform)

`modules/compute/karpenter.tf`에서 생성되는 리소스:

| 리소스 | 설명 |
|--------|------|
| `aws_iam_role.karpenter_controller` | Karpenter Controller IRSA Role |
| `aws_iam_role.karpenter_node` | Karpenter가 프로비저닝하는 노드용 IAM Role |
| `aws_iam_instance_profile.karpenter_node` | 노드 Instance Profile |
| `aws_sqs_queue.karpenter_interruption` | Spot 중단 알림용 SQS Queue |
| `aws_cloudwatch_event_rule.*` | Spot/상태 변경 이벤트 규칙 |
| `aws_ec2_tag.*` | Subnet/SG에 Karpenter Discovery 태그 |

## 💰 비용 최적화

### Karpenter Spot Instance 활용

| 구분 | 설정 |
|------|------|
| Managed Node Group | ON_DEMAND 2대 (시스템용, 고정) |
| Karpenter Nodes | **Spot 우선** + ON_DEMAND fallback |
| 인스턴스 타입 | t3.medium ~ t3.2xlarge |

### 예상 비용 절감

| 항목 | ON_DEMAND | Spot 혼합 | 절감 |
|------|-----------|-----------|------|
| 월간 노드 비용 | ~$115 | ~$40 | **~65%** |

## ⚠️ 주의사항

- `env.hcl`의 `gitops_repo_url` 필수 수정
- SSH Key 없으면 생성 필요
- **삭제 시 반드시 Pre-cleanup 먼저 실행** (GitHub Actions 권장)
- Karpenter 설치 후 시스템 노드 Taint 활성화 가능 (env.hcl)
- Subnet 태그 자동 설정됨 (`karpenter.sh/discovery`, `kubernetes.io/role/elb`)

## 🔗 연관 저장소

| 저장소 | 설명 |
|--------|------|
| **platform-gitops** | GitOps 매니페스트 (Karpenter, ArgoCD Apps) |
| **petclinic-gitops** | PetClinic 애플리케이션 GitOps |