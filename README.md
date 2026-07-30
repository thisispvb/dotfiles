# github.com/thisispvb/dotfiles

Philip's dotfiles, managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

## New machine: one command

    sh -c "$(curl -fsLS https://raw.githubusercontent.com/thisispvb/dotfiles/main/install.sh)"

This bootstraps everything in one go: it provisions the age key that encrypts
the repo's secrets (fetched from 1Password via `op` if available, otherwise it
prompts you to paste the key), installs `chezmoi` if needed, clones this repo,
and applies the dotfiles.

If `chezmoi` and the age key (`~/.config/chezmoi/key.txt`) are already in
place, this works too:

    chezmoi init --apply thisispvb

## How secrets work

Secrets are age-encrypted directly in this repo and decrypted transparently by
chezmoi during `apply`/`diff`/`edit`. The only thing a new machine needs is
the age identity at `~/.config/chezmoi/key.txt`, which the bootstrap above
restores from 1Password. There is no per-apply `op` dependency.

To change a secret, run `chezmoi edit <file>` — it decrypts to a temp file and
re-encrypts on save. To add a new secret file, use `chezmoi add --encrypt <file>`.
