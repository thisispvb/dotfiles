#!/usr/bin/env bash

set -e # -e: exit on error

AGE_KEY_FILE="$HOME/.config/chezmoi/key.txt"
AGE_ITEM_UUID="jb7rxvjrxlp7kkhiieipzeruvy"
AGE_KEY_ATTACHMENT_NAME="key.txt"
MAX_KEY_ATTEMPTS=3

# Extract the secret key line from any source: an op field value, a full
# key.txt (including comment lines), or a raw paste.
extract_age_key() {
  grep -om1 'AGE-SECRET-KEY-1[A-Z0-9]*'
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

  if ! op whoami >/dev/null 2>&1; then
    echo "Signing in to 1Password..." >&2
    if ! eval "$(op signin)"; then
      echo "Could not sign in to 1Password." >&2
      echo "If no account is configured on this machine yet, run:" >&2
      echo "  op account add --address my.1password.eu --email p@bargen.co" >&2
      echo "or enable CLI integration in the 1Password desktop app" >&2
      echo "(Settings > Developer > Integrate with 1Password CLI)." >&2
      return 1
    fi
  fi

  # The item has changed shape a couple of times: support a concealed field, a
  # secure note, a file attachment, or the old standalone document form.
  if raw="$(op item get "$AGE_ITEM_UUID" --fields label=credential --reveal 2>/dev/null)" &&
    key="$(printf '%s\n' "$raw" | extract_age_key)"; then
    printf '%s\n' "$key"
    return 0
  fi

  if raw="$(op item get "$AGE_ITEM_UUID" --fields notesPlain --reveal 2>/dev/null)" &&
    key="$(printf '%s\n' "$raw" | extract_age_key)"; then
    printf '%s\n' "$key"
    return 0
  fi

  if item_json="$(op item get "$AGE_ITEM_UUID" --format json 2>/dev/null)"; then
    file_ref="$(printf '%s\n' "$item_json" |
      sed -n 's/.*"reference"[[:space:]]*:[[:space:]]*"\([^"]*\/key[.]txt\)".*/\1/p' |
      head -n 1)"
    if [ -n "$file_ref" ] &&
      raw="$(op read "$file_ref" 2>/dev/null)" &&
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
      raw="$(op read "op://$vault_uuid/$AGE_ITEM_UUID/$AGE_KEY_ATTACHMENT_NAME" 2>/dev/null)" &&
      key="$(printf '%s\n' "$raw" | extract_age_key)"; then
      printf '%s\n' "$key"
      return 0
    fi
  fi

  if raw="$(op document get "$AGE_ITEM_UUID" 2>/dev/null)" &&
    key="$(printf '%s\n' "$raw" | extract_age_key)"; then
    printf '%s\n' "$key"
    return 0
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
    if [ ! -r /dev/tty ]; then
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
  if [ ! "$(command -v chezmoi)" ]; then
    bin_dir="$HOME/.local/bin"
    chezmoi="$bin_dir/chezmoi"
    if [ "$(command -v curl)" ]; then
      sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$bin_dir"
    elif [ "$(command -v wget)" ]; then
      sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$bin_dir"
    else
      echo "To install chezmoi, you must have curl or wget installed." >&2
      exit 1
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
