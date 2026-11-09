#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
# The consumer app links no privileged mount helper or experimental FUSE backend.
swift build -c release --product Harbor --disable-sandbox
bin_path=$(swift build -c release --show-bin-path --disable-sandbox)
app="$PWD/dist/Harbor.app"
python3 - <<'PYBUILD'
from pathlib import Path
import shutil
root=Path.cwd(); dist=root/'dist'; app=dist/'Harbor.app'
if dist.is_symlink() or app.is_symlink():raise SystemExit('Refusing a symlink build output.')
if app.exists():shutil.rmtree(app)
(app/'Contents/MacOS').mkdir(parents=True)
(app/'Contents/Resources').mkdir()
PYBUILD
cp "$bin_path/Harbor" "$app/Contents/MacOS/Harbor"
/usr/bin/strip -S -x "$app/Contents/MacOS/Harbor"
python3 scripts/include-ntfs-provider.py
cp LICENSE NOTICE.md docs/USER-GUIDE.md "$app/Contents/Resources/"
cp LICENSES/GPL-2.0.txt "$app/Contents/Resources/NTFS-LICENSE.txt"
swift scripts/make-icon.swift "$PWD/.build/Harbor.iconset"
/usr/bin/iconutil -c icns "$PWD/.build/Harbor.iconset" -o "$app/Contents/Resources/Harbor.icns"
python3 - <<'PYBUILD'
from pathlib import Path
import plistlib
info={
 'CFBundleExecutable':'Harbor','CFBundleIdentifier':'local.harbor.desktop',
 'CFBundleName':'Harbor','CFBundlePackageType':'APPL',
 'CFBundleShortVersionString':'0.3.0','CFBundleVersion':'4',
 'CFBundleIconFile':'Harbor',
 'LSMinimumSystemVersion':'26.0','NSHighResolutionCapable':True,
 'LSApplicationCategoryType':'public.app-category.utilities',
 'NSRemovableVolumesUsageDescription':'Harbor copies and verifies files in the destination folder you choose.'
}
Path('dist/Harbor.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PYBUILD
codesign --force --options runtime --entitlements config/Harbor.entitlements --sign "${HARBOR_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
printf 'Built %s\n' "$app"
