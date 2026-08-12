#!/usr/bin/env bash

set -e # -e: exit on error

# Overridable so the provisioning path can be exercised against a temp file.
AGE_KEY_FILE="${AGE_KEY_FILE:-$HOME/.config/chezmoi/key.txt}"
AGE_ACCOUNT="my.1password.eu"
AGE_ITEM_UUID="jb7rxvjrxlp7kkhiieipzeruvy"
AGE_KEY_ATTACHMENT_NAME="key.txt"
MAX_KEY_ATTEMPTS=3

# Extract the secret key line from any source: an op field value, a full
# key.txt (including comment lines), or a raw paste.
extract_age_key() {
  grep -om1 'AGE-SECRET-KEY-1[A-Z0-9]*'
}

# 0 if /dev/tty can actually be opened. `[ -r /dev/tty ]` only checks the device
# node's permissions and is true even where there is no controlling terminal, so
# the prompts below would die on the redirect instead of falling back.
tty_available() {
  { : </dev/tty; } 2>/dev/null
}

# 0 if op is installed and has a live session for $AGE_ACCOUNT. This is the
# single readiness gate: it fast-fails with "account is not signed in" when the
# desktop app is locked, signed out, or CLI integration is off.
op_ready() {
  command -v op >/dev/null 2>&1 || return 1
  op whoami --account "$AGE_ACCOUNT" >/dev/null 2>&1
}

# 0 if op knows about $AGE_ACCOUNT at all. Distinguishes "the app is not signed
# in yet" (no account) from "CLI integration is off" (account, but no session).
op_has_account() {
  command -v op >/dev/null 2>&1 || return 1
  op account list 2>/dev/null | grep -q "$AGE_ACCOUNT"
}

# Establish a session for $AGE_ACCOUNT if there isn't one. 0 when op is usable
# afterwards. op's own stderr is kept visible: it explains the desktop-app case.
op_signin() {
  signin_out=""

  op_ready && return 0
  command -v op >/dev/null 2>&1 || return 1

  # `op signin` writes the session exports to stdout and nothing on failure, so
  # the exit status has to be tested before eval - `eval ""` always succeeds.
  # Read from /dev/tty when available so the prompt works under `curl | sh`.
  if tty_available; then
    signin_out="$(op signin --account "$AGE_ACCOUNT" </dev/tty)" || signin_out=""
  else
    signin_out="$(op signin --account "$AGE_ACCOUNT")" || signin_out=""
  fi
  if [ -n "$signin_out" ]; then
    eval "$signin_out"
  fi

  op_ready
}

# Why op cannot be used, and how to fix it.
print_1password_auth_help() {
  echo "Could not authenticate to 1Password ($AGE_ACCOUNT)." >&2
  echo "The desktop app must be signed in and unlocked, and CLI integration" >&2
  echo "must be enabled (Settings > Developer > Integrate with 1Password CLI)." >&2
  echo "If you use the CLI standalone instead, add the account first:" >&2
  echo "  op account add --address $AGE_ACCOUNT --email p@bargen.co" >&2
}

# Make Homebrew available on macOS: find an existing install that just isn't
# on PATH yet, or run the official installer. Puts brew on PATH for the rest
# of this script. Best-effort: returns non-zero if brew cannot be made
# available.
ensure_homebrew() {
  brew_bin=""

  [ "$(uname -s)" = "Darwin" ] || return 0
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  # Installed (possibly by another account) but not on this shell's PATH.
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      brew_bin="$candidate"
      break
    fi
  done

  if [ -z "$brew_bin" ]; then
    if ! tty_available; then
      echo "Homebrew is not installed and no terminal is available to install it." >&2
      return 1
    fi
    echo "Installing Homebrew (this also installs the Xcode Command Line Tools)..." >&2
    # Attach the tty so the installer's sudo/confirmation prompts work even
    # though this script is usually piped via stdin (curl | sh).
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/tty; then
      echo "Homebrew installation failed." >&2
      return 1
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$candidate" ]; then
        brew_bin="$candidate"
        break
      fi
    done
    if [ -z "$brew_bin" ]; then
      echo "Homebrew installer finished but brew was not found." >&2
      return 1
    fi
  fi

  eval "$("$brew_bin" shellenv)"
}

