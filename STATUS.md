# Status — Daily Briefing

**Last updated:** 2026-04-16
**Status:** Scheduled run failing — MCP tools not yet configured (see [issue #1](https://github.com/gitinq/daily-briefing/issues/1))

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

## MCP dependencies

`prompt.md` uses tool names from the claude.ai web connector naming convention. For these to work in the scheduled CLI context, **local MCP servers must be configured** at `/home/briefing/.claude/settings.json` on the NAS with matching server names:

| MCP server name in settings.json | Provides |
|---|---|
| `claude_ai_Slack` | `mcp__claude_ai_Slack__slack_send_message` etc. |
| `claude_ai_Gmail` | `mcp__claude_ai_Gmail__search_threads` etc. |
| `claude_ai_Google_Calendar` | `mcp__claude_ai_Google_Calendar__gcal_list_events` etc. |

**Credentials required (one-time setup):**
- **Slack**: Create Slack app at api.slack.com/apps → bot token (`xoxb-...`) + workspace team ID. Store `SLACK_BOT_TOKEN` in `/mnt/apps_pool/docker_apps/opt/nas-claude/.env`.
- **Google**: GCloud project → enable Gmail API + Calendar API → OAuth 2.0 credentials → run auth flow once inside container to generate token files. Store credential/token JSON files in `claude-data/`.

See [nas-claude issue #1](https://github.com/gitinq/nas-claude/issues/1) for full setup steps.

## Known maintenance items

- **MCP setup**: Not yet complete — see above and [daily-briefing issue #1](https://github.com/gitinq/daily-briefing/issues/1).
- **Auth token expiry**: When claude.ai session expires, copy fresh `~/.claude/.credentials.json` from Windows to `/mnt/apps_pool/docker_apps/opt/nas-claude/claude-data/` on NAS.
- **Container rebuild**: Required for changes to `nas-claude` repo (not this repo). `git pull` + `docker compose build && docker compose up -d`.
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
