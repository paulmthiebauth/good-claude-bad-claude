---
name: submitting-examples
description: Use when the user says "good claude" or "bad claude", or runs /good-claude or /bad-claude. Captures a good vs bad code example through a short guided flow and submits it to the configured Google Form.
---

# Submitting Good/Bad Code Examples

Capture one good example and one bad example of code or behavior and submit them
to the team's Google Form. Both examples are always collected; "good claude" just
asks for the good one first, "bad claude" asks for the bad one first.

## Step 0 - Ensure config exists (setup + discovery)

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
     descriptor). Also note whether the form collects email (a `type="email"`
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

## Step 1 - Collect the two snippets

Ask for the good example first (for "good claude") or the bad example first (for
"bad claude"), then the other. The user may paste code or point at something from
the conversation ("the test I just wrote") - capture that snippet verbatim. Do not
submit if either snippet is empty; re-ask.

## Step 2 - Whys (optional, draftable)

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

## Step 3 - Infer the context fields

- `repo`: `basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
- `stack`: from repo signals - `Gemfile` → Ruby/Rails, `package.json` → JS/React,
  `go.mod` → Go, `pyproject.toml`/`requirements.txt` → Python, etc.
- `context`: a short label such as "rails testing" or "react testing", inferred
  from the snippet and what the user is doing.
- `email`: `git config user.email` (used only if `collects_email` is true).

## Step 4 - Preview & confirm

Show the full assembled submission: repo, stack, context, the good field, the bad
field, and the email. Let the user correct the inferred `stack`/`context`. Ask for
a final yes before sending.

## Step 5 - Submit

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
