# good-claude-bad-claude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a forkable Claude Code plugin that captures a "good vs bad" code example through a guided flow and submits it to a configured Google Form.

**Architecture:** A skill (`submitting-examples`) carries the guided flow and is triggered by saying "good claude" / "bad claude" or by the `/good-claude` and `/bad-claude` slash commands. On first use the skill discovers the form's field IDs (Claude fetches the form with `curl` and parses it) and caches them to a per-user `config.json` under `${CLAUDE_PLUGIN_DATA}`. Each submission is sent by a thin, flag-driven `submit_example.sh` (curl only). Nothing form-specific is committed to the repo.

**Tech Stack:** Claude Code plugin (JSON manifests, Markdown skill + commands), Bash, `curl`. Tests are plain Bash (no `bats` dependency).

## Global Constraints

Every task implicitly includes these. Values copied from `docs/design.md`:

- No form-specific data is committed: no form URL and no `entry.*` IDs anywhere in the repo.
- Bundled scripts depend only on `curl` + Bash/coreutils — they must run on any engineer's machine with no `jq`/`python`/`ruby`/`node`.
- Per-user runtime config lives at `${CLAUDE_PLUGIN_DATA}/config.json`; bundled scripts are referenced via `${CLAUDE_PLUGIN_ROOT}`.
- Names are exact: plugin `good-claude-bad-claude`, skill `submitting-examples`, commands `/good-claude` and `/bad-claude`.
- Good/bad paragraph fields are submitted in this exact format:
  ```
  CODE:
  <snippet>

  WHY:
  <the why, or (to be inferred)>
  ```
- No inferred why is ever submitted without explicit user confirmation.
- The submitter email is sent via the `emailAddress` POST param only when the form collects email.
- All docs/code stay generic and forkable: use `<owner>` as the GitHub user/org placeholder; no personal or employer-specific references.

---

### Task 1: Plugin skeleton & manifests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: an installable plugin named `good-claude-bad-claude` that declares a `form_url` user config field. Later tasks add the skill, commands, and scripts into this structure.

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "good-claude-bad-claude",
  "description": "Capture good vs bad code examples and submit them to a shared Google Form to power team style guides.",
  "version": "0.1.0",
  "keywords": ["style-guide", "code-review", "examples", "google-forms"],
  "userConfig": {
    "form_url": {
      "type": "string",
      "title": "Google Form URL",
      "description": "The viewform URL of the Google Form to submit examples to."
    }
  }
}
```

- [ ] **Step 2: Create `.claude-plugin/marketplace.json`**

```json
{
  "name": "good-claude-bad-claude",
  "description": "Marketplace for the good-claude-bad-claude plugin.",
  "owner": { "name": "<owner>" },
  "plugins": [
    {
      "name": "good-claude-bad-claude",
      "description": "Capture good vs bad code examples and submit them to a shared Google Form.",
      "version": "0.1.0",
      "source": "./"
    }
  ]
}
```

- [ ] **Step 3: Verify both files are valid JSON**

Run: `cat .claude-plugin/plugin.json .claude-plugin/marketplace.json`
Then read each file back and confirm it parses as JSON (Claude reads them; do not add a structural unit test). Expected: both files print without truncation and contain the keys above.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat: add plugin manifest and marketplace with form_url user config"
```

---

### Task 2: `submit_example.sh` (the submission engine, TDD)

**Files:**
- Create: `scripts/submit_example.sh`
- Test: `scripts/test_submit.sh`

**Interfaces:**
- Produces: `submit_example.sh`, invoked by the skill as
  `"${CLAUDE_PLUGIN_ROOT}/scripts/submit_example.sh" --form-url URL --field-repo entry.X --field-stack entry.X --field-context entry.X --field-good entry.X --field-bad entry.X [--email EMAIL] --repo V --stack V --context V --good V --bad V [--dry-run]`.
  Exits `0` on HTTP 200, `1` on any missing required value or non-200 response. `--dry-run` prints the curl invocation and sends nothing.

