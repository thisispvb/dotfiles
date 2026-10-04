# CLAUDE.md

Guidance for Claude Code and other agents working in this repository.

## What this is

Personal dotfiles for macOS (only), managed with [chezmoi](https://www.chezmoi.io/)
(v2.73.0+, pinned in `home/.chezmoiversion`). One source tree provisions both
personal and work (Radix ILS) Macs; the machine role decides what each gets.
The repo is **public**: never commit secrets, emails, account IDs, vault/item
names or internal hostnames outside age-encrypted files.

## Commands

```sh
bin/check                  # render every template for both roles and lint (run before committing)
bin/drift                  # how this machine deviates (brew + chezmoi status)
bin/bump-versions          # pinned versions vs latest upstream
chezmoi diff               # review before applying
chezmoi apply              # apply (scripts may need sudo: run in a real terminal)
chezmoi execute-template < file.tmpl   # debug a template
bin/edit-secret <name>     # edit this role's encrypted secret
bin/encrypt-secret <role> <name> [file] # add/replace a secret for a role
```

## Layout

- `.chezmoiroot` = `home/`: every managed file lives under `home/`. The repo root
  holds `install.sh`, `bin/` (repo tooling, not deployed), `docs/`, CI and hooks.
- `home/.chezmoi.toml.tmpl`: two prompts, `machineRole` (`personal`|`work`) and
  `manageBrew` (only one account per Mac manages Homebrew). Derived flags:
  `.personal`, `.radixils`. Also the per-role age recipients.
- `home/.chezmoidata/`: `packages.yaml`, `versions.yaml` (all pins),
  `ssh.yaml` (public keys), `machine-sync.yaml`.
- `home/.chezmoiignore` / `.chezmoiremove`: role gating and retired targets.
- `home/.chezmoiexternal.toml`: oh-my-zsh, plugins, powerlevel10k, agent skills,
  all pinned via `versions.yaml`.
- `home/.secrets/<role>/*.age`: encrypted payloads, included by thin templates.

Details: `docs/architecture.md`, `docs/roles.md`, `docs/secrets.md`,
`docs/tooling.md`, `docs/new-machine.md`.

## Conventions

- Paths: `~`, `$HOME` or `{{ .chezmoi.homeDir }}`, never `/Users/<name>`.
- Scripts: bash, `set -eufo pipefail`, shellcheck- and `shfmt -i 2 -ci`-clean.
  `run_onchange_` scripts must be idempotent; to re-trigger on an external
  input, embed its hash in a comment.
- Package lists render with `sortAlpha | uniq`; brew scripts use
  `brew bundle check` so unchanged lists are a fast no-op.
- Files the app rewrites at runtime (Claude `settings.json`, `colima.yaml`) are
  `modify_` scripts that merge managed keys into the live file.
- Toolchains (node, pnpm, python, go) come from mise shims, pinned in
  `versions.yaml`. Work machines follow rdx's pins.
- Zsh: edit `path=(...)` arrays, never `PATH=...` (`typeset -U` only dedupes
  arrays). `~/.zshenv` stays tiny: it runs for every agent shell.
- Work env vars and tokens load through direnv under `~/git/rdx` only, never in
  every shell.
- Agents: run `bin/check` before committing. Don't run `chezmoi apply` from a
  non-interactive shell when the macOS defaults script is pending (it needs sudo).
