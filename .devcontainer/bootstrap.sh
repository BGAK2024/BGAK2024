#!/usr/bin/env bash
set -euo pipefail

echo "🔧 Bootstrapping OSBRN Codespace environment..."

# -----------------------------
# 1. Basic tooling
# -----------------------------
echo "📦 Installing core tools (Node, npm, Terraform, AWS CLI)..."

# Node (if not already installed in image)
if ! command -v node >/dev/null 2>&1; then
  echo "Installing Node.js LTS..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

# Terraform
if ! command -v terraform >/dev/null 2>&1; then
  echo "Installing Terraform..."
  TF_VERSION="1.9.5"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" -o /tmp/terraform.zip
  sudo unzip -o /tmp/terraform.zip -d /usr/local/bin
  rm /tmp/terraform.zip
fi

# AWS CLI v2
if ! command -v aws >/dev/null 2>&1; then
  echo "Installing AWS CLI v2..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi

# -----------------------------
# 2. Project structure
# -----------------------------
echo "📁 Creating OSBRN project structure..."

mkdir -p backend/src/handlers backend/src/services backend/src/repositories
mkdir -p frontend
mkdir -p infra/modules
mkdir -p .github/workflows

# -----------------------------
# 3. Backend setup
# -----------------------------
echo "🧠 Setting up backend (TypeScript + Node)..."

cd backend

if [ ! -f package.json ]; then
  npm init -y
fi

npm install --save \
  aws-sdk \
  @aws-sdk/client-dynamodb \
  @aws-sdk/lib-dynamodb \
  uuid \
  stripe \
  jsonwebtoken

npm install --save-dev \
  typescript \
  ts-node \
  @types/node \
  @types/jsonwebtoken \
  @types/aws-lambda \
  eslint \
  prettier

npx tsc --init --rootDir src --outDir dist --esModuleInterop true --resolveJsonModule true --module commonjs --target ES2020

cd ..

# -----------------------------
# 4. Frontend setup (Next.js)
# -----------------------------
echo "🎨 Setting up frontend (Next.js + TypeScript)..."

if [ ! -d "frontend" ] || [ -z "$(ls -A frontend)" ]; then
  npx create-next-app@latest frontend --typescript --eslint --src-dir --no-tailwind --use-npm <<EOF
 y
EOF
fi

# -----------------------------
# 5. Terraform skeleton
# -----------------------------
echo "🌍 Setting up Terraform skeleton..."

cat > infra/main.tf << 'EOF'
tf {
  required_version = ">= 1.9.0"
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

# TODO: wire modules (cognito, dynamodb, lambda, apigw, cloudfront, route53, acm, s3, waf, cloudtrail, iam)
EOF

cat > infra/variables.tf << 'EOF'
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
EOF

cat > infra/outputs.tf << 'EOF'
output "region" {
  value = var.aws_region
}
EOF

# -----------------------------
# 6. GitHub Actions skeleton
# -----------------------------
echo "⚙️ Creating GitHub Actions workflows..."

cat > .github/workflows/backend-ci.yml << 'EOF'
name: Backend CI/CD

on:
  push:
    paths:
      - "backend/**"
      - "infra/**"
      - ".github/workflows/backend-ci.yml"
  pull_request:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install backend deps
        working-directory: ./backend
        run: npm install

      - name: Build backend
        working-directory: ./backend
        run: npm run build || npx tsc

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.5

      - name: Terraform Init
        working-directory: ./infra
        run: terraform init

      - name: Terraform Plan
        working-directory: ./infra
        run: terraform plan -input=false

      # Uncomment to enable apply in non-PR branches
      # - name: Terraform Apply
      #   if: github.ref == 'refs/heads/main'
      #   working-directory: ./infra
      #   run: terraform apply -auto-approve -input=false
EOF

cat > .github/workflows/frontend-ci.yml << 'EOF'
name: Frontend CI/CD

on:
  push:
    paths:
      - "frontend/**"
      - ".github/workflows/frontend-ci.yml"
  pull_request:

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"

      - name: Install frontend deps
        working-directory: ./frontend
        run: npm install

      - name: Build frontend
        working-directory: ./frontend
        run: npm run build
EOF

# -----------------------------
# 7. Environment hints
# -----------------------------
echo "🧩 Creating .env.example files..."

cat > backend/.env.example << 'EOF'
AWS_REGION=us-east-1
DYNAMODB_TABLE=osbrn-main
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
COGNITO_USER_POOL_ID=us-east-1_xxxxx
COGNITO_CLIENT_ID=xxxxxxxx
EOF

cat > frontend/.env.local.example << 'EOF'
NEXT_PUBLIC_API_BASE_URL=https://api.osbrn.example.com
NEXT_PUBLIC_COGNITO_USER_POOL_ID=us-east-1_xxxxx
NEXT_PUBLIC_COGNITO_CLIENT_ID=xxxxxxxx
EOF

echo "✅ OSBRN Codespace bootstrap complete."
echo "Next steps:"
echo "1) Configure AWS credentials in Codespaces (env vars or AWS SSO)."
echo "2) Copy .env.example to .env in backend and frontend."
echo "3) Start coding or paste in your AI-generated code into the created structure.")
