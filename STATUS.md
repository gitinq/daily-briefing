# Status — Daily Briefing

**Last updated:** 2026-04-18
**Status:** Live and working — scheduled run confirmed via supercronic 02:23 BST 2026-04-18

## What this is

Paul's weekday morning briefing, migrated from Claude Cowork to Claude Code.
Reads Gmail + Google Calendar, sends formatted summary to Slack channel `C0ASTJ537R8`.
Runs in the `nas-claude` Docker container on MiniPC01 (192.168.0.6).

## Schedule

| Day | Time |
|---|---|
| Monday–Thursday | 08:00 Europe/London |
| Friday | 06:00 Europe/London |

## Infrastructure repo

`nas-claude`: https://github.com/gitinq/nas-claude
- Dockerfile, docker-compose, crontab, run-task.sh, entrypoint.sh
- NAS path: `/mnt/apps_pool/docker_apps/containers/nas-claude/`

## NAS task path

`/mnt/apps_pool/docker_apps/opt/nas-claude/tasks/daily-briefing/`

## Key decisions made

- **Two-repo split**: infrastructure (`nas-claude`) vs prompt payload (this repo). Prompt changes require only a `git pull` on NAS — no container rebuild.
- **Auth**: claude.ai OAuth (Pro plan), not API key. Token persisted in `claude-data/` volume at `/mnt/apps_pool/docker_apps/opt/nas-claude/claude-data/`.
- **Non-root execution**: `--dangerously-skip-permissions` is blocked for root. Container runs as root but `run-task.sh` invokes `claude` via `su - briefing`.
- **Scheduling**: supercronic (container-native cron, TZ-aware). Uses `CRON_TZ=Europe/London` in `/app/crontab`.
- **HOME fix (2026-04-18)**: `su - briefing` does not override `HOME` when inherited from SSH session. Fixed by setting `HOME=/home/briefing` explicitly in the claude invocation in `run-task.sh` (NAS commit `788cc89`). Without this, MCP servers never load and all scheduled runs fail silently.

## MCP dependencies

Local MCP servers configured at `/home/briefing/.claude/settings.json` on the NAS:

| Server | npm package | Provides |
|---|---|---|
| `gmail` | `@monsoft/mcp-gmail` | Gmail search/read tools |
| `google-calendar` | `@cocal/google-calendar-mcp` | Calendar list/event tools |
| `slack` | `slack-mcp-server@latest` | Slack send message |

**Credentials required (one-time setup):**
- **Slack**: xoxp user token in `settings.json` env block.
- **Google**: OAuth credential + token JSON files in `claude-data/` volume. Re-run auth if refresh token expires.

## Known maintenance items
- **Auth token expiry**: When claude.ai session expires, copy fresh `~/.claude/.credentials.json` from Windows to `/mnt/apps_pool/docker_apps/opt/nas-claude/claude-data/` on NAS.
- **Container rebuild**: Required for changes to `nas-claude` repo (not this repo). `git pull` + `docker compose build && docker compose up -d`.
- **Prompt updates**: `git pull` in `/mnt/apps_pool/docker_apps/opt/nas-claude/tasks/daily-briefing/` — takes effect on next run.
- **nas-claude fix not pushed to GitHub**: The `HOME=/home/briefing` fix is committed locally on the NAS (`788cc89`) but not pushed. If the NAS repo is ever cloned fresh, re-apply this fix or push from the NAS.
- **Healthcheck cosmetic failure**: `pgrep` not in image — container shows "unhealthy" but supercronic runs fine. Fix in future rebuild by replacing healthcheck with `/bin/sh -c "kill -0 1"` or similar.

## Verification

```bash
# Manual test run (from Windows Git Bash, NAS_PASS in ~/.bash_profile)
source ~/.bash_profile
plink.exe -ssh truenas_admin@192.168.0.6 -pw "$NAS_PASS" \
  -hostkey "ssh-ed25519 255 SHA256:eCQS039rbkZl9b21hLinxBggAWl5vn78j2s+6BKOGn0" \
  -batch "echo '$NAS_PASS' | sudo -S bash -c 'docker exec nas-claude /scripts/run-task.sh daily-briefing'"

# Logs
... | sudo -S bash -c 'tail -f /mnt/apps_pool/docker_apps/opt/nas-claude/logs/daily-briefing.log'

# Container status
... | sudo -S bash -c 'docker ps -a --filter name=nas-claude'
```
