---
name: submitting-examples
description: Use when the user says "good claude" or "bad claude", or runs /good-claude or /bad-claude. Captures a good vs bad code example and submits it to the team's Google Form.
allowed-tools: Bash(git *), Bash(basename *), Bash(cat *), Bash(ls *)
---

# Submitting Good/Bad Code Examples

Capture one good example and one bad example of code or behavior and submit them
to the team's Google Form. Both examples are always collected; "good claude" just
asks for the good one first, "bad claude" asks for the bad one first. After
submitting, you can optionally save a personal "apply-now" rule to your Claude
memory so the lesson takes effect immediately, without waiting for a formal style
guide (see Step 6).

## Environment (injected at load)

- Existing config: !`cat "${CLAUDE_PLUGIN_DATA}/config.json" 2>/dev/null || echo "MISSING"`
- Repo: !`basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
- Stack signal files: !`ls -1 Gemfile package.json go.mod pyproject.toml requirements.txt Cargo.toml pom.xml 2>/dev/null || true`
- Git email: !`git config user.email 2>/dev/null || echo "(none)"`

## Step 0 - Ensure config exists

Use the injected **Existing config** above.

- If it is valid JSON with `form_url` and all five `fields`, use it and skip to Step 1.
- If it is `MISSING` or incomplete, run the one-time setup in
  [references/discovery.md](references/discovery.md) — it writes
  `${CLAUDE_PLUGIN_DATA}/config.json` — then continue.

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

For a calibrated *why* and the Step 6 rule, see
[examples/worked-example.md](examples/worked-example.md).

## Step 3 - Infer the context fields

Use the injected environment above:

- `repo`: the injected **Repo** value.
- `stack`: map the injected **Stack signal files** - `Gemfile` → Ruby/Rails,
  `package.json` → JS/React, `go.mod` → Go, `pyproject.toml`/`requirements.txt`
  → Python, `Cargo.toml` → Rust, etc.
- `context`: a short label such as "rails testing" or "react testing", inferred
  from the snippet and what the user is doing.
- `email`: the injected **Git email** (used only if `collects_email` is true).
  If it is `(none)` and the form collects email, ask the user; never submit a
  blank email.

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

## Step 6 - Save an "apply-now" rule (optional)

The Google Form feeds the team's *future* style guides. This step gives the
submitter an *immediate* benefit: a personal rule Claude applies right away.

1. Synthesize one concise, imperative rule from the example:
   `When <context>, prefer <good>; avoid <bad>. Why: <why>.`
   Use the accepted why; if it was skipped, infer a brief one.
2. Show the rule and ask where to save it:
   - **A) Project memory** - personal to you, scoped to this repo, not committed.
   - **B) Global memory** - applies to you in every repo.
   - **C) Don't save.**
3. **On A:** save it to this project's built-in Claude auto-memory - do NOT
   hardcode `~/.claude/projects/...`; use the project memory that Claude Code
   manages. Write the full rule as a topic memory file with frontmatter (`name`,
   `description`, `metadata.type: feedback`) and a body with **Why:** and **How to
   apply:** lines, then add a concise, actionable one-line pointer to `MEMORY.md`.
   The pointer line must carry the gist, since only the top of `MEMORY.md`
   auto-loads. If a topic file already covers this subject, update it instead of
   duplicating.
   **On B:** append the rule to `~/.claude/CLAUDE.md` under the heading
   `## Good/Bad conventions (via good-claude-bad-claude)` (create the heading if
   missing); skip if an identical line already exists.
   **On C:** do nothing.

This step is additive: it never changes or blocks the Step 5 form submission. If
the memory write fails, say so — the form submission already succeeded and the
two are independent.
