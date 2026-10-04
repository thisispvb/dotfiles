# Tooling

## Toolchains: mise

- `~/.config/mise/config.toml` (rendered from `versions.yaml`) pins node, pnpm,
  python and, on work machines, go. Work machines take rdx's Node/pnpm pins, so
  `pnpm install` in any worktree never downloads a runtime.
- Tools resolve through **shims** (`~/.local/share/mise/shims`), which honour
  per-project pins (`.mise.toml`, `.node-version`, `.nvmrc`) on every call.
- `mise activate` is deliberately not used: it costs ~40 ms per shell start, and
  shims already handle versions. Per-directory env vars are direnv's job.
- The old pnpm-managed runtime paths (`~/.local/share/pnpm/pnpm`,
  `~/.local/share/pnpm/bin/{node,npm,npx}`) are links to the shims, so shells
  and tools started before the switch keep working.

## Shell startup

| File | Runs for | Does |
| --- | --- | --- |
| `~/.zshenv` | every zsh, including `zsh -c` and agent shells | `typeset -U path`, mise shims, work caches. No subprocesses. |
| `~/.zprofile` | login shells | Homebrew env (static, no `brew shellenv`), Go, pnpm globals, shims ahead of brew (macOS `path_helper` reorders) |
| `~/.zshrc` | interactive | oh-my-zsh + powerlevel10k (instant prompt), aliases, direnv hook |

Warm `zsh -i -c exit` takes about 70 ms; measure with `hyperfine 'zsh -i -c exit'`.

## Homebrew

`packages.yaml` renders to Brewfiles in the `run_onchange_before_10` and
`after_15` scripts. They run `brew bundle check` first, so an unchanged list
costs about a second. Only the account with `manageBrew = true` installs.
Removing a package from the list does not uninstall it; `bin/drift` lists
what's installed but unlisted.

## Checks

- `bin/check`: renders every template for both roles with throwaway answers
  (nothing decrypted), then runs shellcheck, shfmt, `zsh -n`, jq, plutil and a
  TOML parse, and feeds the `modify_` scripts empty input. It takes about 2 s.
- `lefthook.yml` (`lefthook install` once per clone): shellcheck, shfmt,
  plutil, gitleaks on staged changes, a hard-coded-home-path guard, a docs leak
  guard (emails, account IDs, 1Password paths, internal hosts), and `bin/check`.
- CI (`.github/workflows/check.yml`, macOS) runs `bin/check` and a full-history
  gitleaks scan.
- `bin/drift`: missing or unlisted brew packages, plus `chezmoi status`.
- `bin/bump-versions`: every pin next to its latest upstream release.
