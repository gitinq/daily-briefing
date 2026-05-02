# Status — Daily Briefing

**Last updated:** 2026-05-02
**Status:** Live on Azure Container Apps Jobs

## Recent changes (2026-05-02)

- **Diagnostic layer added**: each run writes `latest-briefing-diag.json` to the `stbriefing57752 / briefing-data` file share (Step 5b in prompt, handled by entrypoint). Fields: `notes_fetch_ok`, `notes_entries`, `label_checks`, `note_decisions`. Slack Filtered section shows a one-liner summary.
- **Bug fixed — `su -` stripping env vars (issue #4)**: `BRIEFING_API_KEY` was not reaching Claude because `su -` creates a login shell that resets the environment. Fixed by passing it explicitly in the `su -c` command string. Any future env var needed by Claude must be passed the same way.
- **Verified working (2026-05-02 manual run)**: notes fetched, EON Solar correctly de-prioritised to FYI with "per yesterday's note" annotation. Issues #2 and #4 closed.
- **Issue #3 (Gmail labels)**: label checking confirmed running (3 threads per run), but FYI-with-label-annotation path not yet tested. Pending a run with a labelled email.

## Recent changes (2026-05-01)

- **Step 1b added to prompt**: fetches briefing notes from `https://inqltd.uk/api/briefing-notes` using `BRIEFING_API_KEY` env var.
- **Step 2 updated**: for emails needing attention, calls `get_thread` to check Gmail labels. Resolution labels move items to FYI. Escalation labels elevate priority.
- **`BRIEFING_API_KEY` env var**: set on all 7 ACA Jobs and added to `provision.sh` template.

## Known issues / recent fixes (2026-04-28)

- Cloud MCP connectors (Gmail/Calendar/Slack) load intermittently at session startup — entrypoint now retries once after 30s if briefing txt file not written
- Briefing txt file path changed from `/home/briefing/.claude/latest-briefing-text.txt` to `/home/briefing/latest-briefing-text.txt` — Claude Code blocks Write tool access to `.claude/` directory
- Prompt Step 5 updated to use Write tool instead of bash (more reliable with multi-line mrkdwn)
- entrypoint no longer overwrites `latest-briefing.json` with empty content if run produces nothing

## What this is

Paul's weekday morning briefing. Reads Gmail + Google Calendar via cloud MCP, sends formatted
summary to Slack channel `C0ASTJ537R8`.

## Schedule

| Day | Time |
|---|---|
| Monday–Thursday | 08:00 Europe/London |
| Friday | 06:00 Europe/London |

## Platform: Azure Container Apps Jobs

The briefing runs as a scheduled Azure Container Apps Job — no always-on server.

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-briefing` | uksouth |
| Container Apps Environment | `ace-briefing` | Consumption plan |
| Container image | `ghcr.io/gitinq/briefing:latest` | Built by GitHub Actions on push to master |
| File share | `stbriefing57752 / briefing-data` | Mounted at `/home/briefing/.claude/` — persists OAuth credentials |

### Container Apps Jobs (7 total)

| Job | Cron (UTC) | Day | Default state |
|---|---|---|---|
| `briefing-mon` | `0 8 * * 1` | Monday | Enabled |
| `briefing-tue` | `0 8 * * 2` | Tuesday | Enabled |
| `briefing-wed` | `0 8 * * 3` | Wednesday | Enabled |
| `briefing-thu` | `0 8 * * 4` | Thursday | Enabled |
| `briefing-fri` | `0 6 * * 5` | Friday | Enabled |
| `briefing-sat` | `0 0 31 2 *` | Saturday | Disabled |
| `briefing-sun` | `0 0 31 2 *` | Sunday | Disabled |

Disabled = sentinel cron `0 0 31 2 *` (Feb 31, never fires). Schedule is configurable live
at `inqltd.uk/briefing/`.

### How a run works

1. Container starts (`azure/entrypoint.sh`, runs as root initially)
2. Chowns `/home/briefing/.claire` (File Share mounted as root)
3. Clones or pulls this repo (`gitinq/daily-briefing`) as `briefing` user
4. Checks `claude auth status` — posts Slack alert and exits if expired
5. Runs `claude --dangerously-skip-permissions -p "$(cat prompt.md)"`
6. Claude uses cloud MCP (Gmail, Calendar, Slack) via `.credentials.json` OAuth token
7. Container exits cleanly; Azure marks execution Succeeded/Failed

### Checking runs

Azure Portal → Container Apps → `rg-briefing` → any `briefing-*` job → Execution history

Or via `inqltd.uk/briefing/` History card (shows last 10 across all jobs).

## Updating the prompt

Edit `prompt.md` in this repo and push. The container pulls latest on every run — no image
rebuild needed.

## Updating the container image

Edit `azure/Dockerfile` or `azure/entrypoint.sh` in this repo and push to master. GitHub
Actions builds and pushes `ghcr.io/gitinq/briefing:latest` automatically. Existing jobs
pick up the new image on their next run.

## Auth renewal

Claude OAuth credentials expire. When expired, upload a fresh `.credentials.json` to the
`briefing-data` File Share at path `.credentials.json`.

Azure Portal → Storage accounts → `stbriefing57752` → File shares → `briefing-data`

The entrypoint checks auth on every run and will post to Slack if expired.

## Re-provisioning from scratch

```bash
# Requires az CLI logged in and correct subscription
bash azure/provision.sh
```

See the script for full details and manual steps.

## Key decisions

- **One repo**: Infrastructure (`azure/`) and prompt (`prompt.md`) live here.
  Prompt changes take effect immediately (pulled at run time). Image changes require a push
  to trigger a rebuild.
- **Auth**: claude.ai OAuth (Pro plan), not API key. Token persisted in Azure File Share.
- **Non-root execution**: `--dangerously-skip-permissions` is blocked for root. Container
  runs entrypoint as root for chown, then drops to `briefing` user for claude.
- **Schedule management**: `inqltd.uk/briefing/` UI in `gitinq/web` repo.
