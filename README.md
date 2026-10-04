# github.com/thisispvb/dotfiles

Philip's macOS dotfiles, managed with [chezmoi](https://www.chezmoi.io/). One
tree serves personal and work Macs; the machine role picks what each gets.

## New machine

    sh -c "$(curl -fsLS https://raw.githubusercontent.com/thisispvb/dotfiles/main/install.sh)"

It asks for the machine role (or reads `MACHINE_ROLE=personal|work`), installs
Homebrew and 1Password, fetches that role's age key from 1Password (or asks you
to paste it), then runs `chezmoi init --apply`. See
[docs/new-machine.md](docs/new-machine.md) for what it doesn't cover.

## Day to day

```sh
chezmoi diff && chezmoi apply   # review, then apply
bin/check                       # lint every template for both roles
bin/drift                       # what differs on this machine
bin/bump-versions               # pinned versions vs upstream
```

## Docs

- [Architecture](docs/architecture.md): layout, data, scripts, externals
- [Roles](docs/roles.md): what differs between personal and work
- [Secrets](docs/secrets.md): per-role age keys, adding and rotating secrets
- [Tooling](docs/tooling.md): mise, Homebrew, shell, agent shells, checks