# Install the 1Password app + CLI via Homebrew and walk through app-based CLI
# integration so the age key can be fetched automatically (macOS only).
# Best-effort: any failure just means provision_age_key falls back to a
# manual paste.
ensure_1password() {
  casks=""
  fruitless=0
  reply=""
  round=1

  [ "$(uname -s)" = "Darwin" ] || return 0

  if ! command -v op >/dev/null 2>&1; then
    casks="1password-cli"
  fi
  if [ ! -d "/Applications/1Password.app" ] && [ ! -d "$HOME/Applications/1Password.app" ]; then
    casks="1password $casks"
  fi

  if [ -n "$casks" ]; then
    if ! command -v brew >/dev/null 2>&1; then
      echo "Homebrew is not available; skipping 1Password installation." >&2
      return 1
    fi
    echo "Installing 1Password ($casks)..." >&2
    # shellcheck disable=SC2086 # word-splitting the cask list is intended
    if ! HOMEBREW_CASK_OPTS="--appdir=/Applications" brew install --cask $casks; then
      echo "Could not install 1Password via Homebrew." >&2
      return 1
    fi
  fi

  if ! command -v op >/dev/null 2>&1; then
    echo "1Password CLI (op) is still not available after installation." >&2
    return 1
  fi

  # Already signed in with CLI integration? Nothing left to set up.
  if op_ready; then
    return 0
  fi

  if ! tty_available; then
    return 1
  fi

  # Guide, then verify. Up to three rounds, because getting this right on a
  # fresh machine is two separate steps in the app and it is easy to do one.
  while [ "$round" -le 3 ]; do
    open -a 1Password >/dev/null 2>&1 || true
    echo "" >&2
    if op_has_account; then
      # op knows the account, so the app is signed in: the integration toggle
      # is what's missing (or the app is locked).
      echo "1Password is open but the CLI cannot talk to it yet." >&2
      echo "  1. Enable Settings > Developer > Integrate with 1Password CLI." >&2
      echo "  2. Make sure the app is unlocked and signed in to $AGE_ACCOUNT." >&2
    else
      echo "1Password is open but no account is set up on this machine yet." >&2
      echo "  1. Sign in to the app (scanning the QR code from another device works)." >&2
      echo "  2. Enable Settings > Developer > Integrate with 1Password CLI." >&2
    fi
    printf 'Press Enter when done (or again to skip and paste the key manually): ' >/dev/tty
    IFS= read -r reply </dev/tty || reply=""

    if op_signin; then
      echo "1Password CLI integration is working." >&2
      return 0
    fi

    if [ -z "$reply" ]; then
      fruitless=$((fruitless + 1))
      if [ "$fruitless" -ge 2 ]; then
        break
      fi
    fi
    round=$((round + 1))
  done

  print_1password_auth_help
  return 1
}