- [ ] **Step 1: Write the failing test `scripts/test_submit.sh`**

```bash
#!/usr/bin/env bash
# Behavioral tests for submit_example.sh. Uses --dry-run; never hits the network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/submit_example.sh"
pass=0; fail=0

ok()   { echo "ok - $1"; pass=$((pass+1)); }
nok()  { echo "NOT OK - $1"; fail=$((fail+1)); }
has()  { [[ "$1" == *"$2"* ]] && ok "$3" || { nok "$3"; echo "   wanted substring: $2"; }; }
hasnt(){ [[ "$1" != *"$2"* ]] && ok "$3" || nok "$3"; }

full_args=( --form-url https://example.com/formResponse
  --field-repo entry.1 --field-stack entry.2 --field-context entry.3
  --field-good entry.4 --field-bad entry.5
  --repo myrepo --stack rails --context "rails testing"
  --good "good code" --bad "bad code" )

# 1. dry-run maps each field to its value
out=$("$SUT" --dry-run "${full_args[@]}" --email me@example.com)
has "$out" "entry.1=myrepo"            "maps repo field to value"
has "$out" "entry.4=good code"         "maps good field to value"
has "$out" "emailAddress=me@example.com" "includes email when provided"

# 2. dry-run omits emailAddress when no --email
out=$("$SUT" --dry-run "${full_args[@]}")
has   "$out" "entry.5=bad code" "maps bad field to value"
hasnt "$out" "emailAddress"     "omits email when not provided"

# 3. missing a required value exits non-zero
if "$SUT" --dry-run --form-url https://example.com/formResponse \
     --field-repo entry.1 >/dev/null 2>&1; then
  nok "exits non-zero on missing required values"
else
  ok "exits non-zero on missing required values"
fi

echo "---"; echo "pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
```

- [ ] **Step 2: Make the test executable and run it to confirm it fails**

Run:
```bash
chmod +x scripts/test_submit.sh
./scripts/test_submit.sh
```
Expected: FAIL — `submit_example.sh` does not exist yet (errors / `fail` > 0).

- [ ] **Step 3: Implement `scripts/submit_example.sh`**

```bash
#!/usr/bin/env bash
#
# submit_example.sh - POST one good/bad code example to a Google Form.
# Pure curl; no external dependencies. All form-specific values are passed in as
# flags by the caller (the plugin skill reads them from config.json).
#
# Required: --form-url, the five --field-* IDs, and the five value flags
# (--repo --stack --context --good --bad). --email is optional. --dry-run prints
# the curl invocation and sends nothing.
#
set -euo pipefail

form_url="" email=""
field_repo="" field_stack="" field_context="" field_good="" field_bad=""
val_repo="" val_stack="" val_context="" val_good="" val_bad=""
dry_run=false

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --form-url)      form_url="$2"; shift 2;;
    --email)         email="$2"; shift 2;;
    --field-repo)    field_repo="$2"; shift 2;;
    --field-stack)   field_stack="$2"; shift 2;;
    --field-context) field_context="$2"; shift 2;;
    --field-good)    field_good="$2"; shift 2;;
    --field-bad)     field_bad="$2"; shift 2;;
    --repo)          val_repo="$2"; shift 2;;
    --stack)         val_stack="$2"; shift 2;;
    --context)       val_context="$2"; shift 2;;
    --good)          val_good="$2"; shift 2;;
    --bad)           val_bad="$2"; shift 2;;
    --dry-run)       dry_run=true; shift;;
    -h|--help)       usage 0;;
    *) echo "Unknown argument: $1" >&2; usage 1;;
  esac
done

missing=""
for pair in "form_url:--form-url" \
            "field_repo:--field-repo" "field_stack:--field-stack" \
            "field_context:--field-context" "field_good:--field-good" \
            "field_bad:--field-bad" \
            "val_repo:--repo" "val_stack:--stack" "val_context:--context" \
            "val_good:--good" "val_bad:--bad"; do
  var="${pair%%:*}"; flag="${pair##*:}"
  if [[ -z "${!var}" ]]; then missing="$missing $flag"; fi
done
if [[ -n "$missing" ]]; then
  echo "Missing required:$missing" >&2
  exit 1
fi

args=( --data-urlencode "${field_repo}=${val_repo}"
       --data-urlencode "${field_stack}=${val_stack}"
       --data-urlencode "${field_context}=${val_context}"
       --data-urlencode "${field_good}=${val_good}"
       --data-urlencode "${field_bad}=${val_bad}" )
if [[ -n "$email" ]]; then
  args+=( --data-urlencode "emailAddress=${email}" )
fi

if $dry_run; then
  out="curl -s -X POST $form_url"
  i=0
  while [[ $i -lt ${#args[@]} ]]; do
    out="$out ${args[i]} '${args[i+1]}'"
    i=$((i+2))
  done
  echo "$out"
  exit 0
fi

status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$form_url" "${args[@]}")
if [[ "$status" == "200" ]]; then
  echo "OK Submitted (HTTP $status)"
else
  echo "FAILED (HTTP $status)" >&2
  exit 1
fi
```

