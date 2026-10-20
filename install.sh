#!/bin/sh
# Set up gcloud-auth.
#   sh install.sh          copy gcloud-auth.zsh into ~/.gcloud-accounts
#   sh install.sh --link   symlink to the file in this repo instead (follows updates)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
accounts_dir=${GCLOUD_ACCOUNTS_DIR:-$HOME/.gcloud-accounts}
zshrc=${ZDOTDIR:-$HOME}/.zshrc
mode=copy
[ "${1:-}" = "--link" ] && mode=link

mkdir -p "$accounts_dir"
chmod 700 "$accounts_dir"

# the tool itself
target=$accounts_dir/gcloud-auth.zsh
if [ "$mode" = link ]; then
  ln -sfn "$here/gcloud-auth.zsh" "$target"
  echo "symlinked: $target -> $here/gcloud-auth.zsh"
else
  rm -f "$target"   # may be a symlink left by --link
  cp "$here/gcloud-auth.zsh" "$target"
  echo "copied: $target"
fi

# folder -> account mapping
[ -e "$accounts_dir/dirs" ] || : > "$accounts_dir/dirs"

# .zshrc
line="source \"$accounts_dir/gcloud-auth.zsh\""
if [ -f "$zshrc" ] && grep -qF "gcloud-auth.zsh" "$zshrc"; then
  echo "skipped: $zshrc already sources gcloud-auth.zsh"
else
  printf '\n# gcloud-auth: switch Google Cloud accounts\n%s\n' "$line" >> "$zshrc"
  echo "appended: $zshrc"
fi

echo
echo "Done. Open a new terminal or run:"
echo "  $line"
echo "Then register an account: gcloud-auth add-account <name>"
