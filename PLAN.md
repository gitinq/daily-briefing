# Plan — Daily Briefing

## Current status

Live on Azure Container Apps Jobs. Prompt-only changes take effect immediately on next run (pulled at runtime from this repo). Infrastructure changes require a push to trigger a Docker image rebuild via GitHub Actions.

---

## Open issues

| Issue | Title | Status |
|---|---|---|
| [#2](https://github.com/gitinq/daily-briefing/issues/2) | Include briefing notes in morning briefing context | Pending TEST |
| [#3](https://github.com/gitinq/daily-briefing/issues/3) | Check Gmail labels on flagged emails to identify resolved items | Pending TEST |

---

## Feature: Briefing notes context + Gmail label awareness

### Overview

Two additions to `prompt.md` that give the briefing access to Paul's saved notes and Gmail resolution labels, so it can skip items already dealt with and carry forward standing context.

### Dependencies

- **web #31** must be implemented first — the `api/briefing-notes` endpoint must exist and `BRIEFING_API_KEY` must be set as a SWA app setting before the briefing runner can call it.
- `BRIEFING_API_KEY` env var must be set on the ACA Jobs (see below).

---

## Issue #2 — Briefing notes context

### Prompt change

Add a new **Step 1b** between Step 1 (lookback period) and Step 2 (Gmail):

```
## Step 1b — Fetch briefing notes

Run bash: curl -sf -H "X-Briefing-Key: $BRIEFING_API_KEY" https://inqltd.uk/api/briefing-notes

If the call fails or returns empty, continue without notes.

Parse the JSON response. It contains entries with two types:
- keep_longterm: true  — Pinned standing context (e.g. "Acme invoices always take 30 days to pay")
- keep_longterm: false — Recent daily notes (up to 5 days old)

Apply these throughout the briefing:
- Longterm notes: treat as background context when assessing emails and tasks.
  If an email matches a topic in a longterm note, reference the note when noting priority/action.
- Recent notes: if a note says an item was resolved, replied to, or dealt with,
  de-prioritise or omit the matching email from Emails Needing Attention.
  Mention it briefly in FYI if still worth noting: "[Sender] — already handled per your note [date]"
```

### Infrastructure change

Add `BRIEFING_API_KEY` env var to ACA Jobs. On existing jobs:
```bash
az containerapp job update --name briefing-mon --resource-group rg-briefing \
  --set-env-vars BRIEFING_API_KEY=<value>
# Repeat for briefing-tue through briefing-fri
```

Also add to `azure/provision.sh` YAML template so reprovisioning includes it.

### Checklist

- [x] web #31 implemented and `BRIEFING_API_KEY` SWA app setting set (2026-05-01)
- [x] Generate `BRIEFING_API_KEY` value — done (2026-05-01)
- [x] Add Step 1b to `prompt.md` (2026-05-01)
- [x] Set `BRIEFING_API_KEY` on all 7 ACA Jobs (2026-05-01)
- [x] Add `BRIEFING_API_KEY` env var to YAML template in `provision.sh` (2026-05-01)
- [ ] Trigger a manual run and verify notes appear in briefing output
- [ ] Update STATUS.md

---

## Issue #3 — Gmail label awareness

### Prompt change

Extend **Step 2** (Gmail) with label checking:

```
After identifying emails that need attention, for each one:

1. Call get_thread with the thread ID to fetch full labels.

2. Check for resolution labels (case-insensitive):
   Paid, Done, Replied, Actioned, Resolved, No Action Needed

3. If a resolution label is found:
   - Remove from Emails Needing Attention
   - Add to FYI: "[Sender] — [subject] (marked: [label])"

4. Check for escalation labels:
   Action Required, Follow Up, Urgent, Priority

5. If an escalation label is found:
   - Elevate in priority regardless of automated sender classification
```

### Checklist

- [x] Add label-check instructions to Step 2 of `prompt.md` (2026-05-01)
- [ ] Trigger a manual run (with a test email labelled "Done") and verify behaviour
- [ ] Update STATUS.md

---

## Assumptions and constraints

- The briefing container image has `curl` installed (confirmed in Dockerfile: `curl ca-certificates git`).
- `BRIEFING_API_KEY` is a static secret — rotate it if ever exposed.
- `get_thread` is available via the `gmail` MCP connector (already loaded in every run).
- Only call `get_thread` on threads already identified as needing attention — do not fetch all threads (token cost + latency).
- If `BRIEFING_API_KEY` is not set in the container env, `$BRIEFING_API_KEY` expands to empty string and the curl call will return 401 — handle gracefully (continue without notes).

---

## Build order

1. Implement web #31 first (API endpoint)
2. Set up `BRIEFING_API_KEY` in both SWA and ACA Jobs
3. Implement #2 (prompt Step 1b)
4. Implement #3 (prompt Step 2 labels) — can be done simultaneously with #2
5. Trigger manual test run, verify both features
