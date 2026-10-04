# Secrets

## Model

- Secrets are [age](https://age-encryption.org)-encrypted files in
  `home/.secrets/<role>/`, committed to this public repo.
- There is one age key per role. A Mac holds only its own role's key at
  `~/.config/chezmoi/key.txt` (mode 600, not managed by chezmoi), so a work Mac
  cannot decrypt personal secrets and vice versa.
- Both public keys (recipients) are in `home/.chezmoi.toml.tmpl` and are safe
  to publish.
- Targets are thin templates that decrypt at apply time:

  ```
  {{ include (printf ".secrets/%s/id_ed25519.age" .machineRole) | decrypt }}
  ```

  chezmoi skips dot-prefixed source paths, so `.secrets/` itself is never deployed.

## Backups of the private keys

Each role's private key is in 1Password, as the `credential` field of a
dedicated API Credential item (one item per role, both in the same vault).
`install.sh` holds the two item IDs and fetches the right one for the chosen
role. Keep the items in sync with what's on disk: a key that exists only on a
laptop is one disk failure away from losing every secret of that role.

## Everyday tasks

| Task | Command |
| --- | --- |
| Edit a secret of this machine's role | `bin/edit-secret <name>`, then `chezmoi apply` |
| Add or replace a secret (either role) | `bin/encrypt-secret <role> <name> [file]` |
| Use it | add a template with `{{ include ".secrets/<role>/<name>.age" \| decrypt }}` and gate it in `.chezmoiignore` if it is role-specific |

Encrypting needs only the public key, so you can add a secret for the other
role. Reading or editing it needs that role's machine.

## Rotating a role's key

1. `age-keygen -o ~/.config/chezmoi/key.new.txt` on a machine of that role (never inside the repo).
2. Re-encrypt every file in `home/.secrets/<role>/`:
   `age -d -i ~/.config/chezmoi/key.txt <f> | age -a -r <new recipient> -o <f>.new && mv <f>.new <f>`.
3. Replace the recipient in `home/.chezmoi.toml.tmpl`, then update the 1Password
   item's `credential` and `public key` fields.
4. Install the new key at `~/.config/chezmoi/key.txt` on each machine of that
   role, then run `chezmoi init` there.
5. Check that `chezmoi diff` is clean, then commit. Old ciphertexts remain in git history,
   so rotate the underlying secrets too if the old key leaked.

## Machine-state backup

`machine-state-backup.sh` (work) writes `~/.claude.json` and the repos'
`.env*`/`.envrc` into a single `secrets.tar.age`, encrypted to this role's
recipient, before anything reaches OneDrive. `machine-state-restore.sh`
decrypts it with the local key and never overwrites a newer local file.

## Tokens in shells

Work tokens never go into every shell. direnv loads them under `~/git/rdx`
only (`~/.config/direnv/direnvrc` → `~/.config/rdx/envrc` → `secrets.zsh`), and
they unload when you `cd` out. Agents started elsewhere don't inherit them.