- [ ] **Step 4: Make it executable and run the test to confirm it passes**

Run:
```bash
chmod +x scripts/submit_example.sh
./scripts/test_submit.sh
```
Expected: PASS — final line `pass=6 fail=0`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/submit_example.sh scripts/test_submit.sh
git commit -m "feat: add flag-driven submit_example.sh with behavioral tests"
```

---

### Task 3: `submitting-examples` skill (guided flow + discovery)

**Files:**
- Create: `skills/submitting-examples/SKILL.md`

**Interfaces:**
- Consumes: `scripts/submit_example.sh` (Task 2) via `${CLAUDE_PLUGIN_ROOT}`; `${CLAUDE_PLUGIN_DATA}/config.json` for the cached form URL + field map; `userConfig.form_url` (Task 1) when readable.
- Produces: the documented flow that `/good-claude` and `/bad-claude` (Task 4) defer to.

- [ ] **Step 1: Create `skills/submitting-examples/SKILL.md`**

````markdown
---
name: submitting-examples
description: Use when the user says "good claude" or "bad claude", or runs /good-claude or /bad-claude. Captures a good vs bad code example through a short guided flow and submits it to the configured Google Form.
---

# Submitting Good/Bad Code Examples

Capture one good example and one bad example of code or behavior and submit them
to the team's Google Form. Both examples are always collected; "good claude" just
asks for the good one first, "bad claude" asks for the bad one first.

## Step 0 — Ensure config exists (setup + discovery)

Read `${CLAUDE_PLUGIN_DATA}/config.json`.

- If it exists and contains `form_url` and all five `fields`, use it. Skip to Step 1.
- If it is missing or incomplete, run setup:
  1. Determine the form URL. If the user configured `form_url` (plugin user config)
     and it is available, use it. Otherwise ask: "What's the URL of the Google Form
     to submit examples to?"
  2. Fetch the form's HTML:
     `curl -sL "<viewform-url>"` (a `/viewform` URL is expected).
  3. In the HTML, find the `FB_PUBLIC_LOAD_DATA_` array. For each question extract
     its visible text and its `entry.<id>` (the numeric id in the question's field
     descriptor). Also note whether the form collects email (an `type="email"`
     input is present).
  4. Map questions to fields by keyword on the question text:
     `repository` → `repo`, `language`/`stack` → `stack`, `context` → `context`,
     `good` → `good`, `bad` → `bad`.
  5. If any field is unmatched or ambiguous, show the user the discovered questions
     and ask which maps to which. Do not guess silently.
  6. Normalize the form URL to its `/formResponse` endpoint and write
     `${CLAUDE_PLUGIN_DATA}/config.json`:
     ```json
     {
       "form_url": "https://docs.google.com/forms/d/e/<id>/formResponse",
       "collects_email": true,
       "fields": {
         "repo": "entry.<id>",
         "stack": "entry.<id>",
         "context": "entry.<id>",
         "good": "entry.<id>",
         "bad": "entry.<id>"
       }
     }
     ```

## Step 1 — Collect the two snippets

Ask for the good example first (for "good claude") or the bad example first (for
"bad claude"), then the other. The user may paste code or point at something from
the conversation ("the test I just wrote") — capture that snippet verbatim. Do not
submit if either snippet is empty; re-ask.

## Step 2 — Whys (optional, draftable)

For each example, the user picks one of:
- write their own why,
- have you draft one, or
- skip.

When asked to draft, infer a concise why from the snippet and context, show both
drafted whys, and ask **"Does this sound correct?"** The user accepts, edits, or
discards. A why that is neither written nor accepted is recorded as
`(to be inferred)`. **Never submit an inferred why without explicit confirmation.**

Assemble each paragraph field in this exact format:
```
CODE:
<snippet>

