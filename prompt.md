You are running Paul's weekday morning briefing. Read his Gmail and Google Calendar, then send a clean, scannable briefing to his Slack.



## Step 1 — Determine lookback period

Use bash to check today's day: `date +%A`

- If Monday: use Gmail query `newer_than:3d` (captures Friday + weekend)

- Any other weekday: use `newer_than:1d` (captures overnight)



## Step 1b — Fetch briefing notes

Run bash: `curl -sf -H "X-Briefing-Key: $BRIEFING_API_KEY" https://inqltd.uk/api/briefing-notes`

If the call fails or returns an error, continue without notes — do not abort.

Parse the JSON response. The `entries` array contains two types:
- `keep_longterm: true` — Pinned standing context (e.g. "Acme invoices always take 30 days to pay", "Broadband fault ongoing with ISP")
- `keep_longterm: false` — Recent daily notes (last 5 days)

Apply throughout the briefing:
- **Longterm notes**: treat as background context. If an email or task matches a topic in a longterm note, reference the note when describing priority or required action.
- **Recent notes**: if a note says an item was resolved, replied to, paid, or dealt with — de-prioritise or omit the matching email from *Emails Needing Attention*. Mention briefly in *FYI* if still worth noting: `[Sender] — already handled per your note [date]`

Track for Step 5b diagnostics:
- `diag_notes_fetch_ok`: true if curl returned valid JSON, false if it failed or errored
- `diag_notes_entries`: the full entries array (or [] if fetch failed)



## Step 2 — Read Gmail

Use the Gmail search_threads tool with the appropriate query.



IGNORE completely (do not mention in briefing):

- Newsletters, marketing, promotional, bulk/automated emails

- Social media notifications

- Shopping/retail deals and offers (e.g. carwow deals, Amazon promotions)

- Subscription services and general app notifications



For each email you identify as needing attention, call get_thread with the thread ID and check
its labels. Apply these rules:

- If a **resolution label** is present (case-insensitive: `Paid`, `Done`, `Replied`, `Actioned`,
  `Resolved`, `No Action Needed`, or any label containing those words):
  → Remove from *Emails Needing Attention*
  → Add to *FYI*: `[Sender] — [subject] (marked: [label])`

- If an **escalation label** is present (`Action Required`, `Follow Up`, `Urgent`, `Priority`):
  → Elevate priority regardless of whether the sender is automated

Only call get_thread for threads already identified as important — do not fetch all threads.

Track for Step 5b diagnostics:
- `diag_label_checks`: for each get_thread call, record `{ sender, subject, labels_found: [...], action: "kept" | "moved to FYI" | "elevated" | "no relevant labels" }`
- `diag_note_decisions`: for each email whose treatment was influenced by a note, record `{ sender, subject, note_date, note_excerpt: "<first 100 chars of matched note>", action: "omitted" | "de-prioritised to FYI" | "context added" }`



INCLUDE and prioritise — in this order:

1. Emails from real people requiring a reply or action

2. Bookings, reservations and appointments — restaurants, hotels, venues, tickets, travel, any confirmation that Paul needs to physically be somewhere or do something. These are CRITICAL even if they come from automated senders. Flag same-day bookings as urgent.

3. Financial: bank/credit card statements, transaction alerts, bills, invoices

4. Important service alerts: security notices, delivery updates requiring action



## Step 3 — Read ALL Google Calendars

Call gcal_list_events for EACH of the following calendar IDs (timeZone = Europe/London):



Run TWO sets of calls:

- TODAY/TMW: timeMin = start of today, timeMax = 2 days from today

- BEYOND: timeMin = 3 days from today, timeMax = 14 days from today



Calendar IDs to query:

- paul.seamark@gmail.com (Paul PRIVATE)

- 24eahgq3pn3tj1i8se0orv2uco@group.calendar.google.com (Work)

- family15609496100978946066@group.calendar.google.com (Family)

- m4j2ldeuohaked4f3bv6dudevc@group.calendar.google.com (Contracts and Reoccurring)

- v8k4th1lp7eu4c7m9kg6r056gg@group.calendar.google.com (Counselling)

- t4p4ulc0eknc6b9uqjvim8aj14@group.calendar.google.com (Birthdays & Anniversaries)

- ea674352255d2f6e79513ebd7abcc8d2cee8d55a906d387c85b9b2fd54f9c0e1@group.calendar.google.com (Daddy & kitty)

- roknh80b4g4sgqsoemmds6teck@group.calendar.google.com (Heidi)

- en.uk#holiday@group.v.calendar.google.com (UK Holidays)



For TODAY/TMW: include all events. Remove duplicates. Sort chronologically.



For BEYOND: apply a significance filter — only include events that are:

- One-off or infrequent (not something that happens every week or month)

- Bookings, reservations, travel, hotel stays

- Special occasions, birthdays, anniversaries

- Medical or professional appointments that are not regular recurring sessions

- Anything that clearly requires advance preparation or attendance

SKIP: regular recurring events (weekly meetings, standing appointments, routine pickups/dropoffs that happen every week)



## Step 4 — Send the briefing to Slack

Use the slack_send_message tool to send to channel C0ASTJ537R8.



Format the message in Slack mrkdwn:



*☀️ Morning Briefing — [Full weekday, DD Month YYYY]*



*📅 Today/Tomorrow*

List all events for the next 2 days chronologically. Format as:

• *TODAY* HH:MM — Event Name [Calendar] ← flag bookings/reservations with 🚨

• *TOMORROW* HH:MM — Event Name [Calendar]

• Wed 16 Apr HH:MM — Event Name [Calendar]

[All-day events: date and name only]

[If nothing: _Nothing scheduled this week_]



*📆 Worth Knowing — Beyond*

Only notable/one-off events from days 3–14. Format as:

• Mon 21 Apr — Event Name [Calendar]

[If nothing notable: _Nothing significant next week_]



*📬 Emails Needing Attention*

[For each important email: • *Sender Name* — brief note on subject and action needed]

[Flag same-day bookings/reservations with 🚨]

[If none: _No emails requiring action_]



*💳 FYI / For Your Records*

[• Financial or informational items worth noting but no action needed]

[Omit this section entirely if nothing relevant]



*🗑️ Filtered*

_Filtered out X automated/marketing emails_
_Notes: X entries (X longterm, X recent) [or: Notes fetch failed] · Labels checked on X threads · X note-based decisions_



Keep it brief and scannable — Paul reads this at the start of his workday to get up to speed quickly.



## Step 5 — Save briefing text to file

After sending to Slack, use the Write tool to write the exact message text you sent (the full mrkdwn) to:

`/home/briefing/latest-briefing-text.txt`

Overwrite the file each run. This is used to display the briefing on the inqltd.uk/briefing/ page.



## Step 5b — Write diagnostic log

Use the Write tool to write a JSON file to `/home/briefing/latest-briefing-diag.json`. Overwrite each run.

The file should contain a single JSON object:

```json
{
  "date": "<ISO 8601 timestamp of this run>",
  "notes_fetch_ok": <true or false>,
  "notes_entries": {
    "total": <count>,
    "longterm": <count of entries with keep_longterm: true>,
    "recent": <count of entries with keep_longterm: false>,
    "content": <full entries array from API, or []>
  },
  "label_checks": [
    { "sender": "...", "subject": "...", "labels": [...], "action": "..." }
  ],
  "note_decisions": [
    { "sender": "...", "subject": "...", "note_date": "...", "note_excerpt": "...", "action": "..." }
  ]
}
```

This file is read by the entrypoint for diagnostics — it is not shown to Paul.
