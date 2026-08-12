# github.com/thisispvb/dotfiles

Philip's dotfiles, managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

## New machine: one command

    sh -c "$(curl -fsLS https://raw.githubusercontent.com/thisispvb/dotfiles/main/install.sh)"

This bootstraps everything in one go. On a fresh Mac it installs Homebrew
(which brings the Xcode Command Line Tools) and the 1Password app + CLI, walks
you through signing in to 1Password and enabling its CLI integration, then
fetches the age key that encrypts the repo's secrets automatically. It
installs `chezmoi` if needed, clones this repo, and applies the dotfiles. On
Linux, or if the 1Password setup is skipped, it prompts you to paste the age
key instead.

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