WHY:
<the why, or (to be inferred)>
```

## Step 3 — Infer the context fields

- `repo`: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
- `stack`: from repo signals — `Gemfile` → Ruby/Rails, `package.json` → JS/React,
  `go.mod` → Go, `pyproject.toml`/`requirements.txt` → Python, etc.
- `context`: a short label such as "rails testing" or "react testing", inferred
  from the snippet and what the user is doing.
- `email`: `git config user.email` (used only if `collects_email` is true).

## Step 4 — Preview & confirm

Show the full assembled submission: repo, stack, context, the good field, the bad
field, and the email. Let the user correct the inferred `stack`/`context`. Ask for
a final yes before sending.

## Step 5 — Submit

Read `form_url` and `fields` from `${CLAUDE_PLUGIN_DATA}/config.json` and run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/submit_example.sh" \
  --form-url "<form_url>" \
  --field-repo "<fields.repo>" --field-stack "<fields.stack>" \
  --field-context "<fields.context>" --field-good "<fields.good>" \
  --field-bad "<fields.bad>" \
  --repo "<repo>" --stack "<stack>" --context "<context>" \
  --good "<good field text>" --bad "<bad field text>" \
  --email "<email>"   # include only if collects_email is true and email is set
```

Run it once with `--dry-run` appended if you want to show the user the exact
request first. Report the result honestly: `OK Submitted` on success, or the
failure (never claim success on a non-200).

## Error handling

- No form URL and none configured → ask the user; do not proceed without one.
- Discovery cannot map a field → ask the user to map it; do not guess.
- No `git config user.email` and the form collects email → ask the user; never
  submit a blank email.
- Empty good or bad snippet → re-ask; do not submit.
- Non-200 / network failure → report it; do not claim success.
````

- [ ] **Step 2: Verify the skill file**

Run: `cat skills/submitting-examples/SKILL.md`
Confirm the frontmatter `name` is `submitting-examples`, the `description` names both "good claude" and "bad claude", and the submit invocation matches the flags from Task 2 exactly.

- [ ] **Step 3: Commit**

```bash
git add skills/submitting-examples/SKILL.md
git commit -m "feat: add submitting-examples skill with discovery and guided flow"
```

---

### Task 4: Slash commands

**Files:**
- Create: `commands/good-claude.md`
- Create: `commands/bad-claude.md`

**Interfaces:**
- Consumes: the `submitting-examples` skill (Task 3).
- Produces: `/good-claude` and `/bad-claude` entrypoints.

- [ ] **Step 1: Create `commands/good-claude.md`**

```markdown
---
description: Capture a good vs bad code example (good example first) and submit it to the team Google Form.
---

Use the `submitting-examples` skill to capture a good vs bad code example.
Frame the flow good-first: ask for the GOOD example first, then the BAD example.
Follow the skill exactly, including preview-and-confirm before submitting.
```

- [ ] **Step 2: Create `commands/bad-claude.md`**

```markdown
---
description: Capture a good vs bad code example (bad example first) and submit it to the team Google Form.
---

Use the `submitting-examples` skill to capture a good vs bad code example.
Frame the flow bad-first: ask for the BAD example first, then the GOOD example.
Follow the skill exactly, including preview-and-confirm before submitting.
```

