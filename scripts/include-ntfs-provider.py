#!/usr/bin/env python3
"""Include the official provider plus upstream-designated release source/notices.

The unresolved embedded-commit difference stays explicit in provenance.
Fetching happens at BUILD time; the end-user app works offline and has no downloader.
"""
from pathlib import Path
import hashlib, json, plistlib, subprocess, tarfile, tempfile

ROOT = Path(__file__).resolve().parent.parent
URL = 'https://github.com/dr-kbadawi/ttntfs/releases/download/v0.4.1/TT-NTFS-Native-0.4.1.dmg'
DIGEST = '1a4d90309bab95772ea5efefdf069da0f53de5c481b4e3a061b4fc9bd4fad5c4'
TEAM = 'HU5S996C2K'
SOURCE_COMMIT = '3891dcbb5eebce1baff5c8fe5aee3c00ff11df9e'
SOURCE_TREE = '864515292bf94ee23f1ee5e9b97c927dde6bdb9a'
SOURCE_DIGEST = '7abc7cc56d4c98881396df9eb303192f17395a5cbf5bd0b79ebf87f10d3af9b4'
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
# Always carry upstream-designated source, including in a copied app bundle.
source_archive = cache / 'TT-NTFS-Native-0.4.1-source.tar.gz'
if source_archive.is_symlink():
    raise SystemExit('Refusing a symlink source archive.')
if not source_archive.exists():
    with tempfile.NamedTemporaryFile(dir=cache, suffix='.source-download') as temporary:
        subprocess.run(['gh', 'api', f'repos/dr-kbadawi/ttntfs/tarball/{SOURCE_COMMIT}'],
                       stdout=temporary, check=True)
        temporary.flush()
        data = Path(temporary.name).read_bytes()
        if hashlib.sha256(data).hexdigest() != SOURCE_DIGEST:
            raise SystemExit('Provider source archive checksum did not match the audited release archive.')
        source_archive.write_bytes(data)
if hashlib.sha256(source_archive.read_bytes()).hexdigest() != SOURCE_DIGEST:
    raise SystemExit('Cached provider source archive checksum did not match.')
with tarfile.open(source_archive, 'r:gz') as archive:
    members = archive.getmembers()
    prefix = members[0].name.split('/')[0]
    if not all((m.isfile() or m.isdir()) and (m.name == prefix or m.name.startswith(prefix + '/')) for m in members):
        raise SystemExit('Unexpected contents in the provider source archive.')
    if sum(m.isfile() for m in members) != 343:
        raise SystemExit('Provider source archive file count did not match.')
    license_data = archive.extractfile(prefix + '/LICENSE').read()
    copyright_data = archive.extractfile(prefix + '/COPYRIGHT').read()
app = ROOT / 'dist/Harbor.app'
third_party = app / 'Contents/Resources/ThirdParty'
third_party.mkdir()
(third_party / source_archive.name).write_bytes(source_archive.read_bytes())
(third_party / 'TT-NTFS-Native-LICENSE.txt').write_bytes(license_data)
(third_party / 'TT-NTFS-Native-COPYRIGHT.md').write_bytes(copyright_data)
(third_party / 'SOURCE-INFO.md').write_text(
    '# Included NTFS component source\n\n'
    'This folder contains the complete source archive designated by upstream for TT NTFS Native 0.4.1, '
    'including its interfaces and build/packaging scripts, plus its license and copyright notices.\n\n'
    f'Public source commit: {SOURCE_COMMIT}\nPublic source tree: {SOURCE_TREE}\n'
    f'Source archive SHA-256: {SOURCE_DIGEST}\n\n'
    'The official release identifies its source as https://github.com/dr-kbadawi/ttntfs. '
    'The binary embeds v0.3-ui-fixes-112-gfc418d028; that hash has not been resolved publicly. '
    'Independent source-to-binary provenance is not confirmed. See '
    'https://github.com/dr-kbadawi/ttntfs/issues/5 and Harbor’s source audit.\n\n'
    'Harbor is an independent wrapper. The provider remains unchanged and independently signed; '
    'its signing keys are not part of the source. Harbor itself is an ad-hoc-signed beta, not notarized.\n'
)

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
    provenance = {'provider': 'TT NTFS Native', 'version': '0.4.1', 'license': 'GPL-2.0', 'downloadURL': URL, 'downloadSHA256': DIGEST, 'vendorTeam': TEAM, 'embeddedTTGitCommit': info.get('TTGitCommit'), 'publicSourceTag': 'v0.4.1', 'publicSourceCommit': SOURCE_COMMIT, 'publicSourceTree': SOURCE_TREE, 'sourceArchiveSHA256': SOURCE_DIGEST, 'sourceArchiveIncluded': True, 'sourceDesignation': 'upstream release-tag source', 'correspondingSourceIdentityVerified': False, 'provenanceQuestion': 'https://github.com/dr-kbadawi/ttntfs/issues/5', 'distribution': 'public beta; independent source-to-binary identity unconfirmed'}
    (app / 'Contents/Resources/NTFS-PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
finally:
    subprocess.run(['/usr/bin/hdiutil', 'detach', mounted['dev-entry']], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(helpers / 'TT NTFS Native.app')], check=True)
print('Included official NTFS provider unchanged; checksum and vendor signatures verified.')
