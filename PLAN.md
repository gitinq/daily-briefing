# Plan — Daily Briefing

## Current status

Live on Azure Container Apps Jobs. Prompt-only changes take effect immediately on next run (pulled at runtime from this repo). Infrastructure changes require a push to trigger a Docker image rebuild via GitHub Actions.

---

## Open issues

| Issue | Title | Status |
|---|---|---|
| [#3](https://github.com/gitinq/daily-briefing/issues/3) | Check Gmail labels on flagged emails to identify resolved items | Pending TEST |

---

## Issue #3 — Gmail label awareness (prompt done, pending live test)

Label checking is implemented and working — `get_thread` is called for each important email, labels are recorded in the diagnostic file. What is not yet tested: a thread with an actual resolution label (Done, Paid, etc.) appearing in FYI with the `(marked: [label])` annotation.

**To test:** Label a Gmail thread "Done" or "Paid" before the next briefing run and confirm:
- It moves from Emails Needing Attention → FYI
- FYI entry shows `(marked: Done)` or similar
- `label_checks` in `latest-briefing-diag.json` shows `action: "moved to FYI"`

---

## Diagnostic layer (added 2026-05-02)

Each run writes `latest-briefing-diag.json` to the `stbriefing57752 / briefing-data` file share.

To read after a run:
```bash
az storage file download --account-name stbriefing57752 --share-name briefing-data \
  --path latest-briefing-diag.json --dest diag.json
```

Fields: `notes_fetch_ok`, `notes_entries` (total/longterm/recent/content), `label_checks` (per thread: sender, subject, labels, action), `note_decisions` (per note-influenced email).

The Slack Filtered section also shows a one-liner summary: `Notes: X entries · Labels checked on X threads · X note-based decisions`.

---

## Key architecture notes

- `prompt.md` is pulled fresh from this repo on every run — prompt changes are live immediately, no image rebuild needed.
- `entrypoint.sh` is baked into the Docker image — infrastructure changes require a push to master to trigger a GitHub Actions rebuild.
- `su -` creates a login shell which resets environment variables. Any env var that Claude needs to access from the prompt must be explicitly passed in the `su -c` string (e.g. `BRIEFING_API_KEY='${BRIEFING_API_KEY}'`).
- `BRIEFING_API_KEY` must match the SWA app setting on `inqltd-web` and be set on all 7 ACA Jobs.

---

## Next steps

- [ ] Test issue #3: label a Gmail thread before a run, verify FYI annotation and diag file
