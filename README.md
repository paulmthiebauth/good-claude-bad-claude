# good-claude-bad-claude

A Claude Code plugin to capture "good vs bad" code examples and submit them to a
shared Google Form - fuel for team style guides.

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
