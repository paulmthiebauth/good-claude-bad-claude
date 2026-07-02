# good-claude-bad-claude - Plugin Design Spec

**Date:** 2026-06-28
**Status:** Implemented (v0.2.0 adds the "apply-now" memory)
**Repo:** https://github.com/<owner>/good-claude-bad-claude

## Overview

A Claude Code plugin that lets any engineer quickly capture a "good vs bad" code
example and submit it to a shared Google Form. The collected examples feed the
creation of shared style guides, reducing churn and making coding with Claude more
consistent across a team.

A user says (or types) **"good claude"** or **"bad claude"**. Claude runs a short
guided flow: collect the good example, collect the bad example, optionally collect
or draft (with confirmation) a *why* for each, infer the surrounding context
(repo, stack, what they were doing), preview the assembled submission, and on
confirmation POST it to the configured Google Form. It then optionally saves the
lesson as a personal *apply-now* rule in Claude memory, so the submitter benefits
immediately - without waiting for a formal style guide.

## Goals

- One-line capture of good/bad code examples during normal work.
- Zero form-specific data committed to the repo - the plugin is generic and
  reusable; the destination form is configured per-user.
- Minimal manual input: infer repo, stack, context, and submitter email
  automatically; only the two code snippets are strictly required.
- A well-structured, documented, installable plugin that is easy to maintain and
  extend.
- Immediate personal payoff: optionally save the lesson as an apply-now rule in
  the submitter's Claude memory, so it applies right away (the form remains the
  slow, aggregate path that feeds team style guides).

## Non-Goals

- Silently fabricating a *why*. The plugin may **draft** a why on request, but
  never submits an inferred why without the user confirming it. A why the user
  skips entirely is left marked `(to be inferred)` for downstream processing, not
  invented.
- Building or hosting the Google Form. The form already exists; the plugin only
  submits to it.
- Per-team or multi-form routing. One configured destination per user. (For a
  team rollout, everyone configures the same URL.)
- File-upload form fields (require Google auth; out of scope).

## Trigger Mechanism (Approach C)

Both entrypoints run the same underlying flow:

- **Natural language** - a skill whose description triggers on "good claude" /
  "bad claude" said in chat.
- **Slash commands** - `/good-claude` and `/bad-claude` invoke the same flow for
  users who prefer to type a command. `good-claude` frames good-first;
  `bad-claude` frames bad-first. Both collect *both* examples.

The slash command files are thin wrappers that defer to the skill, so there is a
single implementation of the flow logic.

## Repo Layout

```
good-claude-bad-claude/
├── .claude-plugin/
│   ├── marketplace.json        # makes the repo installable as a marketplace
│   └── plugin.json             # manifest + userConfig (declares form_url)
├── skills/
│   └── submitting-examples/
│       └── SKILL.md            # the guided flow + first-run setup/discovery logic
├── commands/
│   ├── good-claude.md          # thin wrapper → flow, good-first framing
│   └── bad-claude.md           # thin wrapper → flow, bad-first framing
├── scripts/
│   ├── submit_example.sh       # curl submitter (flag-driven; no deps but curl)
│   └── test_submit.sh          # plain-bash test: arg validation + dry-run output
├── docs/
│   └── design.md               # this design spec
└── README.md                   # setup guide (end users + maintainer)
```

## Configuration & Storage

Nothing form-specific is committed. Per-user state lives in two places, with a
clear source of truth:

1. **`userConfig` in `plugin.json`** (enable-time prompt, best-effort seed) - 
   declares a single `form_url` field so Claude Code prompts the user for it when
   they *enable* the plugin (the closest platform mechanism to "ask on install").
   No default value (a default would mean committing the URL).

   ```json
   {
     "userConfig": {
       "form_url": {
         "type": "string",
         "title": "Google Form URL",
         "description": "The viewform URL of the Google Form to submit examples to"
       }
     }
   }
   ```

   `${user_config.form_url}` substitution is documented for hooks / MCP / monitor
   commands but **not** guaranteed for scripts a skill runs. So scripts never read
   it directly; it is only used to *seed* setup when accessible.

2. **`${CLAUDE_PLUGIN_DATA}/config.json`** (runtime source of truth) - written by
   first-run setup, read by every submission. `${CLAUDE_PLUGIN_DATA}`
   (`~/.claude/plugins/data/<plugin-id>/`) is the Claude-provided per-user data
   dir; it survives plugin updates and is removed on uninstall. Holds the form
   URL, the resolved field mapping, and the email flag - everything a submission
   needs (the skill reads it and passes the values to the submit script as flags):

   ```json
   {
     "form_url": "https://docs.google.com/forms/d/e/…/formResponse",
     "collects_email": true,
     "fields": {
       "repo":    "entry.<repo-id>",
       "stack":   "entry.<stack-id>",
       "context": "entry.<context-id>",
       "good":    "entry.<good-id>",
       "bad":     "entry.<bad-id>"
     }
   }
   ```

The skill guarantees `config.json` exists before any submission: if it is missing,
inline setup populates it (seeding the URL from `userConfig` when readable, asking
the user otherwise), then runs field discovery.

## First-Run Field Discovery

Because `entry.*` IDs are form-specific, they cannot be committed. On first use
(or whenever `config.json` is missing/incomplete), the skill performs discovery
**Claude-driven** - Claude fetches and parses the form rather than a bundled
parser script, which keeps the only runtime dependency `curl` (robustly parsing
Google's form data in portable shell is fragile, and Claude is already in the
loop on first run):

