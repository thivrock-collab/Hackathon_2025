# Landing-Zone IAM System

This repository provides a GitHub-native Landing-Zone IAM system that uses GitHub Actions, OIDC federation, Azure CLI and Google Cloud SDK to provision short-lived Azure service principals and GCP service accounts for developers.

Important: replace `ACME-ENTERPRISE` below with your organization where indicated.

Contents
- `roles.yml` - Role matrix for Azure/GCP and TTLs
- `users.yml` - User directory (github username, email, teams, status)
- `drift-policy.json` - Expected state for drift detection
- `index.html`, `admin.html` - GitHub Pages UI (branch: `gh-pages`)
- `.github/workflows/*` - Actions to process requests, rotate secrets, detect drift

Required repository secrets (set these in the repo settings):
- `AZURE_CREDENTIALS` - Admin SP JSON used for initial provisioning (for azure cli admin ops)
- `AZURE_SUBSCRIPTION_ID`
- `GCP_SA_KEY` - GCP admin SA JSON for provisioning
- `GCP_PROJECT_ID`
- `RESEND_API_KEY` (optional for email)
- `ADMIN_GITHUB_TOKEN` - Admin PAT for issue actions (issues:write)
- `SLACK_WEBHOOK_URL` (optional for drift alerts)

High-level flow
1. User visits GitHub Pages `index.html` and requests a role.
2. Request creates a `repository_dispatch` event or opens an issue for traceability.
3. Admin approves (via issue `/approve` comment) or uses Admin Console to create `admin-provision` dispatch.
4. Provisioning workflow runs: creates Azure SP with federated credential and GCP Workload Identity Pool bindings; stores per-user per-platform secrets in repo (per-user naming)
5. Rotate workflow cleans up expired credentials daily; drift detection scans and reports/remediates.

Enterprise SSO & OIDC
- This system uses GitHub OIDC federation to mint short-lived tokens for Azure and GCP.
- You will still need one initial admin credential (stored in `AZURE_CREDENTIALS` and `GCP_SA_KEY`) to seed resource creation and create federated credentials.

Azure federated credential snippet (run once with admin rights):

