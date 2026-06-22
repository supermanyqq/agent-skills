# Agent Skills

Personal agent skills collection.

## Install

Install every bundled skill:

```bash
npx agent-skills --force
```

Install one skill:

```bash
npx agent-skills --skill review-plan-implementation --force
```

List bundled skills:

```bash
npx agent-skills --list
```

The installer copies skills into `${CODEX_HOME}/skills`, or `~/.codex/skills` when `CODEX_HOME` is not set.

## Included Skills

- `review-plan-implementation`: review whether code implementation strictly matches a plan, spec, acceptance criteria, or task breakdown.
