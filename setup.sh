#!/usr/bin/env bash
set -euo pipefail

echo "Landing-Zone setup helper"
echo "This script helps to create initial OIDC trust resources and instructs on secrets to set. It does NOT run without required admin credentials."

cat <<'EOF'
Quick steps:
1. Ensure you have Azure CLI and gcloud installed and are logged in as admin.
2. Set these repo secrets in GitHub: AZURE_CREDENTIALS, AZURE_SUBSCRIPTION_ID, GCP_SA_KEY, GCP_PROJECT_ID, ADMIN_GITHUB_TOKEN
3. Run the Azure and GCP trust snippets in the README to create federated trust.
EOF

echo "
Sample: create Azure federated credential (runs locally with Az login):"
echo "az login && az account set --subscription \$AZURE_SUBSCRIPTION_ID"
echo "# Create app + service principal"
echo "az ad app create --display-name \"gh-oidc-app\" --identifier-uris \"api://gh-oidc-app-landing-zone\" || true"
echo "# Follow README to post federatedIdentityCredentials via Graph API or az rest"

echo "
After running these steps, push branches and create the following secrets in the repo settings:
- AZURE_CREDENTIALS (admin SP JSON)
- AZURE_SUBSCRIPTION_ID
- GCP_SA_KEY (admin SA JSON)
- GCP_PROJECT_ID
- ADMIN_GITHUB_TOKEN

See README.md for full instructions."

exit 0
#!/bin/bash
set -e

# Landing Zone IAM System - Deployment & Setup Script
# Usage: bash setup.sh YOUR-ORG

ORG="${1:-YOUR-ORG}"
REPO="landing-zone"
ADMIN_TEAM="landing-zone-admins"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
  echo -e "${BLUE}ℹ️  ${1}${NC}"
}

log_success() {
  echo -e "${GREEN}✅ ${1}${NC}"
}

log_warning() {
  echo -e "${YELLOW}⚠️  ${1}${NC}"
}

log_error() {
  echo -e "${RED}❌ ${1}${NC}"
  exit 1
}

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  command -v git >/dev/null 2>&1 || log_error "git not found"
  command -v gh >/dev/null 2>&1 || log_error "GitHub CLI not found"
  command -v az >/dev/null 2>&1 || log_error "Azure CLI not found"
  command -v gcloud >/dev/null 2>&1 || log_error "Google Cloud SDK not found"
  command -v yq >/dev/null 2>&1 || log_error "yq not found"
  command -v jq >/dev/null 2>&1 || log_error "jq not found"

  log_success "All prerequisites found"
}

# Validate organization
validate_org() {
  log_info "Validating GitHub organization: ${ORG}"

  if ! gh org view "${ORG}" >/dev/null 2>&1; then
    log_error "Organization not found or not accessible: ${ORG}"
  fi

  log_success "Organization validated"
}