az ad app create --display-name "gh-oidc-app"
APP_ID=$(az ad app show --id http://gh-oidc-app --query appId -o tsv)
az ad sp create --id $APP_ID
az rest --method POST --uri "https://graph.microsoft.com/v1.0/applications/$APP_ID/federatedIdentityCredentials" -b '{"name":"github_oidc","issuer":"https://token.actions.githubusercontent.com","subject":"repo:ACME-ENTERPRISE/landing-zone:ref:refs/heads/*","description":"GitHub OIDC federation for landing-zone"}'

GCP workload identity pool example (run once):
gcloud iam workload-identity-pools create "gh-pool" --project="$GCP_PROJECT_ID" --location="global" --display-name="GitHub Actions Pool"
gcloud iam workload-identity-pools providers create-oidc "gh-provider" --workload-identity-pool="gh-pool" --issuer-uri="https://token.actions.githubusercontent.com" --allowed-audiences="https://github.com/ACME-ENTERPRISE/landing-zone" --location="global" --project="$GCP_PROJECT_ID"

Deployment
1. Create two branches: `main` (content files, workflows) and `gh-pages` (UI files `index.html` and `admin.html`).
2. Push `gh-pages` branch to enable GitHub Pages.
3. Create the required repo secrets (see above).
4. Configure the Azure and GCP trust resources as shown above.

Troubleshooting
- If provisioning fails with Azure permission errors, verify `AZURE_CREDENTIALS` has sufficient privileges to create service principals and federated credentials.
- If GCP steps fail, ensure `GCP_SA_KEY` has `roles/iam.serviceAccountAdmin` and `roles/iam.workloadIdentityPoolAdmin`.
- For GitHub permission issues, ensure `ADMIN_GITHUB_TOKEN` has `repo` and `issues` permissions.

Testing
- Use the E2E workflow `e2e-test.yml` (in `.github/workflows`) to simulate a user request and approval cycle. This uses OIDC and admin secrets and runs in CI.

Audit and compliance
- All actions create GitHub Issues for audit trails. Drift detection creates issues for non-compliant resources and posts to Slack when configured.

Replace placeholders
- Search the repo for `ACME-ENTERPRISE` and replace with your GitHub Organization.
# Landing Zone IAM System - Complete Setup & Usage Guide

A GitHub-native infrastructure for managing Identity and Access Management (IAM) with support for Azure and GCP, featuring drift detection, enterprise SSO integration, and automated provisioning workflows.

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture](#architecture)
3. [Setup Instructions](#setup-instructions)
4. [User Portal](#user-portal)
5. [Admin Console](#admin-console)
6. [Workflow Details](#workflow-details)
7. [Enterprise Features](#enterprise-features)
8. [OIDC Configuration](#oidc-configuration)
9. [Troubleshooting](#troubleshooting)
10. [E2E Testing](#e2e-testing)

---

## Quick Start

### Prerequisites

- GitHub repository with GitHub Pages enabled
- Azure subscription with admin service principal
- GCP project with admin service account
- GitHub organization with team management enabled

### 1. Clone & Setup (5 minutes)

```bash
git clone https://github.com/YOUR-ORG/landing-zone.git
cd landing-zone
bash setup.sh YOUR-ORG
```

### 2. Configure Secrets (in GitHub repo settings)

```bash
# Azure
AZURE_CREDENTIALS: <admin-sp-json>
AZURE_SUBSCRIPTION_ID: <your-sub-id>

# GCP
GCP_SA_KEY: <admin-sa-key-json>
GCP_PROJECT_ID: <your-gcp-project>

# Admin
ADMIN_GITHUB_TOKEN: <repo-scope-pat>

# Optional
RESEND_API_KEY: <resend-api-key>
SLACK_WEBHOOK_URL: <slack-webhook>
```

### 3. Enable GitHub Pages

1. Go to Settings → Pages
2. Select "Deploy from a branch"
3. Branch: `gh-pages`, Folder: `/ (root)`
4. Save

### 4. Deploy Portal & Admin Console (30 seconds)

```bash
git checkout -b gh-pages
git push origin gh-pages
```

→ User Portal: `https://YOUR-ORG.github.io/landing-zone/`
→ Admin Console: `https://YOUR-ORG.github.io/landing-zone/admin.html`

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User Portal (GitHub Pages)               │
│  - Self-service role request                                │
│  - Enterprise SSO detection                                 │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├─ repository_dispatch(role-request)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│              provision.yml (Main Workflow)                  │
│  - Parse request                                            │
│  - Create approval issue                                    │
│  - OIDC: Create Azure SP + GCP SA                          │
│  - Store per-user secrets                                  │
│  - Send notifications                                      │
└─────────────────┬───────────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌─────────┐  ┌──────────┐  ┌──────────────┐
│ Azure   │  │   GCP    │  │  Repo        │
│ Service │  │ Service  │  │ Secrets      │
│ Principal   │ Account  │  │              │
└─────────┘  └──────────┘  └──────────────┘

┌─────────────────────────────────────────────────────────────┐
│            Admin Console (GitHub Pages)                      │
│  - User selection + role assignment                         │
│  - Custom provisioning                                      │
│  - Drift scan trigger                                       │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ├─ repository_dispatch(admin-provision)
                  │
┌─────────────────▼───────────────────────────────────────────┐
│           admin-dispatch.yml (Auto-Approve)                 │
│  - Validate admin                                           │
│  - Create issue + auto /approve                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│           rotate.yml (Daily TTL Cleanup)                    │
│  - Delete expired Azure SPs                                 │
│  - Delete expired GCP SAs                                   │
│  - Remove repository secrets                                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│        drift-detection.yml (Daily Compliance Scan)          │
│  - Compare actual vs expected state                         │
│  - Auto-remediate drift                                     │
│  - Create audit issue + alerts                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Setup Instructions

### Step 1: Azure Service Principal Setup (for OIDC)

Create an admin service principal for provisioning:

```bash
# Login as org admin
az login

# Create SP
az ad sp create-for-rbac \
  --name "landing-zone-admin" \
  --role "User Access Administrator" \
  --scopes "/subscriptions/<SUB_ID>" \
  --output json > azure-sp.json

# Store in AZURE_CREDENTIALS secret (entire JSON)
cat azure-sp.json

# Create Workload Identity Federation for GitHub OIDC
TENANT_ID=$(jq -r '.tenantId' azure-sp.json)
SUBSCRIPTION_ID=$(jq -r '.id' azure-sp.json | cut -d'/' -f3)
OBJECT_ID=$(az ad sp show \
  --id $(jq -r '.clientId' azure-sp.json) \
  --query id -o tsv)

# Create identity provider for GitHub
az identity federated-credentials create \
  --resource-group rg-landing-zone \
  --identity-name landing-zone-admin \
  --name landing-zone-github \
  --issuer https://token.actions.githubusercontent.com \
  --subject "repo:YOUR-ORG/landing-zone:ref:refs/heads/main" \
  --audiences api://AzureADTokenExchange

# Store subscription ID
AZURE_SUBSCRIPTION_ID="<YOUR-SUB-ID>"
```

### Step 2: GCP Service Account Setup (for OIDC)

```bash
# Set project
gcloud config set project YOUR-GCP-PROJECT

# Create admin service account
gcloud iam service-accounts create landing-zone-admin \
  --display-name="Landing Zone IAM Admin"

# Grant roles
gcloud projects add-iam-policy-binding YOUR-GCP-PROJECT \
  --member="serviceAccount:landing-zone-admin@YOUR-GCP-PROJECT.iam.gserviceaccount.com" \
  --role="roles/iam.securityAdmin"

# Create Workload Identity Federation
gcloud iam workload-identity-pools create "github-pool" \
  --project=YOUR-GCP-PROJECT \
  --location=global \
  --display-name="GitHub Actions"

# Configure provider
gcloud iam workload-identity-pools providers create-oidc \
  "github-provider" \
  --project=YOUR-GCP-PROJECT \
  --location=global \
  --workload-identity-pool=github-pool \
  --display-name="GitHub" \
  --attribute-mapping="google.subject=assertion.sub" \
  --issuer-uri=https://token.actions.githubusercontent.com

# Get pool resource name
POOL_RESOURCE_NAME=$(gcloud iam workload-identity-pools describe github-pool \
  --project=YOUR-GCP-PROJECT \
  --location=global \
  --format='value(name)')

# Create service account impersonation binding
gcloud iam service-accounts add-iam-policy-binding \
  landing-zone-admin@YOUR-GCP-PROJECT.iam.gserviceaccount.com \
  --project=YOUR-GCP-PROJECT \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/${POOL_RESOURCE_NAME}/attribute.repository/YOUR-ORG/landing-zone"

# Generate key and store as GCP_SA_KEY
gcloud iam service-accounts keys create /tmp/gcp-key.json \
  --iam-account=landing-zone-admin@YOUR-GCP-PROJECT.iam.gserviceaccount.com

# For non-OIDC fallback (optional)
cat /tmp/gcp-key.json
```

### Step 3: GitHub Configuration

1. **Enable GitHub Pages**: Settings → Pages → gh-pages branch
2. **Create admin team** (for console access):
   ```bash
   gh api /orgs/YOUR-ORG/teams \
     -f name='landing-zone-admins' \
     -f description='Landing Zone IAM Admins'
   ```
3. **Add team members**:
   ```bash
   gh api /orgs/YOUR-ORG/teams/landing-zone-admins/memberships/USERNAME \
     -f role='maintainer'
   ```

### Step 4: Create Required Secrets

Go to repo Settings → Secrets and variables → Actions

| Secret | Value | Required |
|--------|-------|----------|
| `AZURE_CREDENTIALS` | Full SP JSON from azure-sp.json | ✅ |
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID | ✅ |
| `GCP_SA_KEY` | Service account key JSON | ✅ |
| `GCP_PROJECT_ID` | Your GCP project ID | ✅ |
| `ADMIN_GITHUB_TOKEN` | PAT with issues:write, contents:read | ✅ |
| `RESEND_API_KEY` | (Optional) For email notifications | ❌ |
| `SLACK_WEBHOOK_URL` | (Optional) For Slack alerts | ❌ |

### Step 5: Deploy Portal & Admin Console

```bash
# Create gh-pages branch
git checkout -b gh-pages
git push origin gh-pages

# Verify Pages deployment
# Visit: https://YOUR-ORG.github.io/landing-zone/
# Visit: https://YOUR-ORG.github.io/landing-zone/admin.html
```

---

## User Portal

### Features

- **Vanilla HTML/JS**: GitHub Pages compatible, no build required
- **Role Selection**: Dropdown loaded from `roles.yml` via raw.githubusercontent.com
- **Enterprise SSO**: Auto-detects GitHub Enterprise user
- **Request Submission**: Creates `repository_dispatch` event
- **Status Tracking**: Links to approval issue in real-time

### How It Works

1. User visits: `https://YOUR-ORG.github.io/landing-zone/`
2. Portal loads roles from raw.githubusercontent.com/YOUR-ORG/landing-zone/main/roles.yml
3. User selects role + provides justification
4. Form submits to `repository_dispatch` API with GitHub token
5. `provision.yml` creates approval issue
6. User/admin comments `/approve` to trigger provisioning
7. Secrets created → Azure SP + GCP SA provisioned → User notified

### Custom Styling

The portal uses GitHub's Primer CSS design system for consistency with GitHub Enterprise:

```html
<link rel="stylesheet" href="https://primer.github.io/css/index.css">
```

For Dark Mode: Add `data-theme="dark"` to `<html>` tag

---

## Admin Console

### Access Control

The admin console validates users against GitHub organization membership:

```javascript
// Only users in 'landing-zone-admins' team can access
const response = await fetch(
  'https://api.github.com/orgs/YOUR-ORG/teams/landing-zone-admins/memberships/' + username,
  { headers: { 'Authorization': 'token ' + token } }
);
```

### Console Features

1. **User Selection**: Dropdown pre-populated from `users.yml`
2. **Role Assignment**: Predefined or custom
3. **Custom Provisioning**:
   - Azure Service Principal (subscription, role)
   - GCP Service Account (project, roles)
   - Custom secrets (name, value, scope)
4. **Bulk Operations**: Provision multiple users
5. **Drift Controls**: Trigger immediate drift scans
6. **Audit Trail**: View history of all provisioning actions

### Provisioning Workflow

```
Admin selects user + role
        ↓
Form validation (MFA check, permissions)
        ↓
repository_dispatch(admin-provision) event
        ↓
admin-dispatch.yml workflow triggered
        ↓
Validate admin in org/teams/admins
        ↓
Create GitHub issue (auto-labeled, assigned)
        ↓
Add `/approve` comment (auto-commented by bot)
        ↓
provision.yml runs approval handler
        ↓
Azure SP creation (OIDC federation)
        ↓
GCP SA creation (Workload Identity)
        ↓
Repository secrets stored (per-user scoped)
        ↓
Email notification sent (optional)
        ↓
Issue closed as completed
```

---

## Workflow Details

### 1. provision.yml - Main Provisioning Workflow

**Triggers:**
- User form submission: `repository_dispatch(role-request)`
- Admin console: `repository_dispatch(admin-provision)`
- Manual approval comment: `issue_comment(/approve)`

**Steps:**

1. **Parse Payload**
   - Extract username, role, justification from dispatch or issue
   - Validate against `roles.yml`
   - Check user status in `users.yml`

2. **Create Approval Issue**
   - Title: `[ACCESS-REQUEST] @username → devops-full`
   - Body: User info, role details, TTL
   - Labels: `access-request`, `pending-approval`
   - Assign to: `landing-zone-admins` team

3. **Wait for Approval** (24-hour timeout)
   - Listen for `/approve` comment
   - Validate approver is in `landing-zone-admins` team
   - If timeout/approved: proceed to provisioning

4. **Azure SP Provisioning** (OIDC)
   ```bash
   # Using federated credential (no secrets stored)
   az ad sp create-for-rbac \
     --name "gh-${USERNAME}-${ROLE}" \
     --role "Contributor" \
     --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}" \
     --create-cert --years 1 \
     --cert ${CERT_PATH}
   
   # Create federated credential for GitHub OIDC
   az ad app federated-credential create \
     --id ${APP_ID} \
     --parameters '{...}'
   ```

5. **GCP SA Provisioning** (Workload Identity)
   ```bash
   # Create service account
   gcloud iam service-accounts create ${USERNAME}-${ROLE} \
     --display-name="${USERNAME} (${ROLE})"
   
   # Bind to Workload Identity Pool
   gcloud iam service-accounts add-iam-policy-binding \
     ${SA_EMAIL} \
     --role=roles/iam.workloadIdentityUser \
     --member="principalSet://iam.googleapis.com/projects/${PROJECT}/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR-ORG/landing-zone"
   ```

6. **Store Repository Secrets**
   ```bash
   # Per-user scoped secrets
   gh secret set ${USERNAME}-AZURE_CLIENT_ID \
     --body "${CLIENT_ID}"
   gh secret set ${USERNAME}-GCP_SA_EMAIL \
     --body "${SA_EMAIL}"
   ```

7. **Send Notifications**
   - GitHub Issue: Approval complete, links to resources
   - Email (optional): User notified of access grant, TTL date
   - Slack (optional): Alert to `#security-access-log` channel

8. **Update User Status**
   - Patch `users.yml`: status=active, last_provisioned, expiration_date
   - Create audit issue: `[AUDIT] Provisioned @username → devops-full`

---

### 2. admin-dispatch.yml - Admin Console Handler

**Trigger:** `repository_dispatch(admin-provision)` from admin console

**Flow:**
1. Validate requester is in `landing-zone-admins` team
2. Parse: username, role, custom settings
3. Create GitHub issue with full details
4. Auto-comment `/approve` as bot
5. Trigger `provision.yml` (skips approval wait)

**Example Dispatch Payload:**
```json
{
  "event_type": "admin-provision",
  "client_payload": {
    "username": "alice-devops",
    "role": "devops-full",
    "provisioning_type": "azure_sp",
    "azure_scope": "subscription",
    "ttl_days": 90,
    "requested_by": "eve-admin",
    "timestamp": "2025-12-08T10:30:00Z"
  }
}
```

---

### 3. rotate.yml - Daily TTL Cleanup

**Schedule:** Daily at 2:00 AM UTC

**Actions:**

1. **Parse User Expiration Dates** from `users.yml`
2. **Delete Expired Azure Service Principals**
   ```bash
   az ad sp delete --id ${OBJECT_ID}
   ```
3. **Delete Expired GCP Service Accounts**
   ```bash
   gcloud iam service-accounts delete ${SA_EMAIL} --quiet
   ```
4. **Remove Repository Secrets**
   ```bash
   gh secret remove ${USERNAME}-AZURE_CLIENT_ID
   gh secret remove ${USERNAME}-GCP_SA_EMAIL
   ```
5. **Update User Status** in `users.yml`: status=expired
6. **Create Audit Issue**: `[ROTATION] Expired credentials removed for @username`
7. **Send Notification**: Email user about access revocation

---

### 4. drift-detection.yml - Daily Compliance Scan

**Schedule:** Daily at 3:00 AM UTC + Manual trigger via `/drift-scan` comment

**Validation Steps:**

1. **Load Expected State** from `drift-policy.json`
2. **Azure Compliance Check**
   ```bash
   # Get all SPs created by landing-zone
   az ad sp list --filter "displayName startswith 'gh-'" --output json
   
   # For each: validate role, expiration, federation enabled
   az ad sp show --id ${OBJECT_ID}
   az ad app federated-credential list --id ${APP_ID}
   ```
3. **GCP Compliance Check**
   ```bash
   # Get all SAs created by landing-zone
   gcloud iam service-accounts list --filter="displayName:landing-zone"
   
   # For each: validate roles, workload identity binding
   gcloud projects get-iam-policy ${PROJECT} \
     --flatten="bindings[].members" \
     --format="table(bindings.role)" \
     --filter="bindings.members:serviceAccount:*"
   ```
4. **Repository Secrets Validation**
   ```bash
   # List all secrets
   gh secret list --json name,updatedAt -q '.[] | select(.name | startswith("USERNAME-"))'
   ```
5. **Expiration Date Validation**
   ```bash
   # Compare dates from users.yml vs Azure/GCP metadata
   # Flag if discrepancies found
   ```

**Auto-Remediation:**

- **Missing Secrets**: Recreate from Azure/GCP metadata
- **Expired Principals**: Delete immediately (if past grace period)
- **Missing Federation**: Re-establish OIDC trust
- **Unauthorized Role Changes**: Revert to expected role

**Reporting:**

Creates GitHub Issue with:
- ✅ Passed checks
- ⚠️ Warnings (days until expiration)
- ❌ Failed checks (policy violations)
- 🔧 Auto-remediation actions taken
- 📊 Summary statistics

Example Output:
```markdown
# Drift Detection Report - 2025-12-08

## Summary
- Total principals: 4
- Healthy: 3 ✅
- Warnings: 1 ⚠️
- Failed: 0 ❌

## Warnings
- alice-devops: Expires in 23 days (2026-01-01)
- bob-devops: Azure federated credential not validated

## Auto-Remediation Taken
- Recreated bob-devops Azure federated credential
- No principals deleted

## SLA Status
- Detection time: 45 seconds
- Remediation time: 28 seconds
- All within SLA targets ✅
```

---

## Enterprise Features

### 1. Enterprise SSO Integration (SAML/EMU)

The system is pre-configured for GitHub Enterprise Cloud with SAML/EMU:

**User Portal Detection:**
```javascript
// Auto-detect Enterprise user from GitHub session
const username = document.querySelector('[data-github-actor]')?.dataset.githubActor
  || sessionStorage.getItem('github_actor')
  || prompt('GitHub username');
```

**EMU Considerations:**
- Usernames are automatically managed by your IdP (Okta, Azure AD, etc.)
- The system reads `github.actor` from SAML assertions
- No manual username entry needed in Enterprise environments

### 2. SCIM Provisioning Integration

To integrate with your IdP's SCIM provisioning:

1. **Azure AD SCIM (Enterprise Synchronized Users)**

   Add this logic to your custom provisioning workflows:

   ```bash
   # Sync user attributes from Azure AD
   USER_ID=$(az ad user show --id ${GITHUB_USERNAME} --query id -o tsv)
   
   # Verify user exists before provisioning
   if [[ -z "$USER_ID" ]]; then
     echo "User not found in Azure AD - SCIM sync may still be pending"
     exit 1
   fi
   ```

2. **Okta SCIM**

   Update `users.yml` by pulling from Okta API:

   ```bash
   # In rotate.yml, add sync step
   curl -X GET https://YOUR-OKTA-DOMAIN/api/v1/users \
     -H "Authorization: Bearer $OKTA_API_TOKEN" | \
     jq '.[] | {username: .profile.login, email: .profile.email}' > /tmp/okta-users.json
   ```

### 3. Multi-Factor Authentication (MFA)

**Enforcement by Role:**

Edit `roles.yml` to enforce MFA:
```yaml
devops-full:
  requires_mfa: true
  mfa_grace_period_days: 7
reader:
  requires_mfa: false
```

**In Workflows:**

```bash
# Check MFA status
MFA_ENABLED=$(az ad user show --id ${USER_ID} --query strongAuthenticationPhoneNumber -o tsv)
if [[ $ROLE == "devops-full" ]] && [[ -z "$MFA_ENABLED" ]]; then
  echo "MFA required for devops-full role"
  exit 1
fi
```

### 4. Audit & Compliance

**Automatic Audit Trail:**

Every provisioning action creates a GitHub Issue:
- `[AUDIT]` prefix for all audit logs
- Labels: `iam-audit`, `access-request`, `approval`, `provisioning`, `rotation`, `drift`
- Full action details: who, what, when, changes made

**Compliance Reports:**

Generate quarterly compliance reports:

```bash
# List all audit issues from past 90 days
gh issue list --label iam-audit \
  --search "created:>$(date -d '90 days ago' +%Y-%m-%d)" \
  --format table
```

### 5. Integration with External Systems

**Webhook Integration** (for ITSM, ticketing systems):

```bash
# In provision.yml, add this step to notify external systems
curl -X POST https://your-itsm-system.com/api/tickets \
  -H "Authorization: Bearer $ITSM_TOKEN" \
  -d @- << EOF
{
  "title": "Access Provisioned: $USERNAME → $ROLE",
  "user": "$USERNAME",
  "role": "$ROLE",
  "expiration": "$EXPIRATION_DATE",
  "issue_url": "https://github.com/YOUR-ORG/landing-zone/issues/123"
}
EOF
```

**Slack Integration** (already in workflows):

```bash
# Send detailed Slack notification
curl -X POST $SLACK_WEBHOOK_URL \
  -d @- << EOF
{
  "text": ":lock: New Access Provisioned",
  "attachments": [{
    "color": "good",
    "fields": [
      {"title": "User", "value": "$USERNAME"},
      {"title": "Role", "value": "$ROLE"},
      {"title": "Expires", "value": "$EXPIRATION_DATE"},
      {"title": "Issue", "value": "$ISSUE_URL"}
    ]
  }]
}
EOF
```

---

## OIDC Configuration

### Azure AD OIDC (Workload Identity Federation)

The workflows use OIDC to authenticate without storing long-lived secrets.

**How It Works:**

1. GitHub Actions requests a JWT token from `https://token.actions.githubusercontent.com`
2. Token includes claims: repo, ref, actor, subject
3. Azure AD validates token signature
4. If valid, Azure AD returns Azure AD access token
5. Workflow uses access token to call Azure API

**In Your Workflow:**

```yaml
jobs:
  provision:
    runs-on: ubuntu-latest
    permissions:
      id-token: write        # Allow GitHub to request OIDC token
      issues: write          # Create issues
      contents: read         # Read roles.yml, users.yml
    steps:
      - uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
          # NO client-secret needed! OIDC handles authentication
      
      - run: az ad sp create-for-rbac ...
```

**Setup Checklist:**

- [x] Azure AD app registration created
- [x] Federated credential configured:
  - Issuer: `https://token.actions.githubusercontent.com`
  - Subject: `repo:YOUR-ORG/landing-zone:ref:refs/heads/main`
  - Audience: `api://AzureADTokenExchange`
- [x] Service principal has IAM permissions
- [x] `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` stored as repo secrets

### GCP Workload Identity Federation

**How It Works:**

1. GitHub Actions requests JWT from `https://token.actions.githubusercontent.com`
2. GCP Workload Identity Pool validates token
3. Pool exchanges GitHub JWT for GCP access token
4. Workflow uses access token to call GCP APIs

**In Your Workflow:**

```yaml
steps:
  - uses: google-github-actions/auth@v1
    with:
      workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
      service_account_email: landing-zone-admin@YOUR-GCP-PROJECT.iam.gserviceaccount.com
      # NO service account key needed! Workload Identity handles auth
  
  - uses: google-github-actions/setup-gcloud@v1
  
  - run: gcloud iam service-accounts create ...
```

**Setup Checklist:**

- [x] Workload Identity Pool created
- [x] GitHub OIDC provider configured:
  - Issuer: `https://token.actions.githubusercontent.com`
  - Attribute mapping: `google.subject=assertion.sub`
- [x] Service account impersonation IAM binding created
- [x] `WIF_PROVIDER` stored as repo secret

---

## Troubleshooting

### Issue: "401 Unauthorized" when accessing admin console

**Cause:** Not member of `landing-zone-admins` team

**Fix:**
```bash
# Add user to admin team
gh api /orgs/YOUR-ORG/teams/landing-zone-admins/memberships/USERNAME \
  -f role='maintainer'

# Verify
gh api /orgs/YOUR-ORG/teams/landing-zone-admins/members
```

### Issue: Azure SP creation fails with "Insufficient privileges"

**Cause:** Service principal doesn't have User Access Administrator role

**Fix:**
```bash
# Re-run setup with elevated account
az ad sp create-for-rbac \
  --name "landing-zone-admin" \
  --role "User Access Administrator" \
  --scopes "/subscriptions/YOUR-SUB-ID"
```

### Issue: Drift detection reports "Missing secrets"

**Cause:** Secrets not created or were deleted

**Fix:**
1. Check if expiration date passed: `grep expiration_date users.yml`
2. If not expired, manually re-run provision workflow:
   ```bash
   gh workflow run provision.yml \
     -f username=alice-devops \
     -f action=recreate-secrets
   ```
3. Verify secrets exist:
   ```bash
   gh secret list --json name
   ```

### Issue: "Timeout waiting for approval" in provision workflow

**Cause:** No `/approve` comment within 24 hours

**Fix:**
```bash
# Find the issue
gh issue list --label access-request --state open

# Manually approve
gh issue comment ISSUE_NUM --body "/approve"

# Or close and restart
gh issue close ISSUE_NUM
# User resubmits form to retry
```

### Issue: GCP service account not created

**Cause:** Workload Identity Provider not configured or wrong project

**Fix:**
1. Verify WIF provider exists:
   ```bash
   gcloud iam workload-identity-pools providers list \
     --workload-identity-pool=github-pool \
     --location=global
   ```
2. Check service account has IAM permissions:
   ```bash
   gcloud projects get-iam-policy YOUR-GCP-PROJECT \
     --flatten="bindings[].members" \
     --filter="bindings.members:landing-zone-admin@*"
   ```
3. Verify attribute mapping:
   ```bash
   gcloud iam workload-identity-pools providers describe github-provider \
     --workload-identity-pool=github-pool \
     --location=global \
     --format=json | jq .attributeMapping
   ```

### Issue: Email notifications not sending

**Cause:** `RESEND_API_KEY` not configured or invalid

**Fix:**
1. Generate API key at https://resend.com/api-keys
2. Store in repo: `gh secret set RESEND_API_KEY`
3. Verify in workflow logs (should not print key, only "✅ Notification sent")

### Issue: Drift detection shows false positives

**Cause:** `drift-policy.json` out of sync with actual state

**Fix:**
1. Run drift detection to see actual state:
   ```bash
   gh workflow run drift-detection.yml
   ```
2. Comment on issue to view detailed report
3. Update `drift-policy.json` with correct state:
   ```bash
   # Export actual state
   az ad sp list --filter "displayName startswith 'gh-'" > actual-state.json
   # Compare and update drift-policy.json
   ```

---

## E2E Testing

### Test Scenario 1: User Self-Service Request

```bash
# 1. Access portal
open https://YOUR-ORG.github.io/landing-zone/

# 2. Fill form
# Username: test-user-123
# Role: reader
# Justification: "Testing IAM system"
# Submit

# 3. Wait for issue creation (30-60 seconds)
gh issue list --label access-request --state open

# 4. Find issue number
ISSUE_NUM=$(gh issue list --label access-request --state open --json number -q '.[0].number')

# 5. Approve
gh issue comment $ISSUE_NUM --body "/approve"

# 6. Verify secrets created (60 seconds)
gh secret list --json name | grep test-user-123

# 7. Verify Azure SP created
az ad sp list --filter "displayName eq 'gh-test-user-123-reader'"

# 8. Verify GCP SA created
gcloud iam service-accounts list --filter="displayName:test-user-123"
```

**Expected Output:**
- Issue created with correct details ✅
- Secrets: `test-user-123-AZURE_CLIENT_ID`, `test-user-123-GCP_SA_EMAIL` ✅
- Azure SP with federated credential ✅
- GCP SA with workload identity binding ✅

### Test Scenario 2: Admin Console Provisioning

```bash
# 1. Access admin console
open https://YOUR-ORG.github.io/landing-zone/admin.html

# 2. Login with admin account (eve-admin)

# 3. Select user: bob-devops
# 4. Select role: devops-limited
# 5. Click "Provision Now"

# 6. Verify auto-created issue
gh issue list --label access-request --state open --json title,number

# 7. Verify auto-approval (issue should already be approved)
ISSUE_NUM=$(gh issue list --label access-request --state open --json number -q '.[0].number')
gh issue view $ISSUE_NUM --json comments

# 8. Verify provisioning completed within 2 minutes
sleep 120
gh secret list --json name | grep bob-devops-AZURE
```

**Expected Output:**
- Issue auto-created with admin label ✅
- Auto-approval comment visible ✅
- Secrets created within 2 minutes ✅

### Test Scenario 3: Drift Detection

```bash
# 1. Trigger drift scan
gh api repos/YOUR-ORG/landing-zone/issues \
  -f state=open \
  -f body="/drift-scan"

# Alternative: Wait for daily cron (3 AM UTC)

# 2. Monitor workflow run
gh run list --workflow=drift-detection.yml --limit=1

# 3. Wait for completion (2-3 minutes)
sleep 180

# 4. Check drift report issue
gh issue list --label iam-audit --search "Drift Detection" --state open

# 5. View detailed report
ISSUE_NUM=$(gh issue list --label iam-audit --search "Drift Detection" --state open --json number -q '.[0].number')
gh issue view $ISSUE_NUM
```

**Expected Output:**
- Drift report created within SLA (2 minutes) ✅
- All current principals listed ✅
- Compliance status: ✅ (unless intentional drift)
- Auto-remediation actions (if any) documented ✅

### Test Scenario 4: TTL Rotation

```bash
# 1. Modify users.yml to set past expiration
# Change expiration_date for test-user-123 to yesterday

# 2. Trigger rotation workflow (or wait for 2 AM UTC cron)
gh workflow run rotate.yml

# 3. Monitor workflow
gh run list --workflow=rotate.yml --limit=1 --status=in_progress

# 4. Wait for completion (1-2 minutes)
sleep 120

# 5. Verify resources deleted
gh secret list --json name | grep -c test-user-123
# Should return: 0

# 6. Verify Azure SP deleted
az ad sp list --filter "displayName eq 'gh-test-user-123-reader'" --output json | jq length
# Should return: 0

# 7. Verify audit issue created
gh issue list --label iam-audit --search "Expired credentials removed"
```

**Expected Output:**
- Repository secrets removed ✅
- Azure SP deleted ✅
- GCP SA deleted ✅
- Audit issue created with details ✅

### Test Scenario 5: Enterprise SSO

```bash
# 1. Setup GitHub Enterprise SAML (in org settings)
# 2. Link your IdP (Okta, Azure AD, etc.)
# 3. Create test user through IdP

# 4. Access user portal
open https://YOUR-ORG.github.io/landing-zone/

# 5. Verify system detects enterprise user
# Open browser console and check:
console.log(document.querySelector('[data-github-actor]')?.dataset.githubActor)
# Should print: IdP-managed username (e.g., 'alice@company.com')

# 6. Form should be pre-populated with SSO username
# 7. Submit request normally

# 8. Verify in provision.yml logs that `github.actor` is from SAML assertion
gh run view <RUN_ID> --log | grep "github.actor"
```

**Expected Output:**
- User identified by SAML assertion ✅
- No manual username entry required ✅
- All provisioning completed with SSO user ✅

---

## Production Checklist

Before deploying to production:

- [ ] Replace all `YOUR-ORG` placeholders with actual organization
- [ ] Configure all required secrets in GitHub
- [ ] Test user portal with real user (in staging)
- [ ] Test admin console with real admin (in staging)
- [ ] Verify email notifications working (if using RESEND_API_KEY)
- [ ] Verify Slack notifications working (if using SLACK_WEBHOOK_URL)
- [ ] Configure org team: `landing-zone-admins`
- [ ] Enable GitHub Pages on main branch (gh-pages)
- [ ] Run E2E test scenarios
- [ ] Set up monitoring on workflow failures
- [ ] Document any custom integrations (ITSM, ticketing, etc.)
- [ ] Brief team on approval process
- [ ] Set retention policy for audit issues (90 days)

---

## Support & Contributing

For issues, feature requests, or contributions:

1. Create GitHub Issue with detailed description
2. Tag with appropriate label: `bug`, `enhancement`, `documentation`
3. Include workflow logs if applicable: `gh run view <RUN_ID> --log`

---

**Last Updated:** December 8, 2025
**Maintainers:** Landing Zone Team
**License:** MIT
