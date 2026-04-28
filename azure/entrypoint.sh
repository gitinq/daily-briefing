#!/bin/bash
# Entrypoint for Azure Container Apps Job.
# Runs once, sends the daily briefing, then exits.
set -euo pipefail

TASK="daily-briefing"
REPO_URL="https://github.com/gitinq/daily-briefing.git"
TASK_DIR="/home/briefing/tasks/${TASK}"
LOG_FILE="/var/log/${TASK}.log"
SLACK_CHANNEL="C0ASTJ537R8"

on_error() {
  local msg="[azure-briefing] Task \`${TASK}\` FAILED at $(date -Iseconds)"
  echo "$msg" | tee -a "${LOG_FILE}"
  if [ -n "${SLACK_BOT_TOKEN:-}" ]; then
    curl -s -X POST https://slack.com/api/chat.postMessage \
      -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "{\"channel\":\"${SLACK_CHANNEL}\",\"text\":\"${msg}\"}" > /dev/null || true
  fi
  exit 1
}
trap on_error ERR

# Fix ownership of mounted .claude directory (File Share is mounted by root)
if [ -d /home/briefing/.claude ]; then
  chown -R briefing:briefing /home/briefing/.claude 2>/dev/null || true
fi

# Pull latest prompt — clone on first run, pull on subsequent runs
mkdir -p /home/briefing/tasks
chown briefing:briefing /home/briefing/tasks

if [ -d "${TASK_DIR}/.git" ]; then
  echo "[$(date -Iseconds)] Pulling latest prompt..."
  su - briefing -c "HOME=/home/briefing GIT_TERMINAL_PROMPT=0 git -C '${TASK_DIR}' pull --quiet"
else
  echo "[$(date -Iseconds)] Cloning daily-briefing repo..."
  su - briefing -c "HOME=/home/briefing GIT_TERMINAL_PROMPT=0 git clone --depth=1 '${REPO_URL}' '${TASK_DIR}'"
fi

PROMPT_FILE="${TASK_DIR}/prompt.md"
if [ ! -f "${PROMPT_FILE}" ]; then
  echo "[$(date -Iseconds)] ERROR: prompt file not found: ${PROMPT_FILE}"
  exit 1
fi

# Verify claude auth before running
echo "[$(date -Iseconds)] Checking claude auth..."
if ! su - briefing -c "HOME=/home/briefing claude auth status > /dev/null 2>&1"; then
  echo "[$(date -Iseconds)] ERROR: claude auth invalid or expired — upload fresh .credentials.json to File Share"
  exit 1
fi
echo "[$(date -Iseconds)] Auth OK. Starting ${TASK}..."

TMPFILE=$(mktemp /tmp/briefing_XXXXXX.md)
cp "${PROMPT_FILE}" "${TMPFILE}"
chmod 644 "${TMPFILE}"
BRIEFING_TEXT_FILE="/home/briefing/latest-briefing-text.txt"

run_claude() {
  # Clear the txt file before each attempt so we can tell if Claude wrote it
  rm -f "${BRIEFING_TEXT_FILE}"
  su - briefing -c \
    "HOME=/home/briefing claude --dangerously-skip-permissions -p \"\$(cat '${TMPFILE}')\"" \
    2>&1 | tee -a "${LOG_FILE}"
}

run_claude

# If Claude exited 0 but didn't write the briefing text, MCP connectors likely
# failed to load at session startup (known intermittent issue). Retry once.
if [ ! -s "${BRIEFING_TEXT_FILE}" ]; then
  echo "[$(date -Iseconds)] Briefing text not written — MCP connectors may have failed to load. Retrying in 30s..."
  sleep 30
  run_claude
fi

rm -f "${TMPFILE}"

# Read the briefing text Claude wrote to the File Share (Step 5 of prompt)
# and persist as JSON for the /briefing web page (non-fatal)
{
  node -e "
const fs = require('fs');
const textFile = process.argv[1];
const content = fs.existsSync(textFile) ? fs.readFileSync(textFile, 'utf8').trim() : '';
if (!content) {
  console.log('[briefing] latest-briefing-text.txt not found or empty — skipping JSON update');
  process.exit(0);
}
const out = JSON.stringify({ date: new Date().toISOString(), content });
fs.writeFileSync('/home/briefing/.claude/latest-briefing.json', out);
console.log('[briefing] Saved briefing text (' + content.length + ' chars) to latest-briefing.json');
" "${BRIEFING_TEXT_FILE}"
} || echo "[$(date -Iseconds)] Warning: could not save latest-briefing.json (non-fatal)"

echo "[$(date -Iseconds)] Task complete: ${TASK}"
