#!/usr/bin/env bash

set -eufo pipefail

encryption_key=$(op read "op://Private/macOS Sensitive Vault Image Encryption Key/password")
vault_name="Obsidian Vaults"
image_path="$HOME/vaults/$vault_name.dmg"

# Create encrypted disk image if it doesn't exist yet
if [[ ! -f "$image_path" ]]; then
  echo "Warning: Disk Image does not exist at \"$image_path\", creating a new one..."
  printf '%s\0' "$encryption_key" | hdiutil create "$image_path" \
    -size 5g \
    -fs APFS \
    -volname "$vault_name" \
    -type UDIF \
    -encryption AES-256 \
    -stdinpass
fi

# Mount the encrypted disk image
printf '%s\0' "$encryption_key" | hdiutil mount "$image_path" -quiet -stdinpass

# Launch Obsidian
echo "Successfully mounted Disk Image from \"$image_path\""
open /Applications/Obsidian.app
