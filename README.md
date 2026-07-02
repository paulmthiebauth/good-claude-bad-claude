# good-claude-bad-claude

A Claude Code plugin to capture "good vs bad" code examples and submit them to a
shared Google Form - fuel for team style guides.

Say **good claude** or **bad claude** (or run `/good-claude` / `/bad-claude`).
The plugin asks for a good example and a bad example, optionally drafts a *why*
for each (with your confirmation), infers your repo / stack / context, previews
the submission, and posts it to your form. It can then also save the lesson as a
personal *apply-now* rule so you benefit immediately - see below.

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
4. Review the preview and confirm - it posts to the form.
5. Optionally save the lesson as a personal *apply-now* rule (project / global / no).

## Apply-now memory

The Google Form feeds the team's *future* style guides. To get value immediately,
the plugin can also save the lesson as a personal rule that Claude applies right
away. After submitting, it synthesizes a short "when X, prefer Y, not Z" rule and
asks where to keep it:

- **Project** - saved to this repo's Claude memory: personal to you, scoped to the
  repo, and never committed (it lives under `~/.claude`, not in the repo).
- **Global** - appended to `~/.claude/CLAUDE.md`, so it applies in every repo.
- **No** - skip; only the form submission happens.

Project memory uses Claude Code's built-in auto-memory (v2.1.59+); on older
versions, use the global option.

## Your Google Form

The plugin works with any Google Form whose questions cover: repository,
language/stack, context, the good example, and the bad example. It auto-discovers
the field IDs from the form URL on first use. Set the form to **collect email
(Responder input)** if you want submissions attributed.

## For maintainers (forking)

1. Fork this repo under your own GitHub user or org - that is `<owner>` above.
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
- [ ] After submit: choosing **Project** writes a rule to project memory and a
      pointer in `MEMORY.md`; **Global** appends to `~/.claude/CLAUDE.md`; **No**
      writes nothing.