1. Normalize the configured `form_url` (`/viewform` → fetch HTML with `curl -sL`).
2. Parse `FB_PUBLIC_LOAD_DATA_` to extract each question's text + `entry.*` ID.
3. Map questions to fields by keyword on the question text:
   `repository` → repo, `language`/`stack` → stack, `context` → context,
   `good` → good, `bad` → bad.
4. Detect whether the form collects email (`type="email"` present).
5. Write the result into `${CLAUDE_PLUGIN_DATA}/config.json`.

If mapping is ambiguous or a field is unmatched, the skill **guides the user
through it inline** (shows the discovered questions, asks which maps to which),
then caches the result. Subsequent submissions skip discovery.

## Submission Flow (SKILL.md)

1. **Setup check** - if `config.json` is missing or incomplete, run inline setup
   (prompt for URL if needed → discover → confirm mapping → cache), then continue.
2. **Collect snippets** - "What's the good example?" then "What's the bad
   example?" (order flips for `bad claude`). User may paste code or point at
   something from the conversation.
3. **Whys (optional, draftable)** - for each example the user picks one of: (a)
   write their own why, (b) have the plugin draft one, or (c) skip. When drafted,
   the plugin infers the why from the snippet + context, shows the drafted whys,
   and asks **"Does this sound correct?"** - the user accepts, edits either, or
   discards. This confirmation happens here, before the final preview. A why that
   is neither written nor accepted is submitted as `(to be inferred)`. No inferred
   why is ever submitted without explicit confirmation.
4. **Infer context fields:**
   - `repo`: `basename "$(git rev-parse --show-toplevel)"`, fallback to cwd
     basename.
   - `stack`: from repo signals (Gemfile → Ruby/Rails, package.json → JS/React,
     etc.).
   - `context`: e.g. "rails testing" / "react testing", inferred from the
     snippet and current activity.
   - `email`: `git config user.email` (sent via the form's special
     `emailAddress` param when the form collects email).
5. **Preview & confirm** - show the full assembled submission and let the user
   correct the inferred `stack`/`context` before sending.
6. **Submit** - run `submit_example.sh`; report ✅/❌ honestly.
7. **Save an apply-now rule (optional)** - synthesize a concise
   `When <context>, prefer <good>; avoid <bad>. Why: <why>.` rule and ask where to
   keep it: **A) project memory** (this repo's built-in Claude auto-memory - a
   topic file plus an actionable pointer line in `MEMORY.md`; personal, never
   committed), **B) global** (`~/.claude/CLAUDE.md`), or **C) don't save**. Uses
   Claude Code's native auto-memory (v2.1.59+); additive and independent of the
   form submission.

### Good/Bad field format

To make downstream *why* inference easy, each paragraph field is submitted as:

```
CODE:
<snippet>

WHY:
<the why, or "(to be inferred)">
```

## submit_example.sh

A thin, **flag-driven** `curl` wrapper with no dependency beyond `curl` itself.
The skill reads `${CLAUDE_PLUGIN_DATA}/config.json` (Claude parses JSON natively)
and passes everything to the script as flags - the form URL, the five `entry.*`
field IDs, the five content values, and `--email` (only when the form collects
email). The script URL-encodes all values, sends `emailAddress` when `--email` is
given, and keeps a `--dry-run` mode that prints the curl invocation without
sending. It validates that the form URL, all field IDs, and both snippet values
are present; exits non-zero on any missing required value or a non-200 response.

Keeping the script flag-driven (rather than having it read `config.json`) means it
needs no JSON parser, so it runs anywhere `curl` exists.

## Error Handling

- **No `form_url`** → trigger inline setup (prompt for it).
- **Discovery fails / unmappable fields** → inline guided mapping.
- **No `git config user.email`** → ask the user (form requires email); never
  submit blank.
- **Empty snippet** → re-prompt; do not submit.
- **Non-200 / network failure** → report the failure; never claim success.

## Testing

- `scripts/test_submit.sh` - a plain-Bash test (no `bats` dependency) covering
  `submit_example.sh` field-to-value mapping, email inclusion/omission, and
  argument validation via `--dry-run` (no network). Runnable in CI.
- The skill flow and Claude-driven discovery get a manual test checklist in the
  README, verified end-to-end against a real form (prompt-driven flows can't be
  meaningfully unit-tested).

## Distribution & Setup Guide

The plugin is meant to be **forked**: a team forks the repo, hosts it under their
own GitHub user or org, and points their people at that fork. Throughout this doc,
`<owner>` is a placeholder for that GitHub user or org.

End-user install (documented in README):

```
/plugin marketplace add <owner>/good-claude-bad-claude
/plugin install good-claude-bad-claude
```

On enable, Claude Code prompts for the form URL. Whoever owns the form distributes
its URL (e.g. via onboarding docs), so everyone on a team funnels into the same form
while nothing form-specific is committed.

**Caveat:** a **private** fork only allows `/plugin marketplace add` for users
whose git is authenticated to it. For a wider rollout, make the fork public or host
it under an organization. The README will document this switch. Private is fine for
initial development and a pilot.

## Open Considerations

- The keyword-based field mapping assumes forms whose question text contains the
  expected keywords. A form that follows the expected question wording satisfies
  this; the inline mapping fallback covers forms that don't.
- `emailAddress` is sent whenever the form collects email; harmless if it does
  not.
