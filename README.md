# github.com/thisispvb/dotfiles

Philip's dotfiles, managed with [`chezmoi`](https://github.com/twpayne/chezmoi).

Install and apply them with:

    chezmoi init --apply thisispvb

    # alternatively if `chezmoi` isn't installed yet:
    sh -c "$(curl -fsLS chezmoi.io/get)" -- init --apply thisispvb

Personal/Work secrets are stored in [1Password](https://1password.com/), and you'll need
the [1Password CLI](https://developer.1password.com/docs/cli/get-started) installed.
Login to 1Password for the first time with:

    op account add --address my.1password.eu --email p@bargen.co
    eval $(op signin)

Then, to login afterwards, run:

    eval $(op signin)