# Update repository configuration
update_repo_config() {
  log_info "Updating repository configuration..."

  # Replace YOUR-ORG placeholders
  find . -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.html" -o -name "*.md" \) \
    -not -path "./.git/*" \
    -exec sed -i "s/YOUR-ORG/${ORG}/g" {} \;

  log_success "Repository configuration updated"
}

# Create admin team
create_admin_team() {
  log_info "Creating admin team: ${ADMIN_TEAM}"

  if gh api "/orgs/${ORG}/teams/${ADMIN_TEAM}" >/dev/null 2>&1; then
    log_warning "Team already exists: ${ADMIN_TEAM}"
  else
    if gh api "/orgs/${ORG}/teams" \
      -f name="${ADMIN_TEAM}" \
      -f description="Landing Zone IAM Administrators" \
      -f privacy="closed" >/dev/null 2>&1; then
      log_success "Team created: ${ADMIN_TEAM}"
    else
      log_warning "Could not create team (may require org admin)"
    fi
  fi
}

# Configure Azure
configure_azure() {
  log_info "Configuring Azure..."
  
  read -p "Enter subscription ID: " SUBSCRIPTION_ID
  if [[ -z "$SUBSCRIPTION_ID" ]]; then
    log_error "Subscription ID required"
  fi

  log_info "Logging in to Azure..."
  az login

  log_info "Creating service principal for Landing Zone..."
  
  SP_NAME="landing-zone-admin"
  SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "${SP_NAME}" \
    --role "User Access Administrator" \
    --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
    --output json)

  CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.clientId')
  TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenantId')
  
  log_success "Service principal created: ${SP_NAME}"
  echo ""
  log_info "Azure Credentials (save these as repo secrets):"
  echo "AZURE_CREDENTIALS (full JSON):"
  echo "$SP_OUTPUT" | jq .
  echo ""
  echo "AZURE_CLIENT_ID: ${CLIENT_ID}"
  echo "AZURE_TENANT_ID: ${TENANT_ID}"
  echo "AZURE_SUBSCRIPTION_ID: ${SUBSCRIPTION_ID}"
  echo ""

  # Save for later
  echo "$SP_OUTPUT" > /tmp/azure-sp.json
  
  # Configure Workload Identity Federation
  log_info "Configuring Workload Identity Federation for GitHub OIDC..."
  
  OBJECT_ID=$(az ad sp show --id "${CLIENT_ID}" --query id -o tsv)
  APP_ID=$(az ad sp show --id "${CLIENT_ID}" --query appId -o tsv)
  
  az ad app federated-credential create \
    --id "${APP_ID}" \
    --parameters @- <<EOF
{
  "name": "github-actions",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${ORG}/${REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions federated credential for landing-zone"
}
EOF

  log_success "Azure Workload Identity Federation configured"
}

# Configure GCP
configure_gcp() {
  log_info "Configuring GCP..."
  
  read -p "Enter GCP Project ID: " PROJECT_ID
  if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID required"
  fi

  log_info "Setting GCP project..."
  gcloud config set project "${PROJECT_ID}"

  log_info "Creating service account for Landing Zone..."
  SA_NAME="landing-zone-admin"
  SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  
  if gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
    log_warning "Service account already exists: ${SA_EMAIL}"
  else
    gcloud iam service-accounts create "${SA_NAME}" \
      --display-name="Landing Zone IAM Admin"
    log_success "Service account created: ${SA_EMAIL}"
  fi

  # Grant roles
  log_info "Granting IAM roles..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.securityAdmin" \
    --quiet

  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.admin" \
    --quiet

  log_success "IAM roles granted"

  # Create Workload Identity Federation
  log_info "Configuring Workload Identity Federation..."
  
  POOL_NAME="github-pool"
  PROVIDER_NAME="github-provider"

  # Check if pool exists
  POOL_EXISTS=$(gcloud iam workload-identity-pools list \
    --project="${PROJECT_ID}" \
    --location=global \
    --filter="displayName:GitHub" \
    --format="value(name)" || echo "")

  if [[ -z "$POOL_EXISTS" ]]; then
    gcloud iam workload-identity-pools create "${POOL_NAME}" \
      --project="${PROJECT_ID}" \
      --location=global \
      --display-name="GitHub Actions" \
      --quiet
    log_success "Workload Identity Pool created: ${POOL_NAME}"
  else
    log_warning "Workload Identity Pool already exists"
    POOL_NAME=$(basename "$POOL_EXISTS")
  fi

  # Create provider
  PROVIDER_EXISTS=$(gcloud iam workload-identity-pools providers list \
    --workload-identity-pool="${POOL_NAME}" \
    --location=global \
    --project="${PROJECT_ID}" \
    --filter="displayName:GitHub" \
    --format="value(name)" || echo "")

  if [[ -z "$PROVIDER_EXISTS" ]]; then
    gcloud iam workload-identity-pools providers create-oidc "${PROVIDER_NAME}" \
      --project="${PROJECT_ID}" \
      --location=global \
      --workload-identity-pool="${POOL_NAME}" \
      --display-name="GitHub" \
      --attribute-mapping="google.subject=assertion.sub" \
      --issuer-uri=https://token.actions.githubusercontent.com \
      --quiet
    log_success "OIDC Provider created: ${PROVIDER_NAME}"
  else
    log_warning "OIDC Provider already exists"
  fi

  # Get pool resource name
  POOL_RESOURCE=$(gcloud iam workload-identity-pools describe "${POOL_NAME}" \
    --project="${PROJECT_ID}" \
    --location=global \
    --format='value(name)')

  # Create service account impersonation binding
  gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --project="${PROJECT_ID}" \
    --role=roles/iam.workloadIdentityUser \
    --member="principalSet://iam.googleapis.com/${POOL_RESOURCE}/attribute.repository/${ORG}/${REPO}" \
    --quiet

  log_success "Workload Identity Federation configured"

  # Get GCP SA key (fallback for non-OIDC)
  log_info "Generating GCP Service Account Key (as fallback)..."
  gcloud iam service-accounts keys create /tmp/gcp-key.json \
    --iam-account="${SA_EMAIL}"

  log_success "GCP Configuration Complete"
  echo ""
  log_info "GCP Secrets (save these as repo secrets):"
  echo "GCP_SA_KEY (full JSON):"
  cat /tmp/gcp-key.json | jq .
  echo ""
  echo "GCP_PROJECT_ID: ${PROJECT_ID}"
  echo "GCP_SERVICE_ACCOUNT_EMAIL: ${SA_EMAIL}"
  echo "GCP_WORKLOAD_IDENTITY_PROVIDER: ${POOL_RESOURCE}/providers/${PROVIDER_NAME}"
  echo ""
}

# Configure repository secrets
configure_secrets() {
  log_info "Configuring GitHub repository secrets..."
  
  echo ""
  log_warning "IMPORTANT: The following secrets must be set in your GitHub repository"
  echo ""
  
  echo "To set secrets, use:"
  echo "  gh secret set SECRET_NAME --body 'secret-value' -R ${ORG}/${REPO}"
  echo ""
  
  echo "Required secrets:"
  echo "  1. AZURE_CREDENTIALS - Full SP JSON from /tmp/azure-sp.json"
  echo "  2. AZURE_CLIENT_ID - Client ID from Azure SP"
  echo "  3. AZURE_TENANT_ID - Tenant ID from Azure SP"
  echo "  4. AZURE_SUBSCRIPTION_ID - Your subscription ID"
  echo "  5. GCP_SA_KEY - Full SA key JSON from /tmp/gcp-key.json"
  echo "  6. GCP_PROJECT_ID - Your GCP project ID"
  echo "  7. GCP_SERVICE_ACCOUNT_EMAIL - Your GCP service account email"
  echo "  8. GCP_WORKLOAD_IDENTITY_PROVIDER - WIF provider resource name"
  echo "  9. ADMIN_GITHUB_TOKEN - GitHub PAT with repo/issues scope"
  echo ""
  
  echo "Optional secrets:"
  echo "  - RESEND_API_KEY - For email notifications"
  echo "  - SLACK_WEBHOOK_URL - For Slack alerts"
  echo ""
  
  read -p "Press Enter to continue once secrets are configured in GitHub..."
}

# Enable GitHub Pages
enable_pages() {
  log_info "Enabling GitHub Pages..."
  
  echo ""
  log_warning "MANUAL STEP REQUIRED:"
  echo "1. Go to: https://github.com/${ORG}/${REPO}/settings/pages"
  echo "2. Select 'Deploy from a branch'"
  echo "3. Choose branch: gh-pages"
  echo "4. Choose folder: / (root)"
  echo "5. Save"
  echo ""
  echo "Portal will be available at:"
  echo "  User: https://${ORG}.github.io/${REPO}/"
  echo "  Admin: https://${ORG}.github.io/${REPO}/admin.html"
  echo ""
  
  read -p "Press Enter once Pages is configured..."
}

# Deploy gh-pages branch
deploy_pages() {
  log_info "Deploying GitHub Pages branch..."
  
  if git rev-parse --verify gh-pages >/dev/null 2>&1; then
    log_warning "Branch gh-pages already exists, updating..."
    git checkout gh-pages
    git pull origin gh-pages
  else
    log_info "Creating gh-pages branch..."
    git checkout -b gh-pages
  fi
  
  # Ensure HTML files are in root
  if [[ ! -f "index.html" ]]; then
    log_error "index.html not found in repository root"
  fi
  
  if [[ ! -f "admin.html" ]]; then
    log_error "admin.html not found in repository root"
  fi
  
  log_info "Pushing gh-pages branch..."
  git push -u origin gh-pages
  
  log_success "GitHub Pages deployed"
}

# Run validation tests
run_validation() {
  log_info "Running validation tests..."
  
  echo ""
  log_info "Testing configuration files..."
  
  # Check YAML syntax
  yq eval . roles.yml > /dev/null && log_success "roles.yml is valid"
  yq eval . users.yml > /dev/null && log_success "users.yml is valid"
  
  # Check JSON syntax
  jq . drift-policy.json > /dev/null && log_success "drift-policy.json is valid"
  
  # Check workflow files
  for workflow in .github/workflows/*.yml; do
    yq eval . "$workflow" > /dev/null && log_success "$(basename $workflow) is valid"
  done
  
  log_success "All validation tests passed"
}

# Print summary
print_summary() {
  echo ""
  echo "=========================================="
  echo "Landing Zone IAM System - Setup Complete!"
  echo "=========================================="
  echo ""
  echo "Organization: ${ORG}"
  echo "Repository: ${REPO}"
  echo ""
  echo "Next Steps:"
  echo "1. ✅ Review secrets configuration"
  echo "2. ✅ Enable GitHub Pages (gh-pages branch)"
  echo "3. ⏳ Test user portal at:"
  echo "     https://${ORG}.github.io/${REPO}/"
  echo "4. ⏳ Test admin console at:"
  echo "     https://${ORG}.github.io/${REPO}/admin.html"
  echo ""
  echo "Documentation:"
  echo "  📖 See README.md for complete setup and usage guide"
  echo "  🔧 Workflows are in .github/workflows/"
  echo "  📋 Configuration files:"
  echo "     - roles.yml (role definitions)"
  echo "     - users.yml (user directory)"
  echo "     - drift-policy.json (compliance expectations)"
  echo ""
  echo "Support:"
  echo "  GitHub Issues: https://github.com/${ORG}/${REPO}/issues"
  echo "  Check README.md Troubleshooting section"
  echo ""
}

# Main execution
main() {
  echo ""
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Landing Zone IAM System - Setup Wizard       ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""

  if [[ "$ORG" == "YOUR-ORG" ]]; then
    log_error "Please provide your GitHub organization: bash setup.sh YOUR-ORG"
  fi

  check_prerequisites
  validate_org
  update_repo_config
  create_admin_team
  
  read -p "Configure Azure? (y/n) " -n 1 -r AZURE_RESPONSE
  echo ""
  if [[ $AZURE_RESPONSE =~ ^[Yy]$ ]]; then
    configure_azure
  fi
  
  read -p "Configure GCP? (y/n) " -n 1 -r GCP_RESPONSE
  echo ""
  if [[ $GCP_RESPONSE =~ ^[Yy]$ ]]; then
    configure_gcp
  fi
  
  configure_secrets
  enable_pages
  deploy_pages
  run_validation
  print_summary
}

# Run main function
main "$@"
