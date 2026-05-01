#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# provision.sh — Azure infrastructure for daily-briefing Container Apps Jobs
#
# Usage:
#   bash azure/provision.sh
#
# Requirements:
#   - az CLI logged in: az login
#   - Correct subscription set (script sets it automatically)
#   - If ghcr.io image is private, set GHCR_PAT env var before running:
#     export GHCR_PAT=<GitHub PAT with read:packages scope>
#
# After running, complete the manual steps printed at the end.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SUBSCRIPTION="4fbd385d-d49d-44e9-989f-cb65baf71921"
LOCATION="uksouth"
RG="rg-briefing"
ACE="ace-briefing"
FILE_SHARE="briefing-data"
IMAGE="ghcr.io/gitinq/briefing:latest"

# UTC cron expressions — Container Apps does not support CRON_TZ.
# Winter (GMT = UTC+0): 08:00 Mon-Thu = "0 8 * * 1-4", Fri 06:00 = "0 6 * * 5"
# Summer (BST = UTC+1): 08:00 Mon-Thu = "0 7 * * 1-4", Fri 06:00 = "0 5 * * 5"
# Starting with winter (GMT) schedule. Update via /briefing page when DST changes.
CRON_WEEKDAY="0 8 * * 1-4"
CRON_FRIDAY="0 6 * * 5"

# Optional: GitHub PAT for private ghcr.io image (leave empty if image is public)
GHCR_PAT="${GHCR_PAT:-}"

# API key for automated briefing runner to read notes from /api/briefing-notes
# Must match the BRIEFING_API_KEY SWA app setting on inqltd-web.
# Set before running: export BRIEFING_API_KEY=<value>
BRIEFING_API_KEY="${BRIEFING_API_KEY:-}"

# ── Set subscription ──────────────────────────────────────────────────────────
echo "Setting subscription to $SUBSCRIPTION..."
az account set --subscription "$SUBSCRIPTION"

# ── Resource group ────────────────────────────────────────────────────────────
echo "Creating resource group $RG in $LOCATION..."
az group create --name "$RG" --location "$LOCATION" --output none

# ── Storage account + file share ──────────────────────────────────────────────
# Storage account name: 3-24 chars, globally unique, lowercase alphanumeric
SA_NAME="stbriefing$(date +%s | tail -c 5)"
echo "Creating storage account $SA_NAME..."
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --output none

STORAGE_KEY=$(az storage account keys list \
  --resource-group "$RG" \
  --account-name "$SA_NAME" \
  --query "[0].value" -o tsv)

echo "Creating file share $FILE_SHARE..."
az storage share create \
  --name "$FILE_SHARE" \
  --account-name "$SA_NAME" \
  --account-key "$STORAGE_KEY" \
  --output none

# ── Container Apps Environment ────────────────────────────────────────────────
echo "Creating Container Apps Environment $ACE..."
az containerapp env create \
  --name "$ACE" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --output none

echo "Linking file share to Container Apps Environment..."
az containerapp env storage set \
  --name "$ACE" \
  --resource-group "$RG" \
  --storage-name "briefing-data" \
  --azure-file-account-name "$SA_NAME" \
  --azure-file-account-key "$STORAGE_KEY" \
  --azure-file-share-name "$FILE_SHARE" \
  --access-mode ReadWrite \
  --output none

ACE_ID=$(az containerapp env show \
  --name "$ACE" \
  --resource-group "$RG" \
  --query "id" -o tsv)