# Print the age key to stdout, fetched from 1Password. Fails if not signed in
# or the item cannot be read.
fetch_age_key_from_1password() {
  file_ref=""
  item_json=""
  key=""
  raw=""
  vault_block=""
  vault_uuid=""

  if ! op_ready; then
    echo "Signing in to 1Password ($AGE_ACCOUNT)..." >&2
    if ! op_signin; then
      print_1password_auth_help
      return 1
    fi
  fi

  # The item has changed shape a couple of times: support a concealed field, a
  # secure note, a file attachment, or the old standalone document form.
  if raw="$(op item get "$AGE_ITEM_UUID" --account "$AGE_ACCOUNT" --fields label=credential --reveal 2>/dev/null)" &&
    key="$(printf '%s\n' "$raw" | extract_age_key)"; then
    printf '%s\n' "$key"
    return 0
  fi

  if raw="$(op item get "$AGE_ITEM_UUID" --account "$AGE_ACCOUNT" --fields notesPlain --reveal 2>/dev/null)" &&
    key="$(printf '%s\n' "$raw" | extract_age_key)"; then
    printf '%s\n' "$key"
    return 0
  fi

  if item_json="$(op item get "$AGE_ITEM_UUID" --account "$AGE_ACCOUNT" --format json 2>/dev/null)"; then
    file_ref="$(printf '%s\n' "$item_json" |
      sed -n 's/.*"reference"[[:space:]]*:[[:space:]]*"\([^"]*\/key[.]txt\)".*/\1/p' |
      head -n 1)"
    if [ -n "$file_ref" ] &&
      raw="$(op read "$file_ref" --account "$AGE_ACCOUNT" 2>/dev/null)" &&
      key="$(printf '%s\n' "$raw" | extract_age_key)"; then
      printf '%s\n' "$key"
      return 0
    fi

    vault_block="${item_json#*\"vault\"}"
    vault_block="${vault_block%%\}*}"
    vault_uuid="$(printf '%s\n' "$vault_block" |
      sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
      head -n 1)"
    if [ -n "$vault_uuid" ] &&
      raw="$(op read "op://$vault_uuid/$AGE_ITEM_UUID/$AGE_KEY_ATTACHMENT_NAME" --account "$AGE_ACCOUNT" 2>/dev/null)" &&
      key="$(printf '%s\n' "$raw" | extract_age_key)"; then
      printf '%s\n' "$key"
      return 0
    fi
  fi

  if raw="$(op document get "$AGE_ITEM_UUID" --account "$AGE_ACCOUNT" 2>/dev/null)" &&
    key="$(printf '%s\n' "$raw" | extract_age_key)"; then
    printf '%s\n' "$key"
    return 0
  fi

  # Only blame the item's shape if we actually got through the door; losing the
  # session mid-read is an auth problem, not a missing attachment.
  if op_ready; then
    echo "Could not read $AGE_KEY_ATTACHMENT_NAME from 1Password item $AGE_ITEM_UUID." >&2
    echo "Check that the item is available in the $AGE_ACCOUNT account and that" >&2
    echo "its credential, notes, document, or $AGE_KEY_ATTACHMENT_NAME attachment contains the age key." >&2
  else
    print_1password_auth_help
  fi
  return 1
}

# Write a key to $AGE_KEY_FILE from 1Password or a manual paste.
# Returns 0 on success, 1 for a retryable failure, 2 to abort.
provision_age_key() {
  raw=""
  key=""

  if command -v op >/dev/null 2>&1; then
    if raw="$(fetch_age_key_from_1password)" && key="$(printf '%s\n' "$raw" | extract_age_key)"; then
      echo "Fetched age key from 1Password."
    else
      echo "Could not fetch the age key from 1Password; falling back to manual entry." >&2
      raw=""
    fi
  else
    echo "1Password CLI (op) is not installed; falling back to manual entry." >&2
    echo "To install it, see https://developer.1password.com/docs/cli/get-started" >&2
  fi

  if [ -z "$raw" ]; then
    if ! tty_available; then
      echo "No terminal available to paste the key." >&2
      echo "Restore $AGE_KEY_FILE manually, then re-run this script." >&2
      return 2
    fi
    echo "" >&2
    echo "Paste the age secret key from 1Password (input is hidden)." >&2
    echo "In the 1Password app, open the chezmoi age key item, reveal and copy" >&2
    echo "the AGE-SECRET-KEY-1... value. Submit an empty line to abort." >&2
    printf 'Age key: ' >/dev/tty
    # Read from /dev/tty so this works even when the script itself is piped via
    # stdin (e.g. curl | sh). stty instead of `read -s` for POSIX shells.
    stty -echo </dev/tty
    IFS= read -r raw </dev/tty || raw=""
    stty echo </dev/tty
    echo "" >/dev/tty
    if [ -z "$raw" ]; then
      echo "Aborted: no key provided." >&2
      return 2
    fi
    if ! key="$(printf '%s\n' "$raw" | extract_age_key)"; then
      echo "That does not look like an age secret key (AGE-SECRET-KEY-1...)." >&2
      return 1
    fi
  fi

  printf '%s\n' "$key" >"$AGE_KEY_FILE"
  chmod 600 "$AGE_KEY_FILE"
}

