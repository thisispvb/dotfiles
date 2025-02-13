#!/usr/bin/env bash

set -eufo pipefail

encryption_key=$(op read "op://Private/macOS Sensitive Vault Image Encryption Key/password")
image_path="$HOME/vaults/Obsidian Vaults.dmg"

# Mount the encrypted disk image
printf '%s\0' "$encryption_key" | hdiutil mount "$image_path" -stdinpass

# Launch Obsidian
open /Applications/Obsidian.app