# ── Container Apps Jobs ───────────────────────────────────────────────────────
create_job() {
  local JOB_NAME="$1"
  local CRON="$2"
  local YAML_FILE
  YAML_FILE=$(mktemp /tmp/job_XXXXXX.yaml)

  # Registry block — only included if GHCR_PAT is set
  if [ -n "$GHCR_PAT" ]; then
    REGISTRY_SECTION=$(printf '    secrets:\n      - name: ghcr-pat\n        value: "%s"\n    registries:\n      - server: ghcr.io\n        username: gitinq\n        passwordSecretRef: ghcr-pat' "$GHCR_PAT")
  else
    REGISTRY_SECTION=""
  fi

  ENV_VARS=""
  if [ -n "$BRIEFING_API_KEY" ]; then
    ENV_VARS="        env:
          - name: BRIEFING_API_KEY
            value: \"${BRIEFING_API_KEY}\""
  fi

  cat > "$YAML_FILE" <<YAML
properties:
  environmentId: ${ACE_ID}
  configuration:
    triggerType: Schedule
    scheduleTriggerConfig:
      cronExpression: "${CRON}"
      parallelism: 1
      replicaCompletionCount: 1
    replicaTimeout: 600
    replicaRetryLimit: 1
${REGISTRY_SECTION}
  template:
    containers:
      - name: briefing
        image: ${IMAGE}
        resources:
          cpu: 0.5
          memory: 1Gi
${ENV_VARS}
        volumeMounts:
          - volumeName: claude-data
            mountPath: /home/briefing/.claude
    volumes:
      - name: claude-data
        storageType: AzureFile
        storageName: briefing-data
YAML

  echo "Creating Container Apps Job $JOB_NAME ($CRON UTC)..."
  az containerapp job create \
    --name "$JOB_NAME" \
    --resource-group "$RG" \
    --yaml "$YAML_FILE" \
    --output none

  rm -f "$YAML_FILE"
}

create_job "briefing-weekday" "$CRON_WEEKDAY"
create_job "briefing-friday" "$CRON_FRIDAY"

# ── Service Principal permissions ─────────────────────────────────────────────
# The web /briefing page uses the existing SWA service principal (AZURE_CLIENT_ID)
# to manage job schedules and trigger runs. Grant it Contributor on rg-briefing.
# Find the SP object ID with:
#   az ad sp show --id <AZURE_CLIENT_ID from SWA app settings> --query id -o tsv

echo ""
echo "Skipping SP role assignment — run this manually after provisioning:"
echo ""
echo "  SP_OID=\$(az ad sp show --id <AZURE_CLIENT_ID_FROM_SWA> --query id -o tsv)"
echo "  az role assignment create \\"
echo "    --assignee \"\$SP_OID\" \\"
echo "    --role Contributor \\"
echo "    --scope /subscriptions/${SUBSCRIPTION}/resourceGroups/${RG}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  Provisioning complete!"
echo ""
echo "  Resource group:     $RG"
echo "  Storage account:    $SA_NAME"
echo "  File share:         $FILE_SHARE"
echo "  Container Apps Env: $ACE"
echo "  Job (Mon-Thu):      briefing-weekday  [$CRON_WEEKDAY UTC]"
echo "  Job (Fri):          briefing-friday   [$CRON_FRIDAY UTC]"
echo ""
echo "  MANUAL STEPS TO COMPLETE:"
echo ""
echo "  1. Make the ghcr.io/gitinq/briefing package public:"
echo "     GitHub > gitinq org > Packages > briefing > Change visibility > Public"
echo "     (Or re-run with GHCR_PAT set if keeping it private)"
echo ""
echo "  2. Upload credentials to the File Share:"
echo "     Azure Portal > Storage accounts > $SA_NAME > File shares > $FILE_SHARE"
echo "     Upload these files from Windows .claude directory:"
echo "       .credentials.json   — Claude.ai OAuth token"
echo "       settings.json       — MCP config (Slack token, Google OAuth paths)"
echo "       Any Google OAuth .json files referenced in settings.json"
echo ""
echo "  3. Grant SP permissions on $RG (see command above)"
echo ""
echo "  4. Test a manual run:"
echo "     az containerapp job start --name briefing-weekday --resource-group $RG"
echo ""
echo "  5. Watch the execution:"
echo "     az containerapp job execution list --name briefing-weekday --resource-group $RG"
echo ""
echo "  6. If DST is active (summer/BST), update schedule via /briefing page:"
echo "     Mon-Thu: 07:00 UTC = 08:00 BST"
echo "     Fri:     05:00 UTC = 06:00 BST"
echo "═══════════════════════════════════════════════════════════════════════"
