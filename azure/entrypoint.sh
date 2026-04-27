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

su - briefing -c "HOME=/home/briefing claude --dangerously-skip-permissions -p \"\$(cat '${TMPFILE}')\"" \
  2>&1 | tee -a "${LOG_FILE}"

rm -f "${TMPFILE}"
echo "[$(date -Iseconds)] Task complete: ${TASK}"
