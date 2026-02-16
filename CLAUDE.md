# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A personal dotfiles repository managed with [chezmoi](https://www.chezmoi.io/) (v2.15.1+). It provisions macOS (primary) and Linux machines with shell config, packages, git settings, SSH keys, and application preferences. Secrets come from 1Password via the `op` CLI.

## Key Commands

```sh
chezmoi apply              # Apply all changes to the home directory
chezmoi apply --dry-run    # Preview what would change
chezmoi diff               # Show diff between source and target
chezmoi execute-template < file.tmpl  # Debug template rendering
chezmoi data               # Show template data (feature flags, hostname, etc.)
chezmoi managed            # List all managed files
chezmoi add ~/path/to/file # Add a new file to be managed
```

## Architecture

### Source Root

`.chezmoiroot` sets `home/` as the chezmoi source directory. All managed files live under `home/`, not the repo root. The repo root contains only chezmoi metadata (`.chezmoiignore`, `.chezmoiversion`) and the install script.

### Chezmoi Naming Conventions

Files use chezmoi's naming scheme to control target attributes:
- `dot_` → `.` (e.g., `dot_zprofile.tmpl` → `~/.zprofile`)
- `private_dot_` → `.` with restricted permissions (e.g., `private_dot_ssh/` → `~/.ssh/`)
- `.tmpl` suffix → processed as Go text/template
- `run_onchange_before_` / `run_onchange_after_` → scripts that run when their content changes, in sort order

### Template Data and Feature Flags

`home/.chezmoi.toml.tmpl` defines machine-specific data based on hostname:
- `docker`, `kubernetes`, `radixils`, `personal` — boolean feature flags
- `hostname`, `osid`, `vault` — machine identity

Hostname is resolved via `scutil --get ComputerName` on macOS (maps friendly names → `pvb-mba`, `pvb-mbp`, etc.). Templates use these flags to conditionally include config blocks, secrets, and packages.

### Scripts (Execution Order)

Scripts in `home/.chezmoiscripts/darwin/` run on `chezmoi apply` when their content changes:

1. `run_onchange_before_10-install-general-packages.sh.tmpl` — Homebrew bundle (taps, brews, casks, Mac App Store apps)
2. `run_onchange_after_09_home-folders.sh.tmpl` — Creates directory structure (`~/git`, `~/bin`, `~/.cache`, etc.)
3. `run_onchange_after_10-setup-asdf.sh.tmpl` — Configures asdf version manager
4. `run_onchange_after_15-configure-radixils-environments.sh.tmpl` — Work-specific environment setup (gated on `radixils` flag)
5. `run_onchange_after_configure.sh.tmpl` — macOS `defaults write` preferences (Dock, Finder, keyboard, trackpad, iTerm2, Chrome)

### External Dependencies

`home/.chezmoiexternal.toml` pulls archives/files that aren't committed to the repo:
- oh-my-zsh + plugins (zsh-autosuggestions, zsh-syntax-highlighting)
- powerlevel10k theme (pinned to v1.16.1)
- iTerm2 color schemes
- `age` binary (Linux only)

### Secrets

Secrets are templated from 1Password using `onepasswordDetailsFields`. The vault ID is stored in `.chezmoi.toml.tmpl` as `vault`. Files containing secrets include SSH keys (`private_dot_ssh/`), AWS config, git credentials, and zshrc API keys. The 1Password CLI (`op`) must be authenticated before `chezmoi apply`.

## Conventions

- All scripts target bash with `set -eufo pipefail`
- Package lists in scripts use chezmoi's `list` template function with `sortAlpha | uniq` for deterministic ordering
- Templates end with a vim modeline comment (e.g., `{{/* vim: set filetype=zsh: */}}`)
- The `.chezmoiignore` uses chezmoi template syntax to conditionally ignore files per OS
- Git config uses `includeIf` for work-specific overrides (Radix ILS repos under `~/git/rdx/`)
