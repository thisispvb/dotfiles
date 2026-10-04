# Roles: personal vs work

`machineRole` is the single switch. This is the boundary map for a future
split of the work layer into its own repo: everything below marked *work*
moves, everything else stays.

| Area | Personal | Work | Where |
| --- | --- | --- | --- |
| age key | personal key | work key | `.chezmoi.toml.tmpl`, `.secrets/<role>/` |
| SSH key | personal | work | `private_dot_ssh/private_id_ed25519.tmpl`, `.chezmoidata/ssh.yaml` |
| `authorized_keys` | all keys on the GitHub account | work key only | `private_dot_ssh/authorized_keys.tmpl` |
| Git identity | default | work email in `~/git/rdx/**` and any work-org clone | `private_dot_config/git/config.tmpl`, `private_dot_config/rdx/gitconfig` |
| Packages | general list | + `packages.darwin.work`, + rdx's own Brewfile | `.chezmoidata/packages.yaml`, `run_onchange_after_15-*` |
| Toolchain | latest Node/pnpm | rdx's pinned Node/pnpm, + Go | `private_dot_config/mise/config.toml.tmpl` |
| Env and tokens | none | direnv, under `~/git/rdx` only | `private_dot_config/direnv/direnvrc`, `private_dot_config/rdx/envrc`, `git/rdx/dot_envrc` |
| Shared caches | none | Turbo, uv, Go caches in `~/.zshenv` | `dot_zshenv.tmpl` |
| Cloud/containers | none | AWS profiles, Docker/colima, kubectl (AWS and ECR identifiers age-encrypted) | `private_dot_aws/`, `private_dot_docker/`, `private_dot_config/colima/`, `.secrets/work/` |
| Claude Code | shared settings | + work repo dirs, plans in OneDrive | `private_dot_claude/modify_settings.json.tmpl` |
| Machine-state backup | none | OneDrive, secrets age-encrypted | `private_dot_local/bin/executable_machine-state-*`, `private_Library/LaunchAgents/` |
| Obsidian vault tooling | yes | no | `.chezmoiignore` |
| AirPlay receiver | on | off (port clash) | `run_onchange_after_configure.sh.tmpl` |

## Contract with the rdx repo

- rdx owns repo tooling: its `Brewfile`, `task setup`, pre-commit hooks, and the
  pinned DuckDB. Dotfiles bundle rdx's Brewfile when the checkout exists.
- Dotfiles own machine setup: shell, AWS/kubectl config, git identity, Claude
  Code globals, shared caches.
- rdx's agent skills assume `~/.claude/plans` and the codex plugin exist; both
  come from these dotfiles.
