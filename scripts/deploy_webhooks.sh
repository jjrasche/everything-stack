#!/bin/bash
# # Webhook Deployment Script
#
# ## What it does
# Deploys Supabase Edge Functions for webhook handling.
# Configures webhook URLs with external services (Teams, GitLab, etc.).
#
# ## Usage
# ```bash
# ./scripts/deploy_webhooks.sh
# ```
#
# ## Prerequisites
# - Supabase CLI installed: `npm install -g supabase`
# - Supabase project linked: `supabase link --project-ref YOUR_PROJECT_REF`
# - Environment variables configured in `.env`
#
# ## Environment Variables Required
# - SUPABASE_PROJECT_REF: Your Supabase project reference ID
# - SUPABASE_ACCESS_TOKEN: Your Supabase access token
# - TEAMS_WEBHOOK_SECRET: Secret for verifying Teams webhooks (optional)
# - GITLAB_WEBHOOK_SECRET: Secret for verifying GitLab webhooks (optional)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Webhook Deployment Script${NC}"
echo ""

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI not found${NC}"
    echo "Install with: npm install -g supabase"
    exit 1
fi

# Check if project is linked
if [ ! -f ".supabase/config.toml" ]; then
    echo -e "${RED}❌ Supabase project not linked${NC}"
    echo "Link your project with: supabase link --project-ref YOUR_PROJECT_REF"
    exit 1
fi

# Load environment variables from .env if it exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}📄 Loading environment variables from .env${NC}"
    export $(cat .env | grep -v '^#' | xargs)
fi

# Verify required environment variables
if [ -z "$SUPABASE_PROJECT_REF" ]; then
    echo -e "${YELLOW}⚠️  SUPABASE_PROJECT_REF not set, using linked project${NC}"
fi

# ============ Deploy Edge Functions ============

echo -e "${GREEN}📦 Deploying Edge Functions...${NC}"

# Deploy Teams webhook handler
if [ -d "supabase/functions/teams-webhook" ]; then
    echo -e "${YELLOW}  → Deploying teams-webhook...${NC}"
    supabase functions deploy teams-webhook --no-verify-jwt
    echo -e "${GREEN}  ✅ teams-webhook deployed${NC}"
else
    echo -e "${YELLOW}  ⚠️  supabase/functions/teams-webhook not found, skipping${NC}"
fi

# Deploy GitLab webhook handler
if [ -d "supabase/functions/gitlab-webhook" ]; then
    echo -e "${YELLOW}  → Deploying gitlab-webhook...${NC}"
    supabase functions deploy gitlab-webhook --no-verify-jwt
    echo -e "${GREEN}  ✅ gitlab-webhook deployed${NC}"
else
    echo -e "${YELLOW}  ⚠️  supabase/functions/gitlab-webhook not found, skipping${NC}"
fi

# Deploy generic webhook handler (catches all other providers)
if [ -d "supabase/functions/generic-webhook" ]; then
    echo -e "${YELLOW}  → Deploying generic-webhook...${NC}"
    supabase functions deploy generic-webhook --no-verify-jwt
    echo -e "${GREEN}  ✅ generic-webhook deployed${NC}"
else
    echo -e "${YELLOW}  ⚠️  supabase/functions/generic-webhook not found, skipping${NC}"
fi

echo ""

# ============ Display Webhook URLs ============

echo -e "${GREEN}📡 Webhook URLs${NC}"
echo ""

# Get project URL from config
SUPABASE_URL=$(grep 'api_url' .supabase/config.toml | cut -d '"' -f 2 | head -1)

if [ -z "$SUPABASE_URL" ]; then
    echo -e "${YELLOW}⚠️  Could not determine Supabase URL from config${NC}"
    echo -e "Webhook URLs will be: https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/<function-name>"
else
    echo -e "Teams webhook URL:"
    echo -e "  ${GREEN}${SUPABASE_URL}/functions/v1/teams-webhook${NC}"
    echo ""
    echo -e "GitLab webhook URL:"
    echo -e "  ${GREEN}${SUPABASE_URL}/functions/v1/gitlab-webhook${NC}"
    echo ""
    echo -e "Generic webhook URL:"
    echo -e "  ${GREEN}${SUPABASE_URL}/functions/v1/generic-webhook${NC}"
    echo ""
fi

# ============ Configuration Instructions ============

echo -e "${GREEN}⚙️  Configuration Instructions${NC}"
echo ""

echo -e "1. Configure webhook URLs in your external services:"
echo -e "   - Teams: Use the teams-webhook URL above"
echo -e "   - GitLab: Use the gitlab-webhook URL above"
echo -e "   - Other services: Use the generic-webhook URL above"
echo ""

echo -e "2. Set webhook secrets (optional but recommended):"
echo -e "   supabase secrets set TEAMS_WEBHOOK_SECRET=<your-secret>"
echo -e "   supabase secrets set GITLAB_WEBHOOK_SECRET=<your-secret>"
echo ""

echo -e "3. Verify webhook signatures in your Edge Functions for security"
echo ""

echo -e "${GREEN}✅ Deployment complete!${NC}"