main() {
  if ! ensure_homebrew; then
    echo "Continuing without Homebrew; chezmoi apply may fail until it is installed." >&2
  fi

  # Only bother with 1Password if the age key still needs fetching and op can't
  # already talk to it. Installed-but-unusable is the common fresh-machine case,
  # so gate on usability, not on presence. Failures fall through to the
  # manual-paste prompt.
  if [ ! -f "$AGE_KEY_FILE" ] && ! op_ready; then
    ensure_1password || true
  fi

  if [ ! "$(command -v chezmoi)" ]; then
    if command -v brew >/dev/null 2>&1 && brew install chezmoi; then
      chezmoi=chezmoi
    else
      bin_dir="$HOME/.local/bin"
      chezmoi="$bin_dir/chezmoi"
      if [ "$(command -v curl)" ]; then
        sh -c "$(curl -fsSL https://get.chezmoi.io)" -- -b "$bin_dir"
      elif [ "$(command -v wget)" ]; then
        sh -c "$(wget -qO- https://get.chezmoi.io)" -- -b "$bin_dir"
      else
        echo "To install chezmoi, you must have curl or wget installed." >&2
        exit 1
      fi
    fi
  else
    chezmoi=chezmoi
  fi

  # POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
  script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

  key_existed=0
  if [ -f "$AGE_KEY_FILE" ]; then
    key_existed=1
    echo "Age key already present at $AGE_KEY_FILE, skipping provisioning."
  else
    mkdir -p "$(dirname "$AGE_KEY_FILE")"
    umask 077
  fi

  # Provision the key (if needed), then prove it can decrypt this repo's
  # secrets before applying anything. Retry on failure.
  attempt=1
  while [ "$attempt" -le "$MAX_KEY_ATTEMPTS" ]; do
    if [ "$key_existed" = 0 ]; then
      status=0
      provision_age_key || status=$?
      if [ "$status" = 2 ]; then
        exit 1
      elif [ "$status" != 0 ]; then
        attempt=$((attempt + 1))
        continue
      fi
    fi

    # Local clone: use it as the source directly. curl-piped: clone from GitHub.
    if [ -d "$script_dir/.git" ]; then
      "$chezmoi" init "--source=$script_dir"
    else
      "$chezmoi" init thisispvb
    fi

    # Exercise decryption + templating through the just-written config.
    if "$chezmoi" cat "$HOME/.ssh/id_ed25519" >/dev/null; then
      break
    fi

    echo "The age key could not decrypt this repo's secrets (attempt $attempt of $MAX_KEY_ATTEMPTS)." >&2
    if [ "$key_existed" = 1 ]; then
      echo "The pre-existing key at $AGE_KEY_FILE is not valid for this repo." >&2
      echo "Restore the correct key from 1Password and re-run this script." >&2
      exit 1
    fi
    rm -f "$AGE_KEY_FILE"
    attempt=$((attempt + 1))
  done

  if [ "$attempt" -gt "$MAX_KEY_ATTEMPTS" ]; then
    echo "Could not provision a valid age key after $MAX_KEY_ATTEMPTS attempts." >&2
    exit 1
  fi

  # exec: replace current process with chezmoi apply
  exec "$chezmoi" apply
}

main "$@"
