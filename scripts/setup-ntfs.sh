#!/bin/bash
# Run deliberately in Terminal. Harbor never executes this automatically.
set -euo pipefail
printf '%s\n' 'This installs macFUSE and the third-party Homebrew NTFS-3G formula.'
printf '%s\n' 'macOS may request administrator authorization for macFUSE installation.'
printf '%s\n' 'Use only the FSKit backend. Do not enable the kernel extension or change Startup Security.'
read -r -p 'Install these dependencies? Type INSTALL: ' answer
test "$answer" = INSTALL || exit 0
if test -x /opt/homebrew/bin/brew; then
    brew_bin=/opt/homebrew/bin/brew
elif test -x /usr/local/bin/brew; then
    brew_bin=/usr/local/bin/brew
else
    printf '%s\n' 'Homebrew is required. See https://brew.sh for installation.' >&2
    exit 1
fi
export HOMEBREW_NO_AUTO_UPDATE=1
if ! test -d /Library/Filesystems/macfuse.fs; then
    "$brew_bin" install --cask macfuse
fi
tap_dir="$("$brew_bin" --repository)/Library/Taps/gromgit/homebrew-fuse"
if ! test -d "$tap_dir"; then
    # Use gh rather than invoking git directly.
    gh repo clone gromgit/homebrew-fuse "$tap_dir" -- --depth 1
fi
"$brew_bin" trust --formula gromgit/fuse/ntfs-3g-mac
"$brew_bin" install gromgit/fuse/ntfs-3g-mac
"$brew_bin" install autoconf automake libgcrypt libtool pkgconf gettext
"$brew_bin" fetch --build-from-source gromgit/fuse/ntfs-3g-mac
cd "$(dirname "$0")/.."
python3 scripts/build-ntfs-engine.py
bash scripts/build-app.sh
printf '%s\n' 'Enable only the macFUSE FSKit file-system extension in System Settings when prompted.'
printf '%s\n' 'Enable FSKit modules through By Category -> File System Extensions.'
printf '%s\n' 'Run python3 scripts/test-ntfs-image.py before using your main HDD.'
