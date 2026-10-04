# Architecture

## Source layout

| Path | Role |
| --- | --- |
| `install.sh` | One-command bootstrap: role, Homebrew, 1Password, age key, `chezmoi init --apply` |
| `bin/` | Repo tooling (`check`, `drift`, `bump-versions`, secret helpers). Not deployed. |
| `home/` | chezmoi source root (`.chezmoiroot`) |
| `home/.chezmoi.toml.tmpl` | Prompts (`machineRole`, `manageBrew`), flags, age recipients |
| `home/.chezmoidata/*.yaml` | Packages, version pins, SSH public keys, OneDrive paths |
| `home/.chezmoiexternal.toml` | Pinned archives: oh-my-zsh, plugins, powerlevel10k, agent skills |
| `home/.chezmoiignore` | Role gating (what a role never gets) |
| `home/.chezmoiremove` | Retired targets, deleted on apply |
| `home/.secrets/<role>/` | age payloads, readable only with that role's key |
| `home/.chezmoiscripts/` | `run_onchange_` scripts |

## Template data

`chezmoi init` asks two questions once and stores the answers:

- `machineRole`: `personal` or `work`. Derived: `.personal`, `.radixils`.
- `manageBrew`: whether this account owns Homebrew (one account per Mac).

`.ageRecipients` holds both roles' public keys; `[age].recipient` is this
role's. Everything else comes from `home/.chezmoidata/`.

## Apply flow

```mermaid
flowchart TD
  A[chezmoi apply] --> B[render config + data]
  B --> C[before_08 machine-sync: OneDrive tree, adopt ~/.claude/plans<br/>work only]
  C --> D[before_10 general packages: brew bundle check || brew bundle<br/>manageBrew only]
  D --> E[files, symlinks, externals, modify_ merges]
  E --> F[after_09 home folders]
  F --> G[after_10 mise install + compat links]
  G --> H[after_15 work tooling: work Brewfile + rdx Brewfile, direnv allow<br/>work only]
  H --> I[after_16 backup launch agent<br/>work only]
  I --> J[after_configure macOS defaults, firewall, update checks<br/>needs sudo]
```

Every script is `run_onchange_`: it reruns only when its rendered content
changes. Scripts that depend on files outside the source embed their hash
(e.g. the mise config, rdx's Brewfile) so a change there re-triggers them.

## Externals

All pinned in `home/.chezmoidata/versions.yaml` (commit SHAs or tags), so no
`refreshPeriod` is needed and applies never fetch unexpectedly:

- oh-my-zsh (commit), zsh-autosuggestions, zsh-syntax-highlighting, powerlevel10k (tags)
- agent skills under `~/.agents/skills`, symlinked into `~/.claude/skills`
- iTerm2 colour schemes (weekly refresh)

`bin/bump-versions` lists each pin next to the latest upstream.
