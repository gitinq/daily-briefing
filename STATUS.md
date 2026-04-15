# Status — Daily Briefing

**Last updated:** 2026-04-15
**Status:** Live and working

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
- **Scheduling**: supercronic (container-native cron, no daemon, TZ-aware).

## Known maintenance items

- **Auth token expiry**: When claude.ai session expires, copy fresh `~/.claude/.credentials.json` from Windows to `/mnt/apps_pool/docker_apps/opt/nas-claude/claude-data/` on NAS.
- **Container rebuild**: Required only for changes to `nas-claude` repo (not this repo). `git pull` + `docker compose build && docker compose up -d`.
- **Prompt updates**: `git pull` in `/mnt/apps_pool/docker_apps/opt/nas-claude/tasks/daily-briefing/` — takes effect on next run.

## Verification

```bash
# Manual test run
docker exec nas-claude /scripts/run-task.sh daily-briefing

# Logs
tail -f /mnt/apps_pool/docker_apps/opt/nas-claude/logs/daily-briefing.log

# Auth status
docker exec nas-claude su - briefing -c "claude auth status"
```
