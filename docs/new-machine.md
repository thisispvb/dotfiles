# Setting up a new work Mac

`install.sh` (see the README) gets the dotfiles, packages, and shell onto a new
machine. This file covers what it *doesn't* — the gaps hit while migrating in
August 2026. Where a gap is scriptable, fix it upstream in the owning repo's
Taskfile and replace the entry here with a link.

## 1. Machine state that no repo holds

Claude Code's transcripts, plans, memory, and per-project prompt history live
only on the machine that made them, as do repo-local `.env*` files and
`rdx-web/tmp/`. They sync through OneDrive, not git.

**Before retiring the old Mac:**

1. `chezmoi apply` — creates `MachineSync/` in OneDrive, moves `~/.claude/plans`
   into it, installs the backup scripts.
2. `machine-state-backup.sh --dry-run`, then `machine-state-backup.sh`.
3. Wait for the OneDrive menu bar to say **up to date** — roughly a gigabyte.

**On the new Mac:**

1. Sign in to OneDrive, then right-click `MachineSync/` → **Always Keep on This
   Device**. Without the pin, macOS can evict the contents and `~/.claude/plans`
   points at dataless files.
2. `chezmoi init --apply thisispvb` (or `chezmoi update`).
3. Clone the repos under `~/git/rdx`, then `machine-state-restore.sh <old-hostname>`.
4. `direnv allow` in each restored repo; restart Claude Code so it re-reads
   `~/.claude.json`.

The backup is additive and per-hostname, so restoring never races the daily
launchd agent (`com.pvb.machine-state-backup`, 13:30, logs to
`~/Library/Logs/machine-state-backup.log`).

Because `~/.claude/plans` is a symlink, plan-mode writes land outside the working
directory and Claude Code prompts for each one. `settings.json.tmpl` pre-authorizes
them — `additionalDirectories` plus allow rules for *both* the symlink path and its
resolved OneDrive target, since path rules are matched against each. The rules are
scoped to `claude/plans`; never widen them to the OneDrive root, which holds company
files. If plan writes start prompting again, that block is the first place to look.

What is deliberately *not* synced: caches, `shell-snapshots/`, `file-history/`,
`sessions/`, and live session resume across machines. Transcripts are durable;
an in-flight session is not portable.

## 2. Tailscale / headscale

1. Register the machine, then authorize it at
   <https://headscale.mgmt.rdxils.com/admin/machines>. This can be done from any
   already-authorized machine.
2. **Accept subnet routes** — in the macOS Tailscale client this is the "Use
   Tailscale subnets" setting. Without it Keycloak and the other internal
   services are unreachable *while connected to Tailscale*, which reads like a
   DNS problem and isn't one.
3. Disconnect and reconnect after changing it.

Prefer the CLI form when the client supports it, since it is re-runnable:

```sh
tailscale set --accept-routes
```

## 3. `rdx` repo, beyond `task setup`

```sh
git submodule update --init
task sops:regenerate-env
```

Then fetch the AIR data (see the `rdx` repo's own docs — it is not part of
`task setup`).

Some environment keys are not covered by setup and have to be pulled from
1Password by hand. Names and locations only — never paste values into this repo:

| Key | Where it lives | Symptom when missing |
| --- | --- | --- |
| `BROKER_ENCRYPTION_KEY` | 1Password, RDX vault | Broker credential writes 500 locally |
| HSBCBM signing keypair | 1Password, RDX vault | SWIFT pre-validation 502s at the wire |

`.envrc` and the app `.env*` files are not produced by `task setup` either —
they come from the state restore in §1, and need `direnv allow` afterwards.

## 4. `rdx-cloudformation`

`task setup` fails against the decommissioned ext cluster until
<https://github.com/RadixILS-Dev/rdx-cloudformation/pull/128> merges. Delete this
section once it does.

## 5. Last pass

Search the *old* machine's shell history for setup commands this file missed:

```sh
grep -E 'task |brew install|tailscale|sops' ~/.zsh_history | sort -u | less
```

`machine-state-backup.sh --with-shell-history` copies `~/.zsh_history` into
OneDrive for exactly this — it is opt-in because command lines can carry secrets.
