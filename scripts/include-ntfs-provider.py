#!/usr/bin/env python3
"""Include an untouched official provider for the private acceptance candidate.

No public binary redistribution until corresponding-source verification is resolved.
Fetching happens at BUILD time; the end-user app works offline and has no downloader.
"""
from pathlib import Path
import hashlib, json, os, plistlib, subprocess, tempfile

if os.environ.get('HARBOR_PUBLIC_RELEASE') == '1':
    raise SystemExit('Public binary release blocked: provider corresponding-source identity is unresolved.')

ROOT = Path(__file__).resolve().parent.parent
URL = 'https://github.com/dr-kbadawi/ttntfs/releases/download/v0.4.1/TT-NTFS-Native-0.4.1.dmg'
DIGEST = '1a4d90309bab95772ea5efefdf069da0f53de5c481b4e3a061b4fc9bd4fad5c4'
TEAM = 'HU5S996C2K'
cache = ROOT / '.vendor' / 'ttntfs-release'
cache.mkdir(parents=True, exist_ok=True)
image = cache / 'TT-NTFS-Native-0.4.1.dmg'
if image.is_symlink() or cache.is_symlink():
    raise SystemExit('Refusing symlink provider cache.')
if not image.exists():
    with tempfile.NamedTemporaryFile(dir=cache, suffix='.download') as temporary:
        subprocess.run(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--tlsv1.2',
                        '--max-filesize', '10000000', '--output', temporary.name, URL], check=True)
        if hashlib.sha256(Path(temporary.name).read_bytes()).hexdigest() != DIGEST:
            raise SystemExit('Official provider download checksum did not match.')
        image.write_bytes(Path(temporary.name).read_bytes())
if hashlib.sha256(image.read_bytes()).hexdigest() != DIGEST:
    raise SystemExit('Cached provider checksum did not match the pinned official release.')
app = ROOT / 'dist/Harbor.app'
helpers = app / 'Contents/Helpers'
helpers.mkdir()
data = subprocess.check_output(['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-plist', str(image)])
entities = plistlib.loads(data)['system-entities']
mounted = next(x for x in entities if 'mount-point' in x)
# Detach only the device returned by this particular attach; never force.
try:
    source = Path(mounted['mount-point']) / 'TT NTFS Native.app'
    for item, identifier in [(source, 'ch.techtag.ntfs'), (source / 'Contents/Extensions/NTFSExtension.appex', 'ch.techtag.ntfs.extension')]:
        requirement = f'anchor apple generic and identifier "{identifier}" and certificate leaf[subject.OU] = "{TEAM}"'
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', '-R', '=' + requirement, str(item)], check=True)
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != '0.4.1':
        raise SystemExit('Wrong provider version.')
    subprocess.run(['/usr/sbin/spctl', '--assess', '--type', 'execute', str(source)], check=True)
    subprocess.run(['/usr/bin/ditto', str(source), str(helpers / source.name)], check=True)
    provenance = {'provider': 'TT NTFS Native', 'version': '0.4.1', 'license': 'GPL-2.0', 'downloadURL': URL, 'downloadSHA256': DIGEST, 'vendorTeam': TEAM, 'embeddedTTGitCommit': info.get('TTGitCommit'), 'publicSourceTag': 'v0.4.1', 'correspondingSourceIdentityVerified': False, 'distribution': 'private acceptance candidate only'}
    (app / 'Contents/Resources/NTFS-PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
finally:
    subprocess.run(['/usr/bin/hdiutil', 'detach', mounted['dev-entry']], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(helpers / 'TT NTFS Native.app')], check=True)
print('Included official NTFS provider unchanged; checksum and vendor signatures verified.')