- [ ] **Step 3: Verify**

Run: `cat commands/good-claude.md commands/bad-claude.md`
Confirm each has a `description` in frontmatter and defers to the `submitting-examples` skill.

- [ ] **Step 4: Commit**

```bash
git add commands/good-claude.md commands/bad-claude.md
git commit -m "feat: add /good-claude and /bad-claude slash commands"
```

---

### Task 5: README (setup guide + manual test checklist)

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: everything above (install steps, usage, maintainer notes).

- [ ] **Step 1: Create `README.md`**

````markdown
# good-claude-bad-claude

A Claude Code plugin to capture "good vs bad" code examples and submit them to a
shared Google Form — fuel for team style guides.

Say **good claude** or **bad claude** (or run `/good-claude` / `/bad-claude`).
The plugin asks for a good example and a bad example, optionally drafts a *why*
for each (with your confirmation), infers your repo / stack / context, previews
the submission, and posts it to your form.

## Install

```
/plugin marketplace add <owner>/good-claude-bad-claude
/plugin install good-claude-bad-claude
```

On enable you'll be asked for your **Google Form URL** (the `/viewform` link).
Everyone on a team enters the same URL, so all submissions land in one form.
Nothing form-specific is stored in this repo.

## Use it

1. Say `good claude` (or `bad claude`), or run `/good-claude`.
2. Provide the good example, then the bad example.
3. Optionally add or have a *why* drafted for each.
4. Review the preview and confirm. Done.

## Your Google Form

The plugin works with any Google Form whose questions cover: repository,
language/stack, context, the good example, and the bad example. It auto-discovers
the field IDs from the form URL on first use. Set the form to **collect email
(Responder input)** if you want submissions attributed.

## For maintainers (forking)

1. Fork this repo under your own GitHub user or org — that is `<owner>` above.
2. Create your Google Form with the five questions and share its `/viewform` URL
   with your team.
3. (Optional) Make the fork public or host it under an org for wider rollout; a
   private fork only installs for users whose git is authenticated to it.

## Development

Run the script tests:

```
./scripts/test_submit.sh
```

### Manual test checklist (the prompt-driven flow)

- [ ] `/plugin marketplace add ./` then install locally; enable and set the form URL.
- [ ] First `good claude` run performs discovery and writes
      `~/.claude/plugins/data/<plugin-id>/config.json` with five field IDs.
- [ ] Drafted whys prompt "Does this sound correct?" and are not submitted unedited
      without confirmation.
- [ ] Preview shows repo / stack / context / good / bad / email; submitting returns
      `OK Submitted` and a row appears in the form.
- [ ] A second run reuses `config.json` (no rediscovery).
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install, usage, and manual test checklist"
```

---

### Task 6: End-to-end verification (manual)

**Files:** none (verification only).

**Interfaces:**
- Consumes: the whole plugin.

- [ ] **Step 1: Install the plugin locally**

In a Claude Code session rooted in the repo:
```
/plugin marketplace add ./
/plugin install good-claude-bad-claude
```
Enable it and provide a real test Google Form URL when prompted.

- [ ] **Step 2: Run the flow with a dry run first**

Say `good claude`, provide a throwaway good and bad snippet, let it infer context,
and at Step 5 use `--dry-run` to inspect the exact curl. Confirm every `entry.*`
maps to the right value and `emailAddress` is present (if the form collects email).

- [ ] **Step 3: Do one real submission and verify**

Submit for real. Expected: `OK Submitted (HTTP 200)` and a new row in the form's
responses with the good/bad fields in the `CODE:/WHY:` format and the email
populated. Delete the test row afterward.

- [ ] **Step 4: Verify config reuse**

Run `good claude` again. Expected: no rediscovery — it reads the existing
`config.json` and goes straight to collecting snippets.

- [ ] **Step 5: Record results**

Note any failures and fix them in the relevant task's files before declaring done.
