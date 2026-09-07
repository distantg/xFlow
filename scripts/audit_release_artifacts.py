#!/usr/bin/env python3
"""Audit exact staged ZIPs and mounted DMGs. Prints findings without secret values."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import pwd
import re
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--version', required=True)
parser.add_argument('--build', required=True)
parser.add_argument('--scanner', required=True, type=Path)
parser.add_argument('--mount-root', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
reports = root / 'dist/release-audit'
reports.mkdir(parents=True, exist_ok=True)
patterns = {
    'private key': rb'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----',
    'provider token': rb'(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{15,}|sk-(?:proj-)?[A-Za-z0-9_-]{30,}|AKIA[A-Z0-9]{16})',
    'personal home path': rb'/Users/[^/\x00\s]{1,80}/',
}
identity = pwd.getpwuid(os.getuid())
private_terms = {identity.pw_name, *identity.pw_gecos.split(',')[0].split()}
private_terms = {t for t in private_terms if len(t) >= 4}
issues = []

def inspect(name, data):
    for label, pattern in patterns.items():
        if re.search(pattern, data):
            issues.append((name, label))
    for term in private_terms:
        if any(term.lower().encode(enc) in data.lower() for enc in ['utf-8', 'utf-16-le', 'utf-16-be']):
            issues.append((name, 'local identity'))
    if data.startswith(b'\x1f\x8b'):
        try:
            inspect(name + ' [gzip]', gzip.decompress(data))
        except (OSError, EOFError):
            issues.append((name, 'unreadable gzip metadata'))

resources = {'AppIcon.icns', 'AppIcon.png', 'SplashBackground.png', 'Sparkle-LICENSE.txt', 'container-migration.plist'}
manifest = {}
for arch, label in [('arm64', 'AppleSilicon'), ('x86_64', 'Intel')]:
    archive = root / f'dist/updates/{arch}/Mosaic-{args.version}-{args.build}-{arch}.zip'
    dmg = root / f'dist/Mosaic-{label}.dmg'
    mount = args.mount_root / arch
    assert mount.is_mount(), f'DMG must be mounted at {mount}'
    mounted_app = mount / 'Mosaic.app'
    with zipfile.ZipFile(archive) as z:
        info = plistlib.loads(z.read('Mosaic.app/Contents/Info.plist'))
        assert info['CFBundleIdentifier'] == 'com.distantg.xflow'
        assert info['CFBundleVersion'] == args.build
        assert info['CFBundleShortVersionString'] == args.version
        assert info['SUFeedURL'] == f'https://raw.githubusercontent.com/distantg/xFlow/main/updates/{arch}/appcast.xml'
        assert info['SUPublicEDKey'] == (root / 'Config/SparklePublicKey.txt').read_text().strip()
        for item in z.infolist():
            path = PurePosixPath(item.filename)
            assert not path.is_absolute() and '..' not in path.parts
            assert path.parts[0] in {'Mosaic.app', '__MACOSX'}
            if item.is_dir():
                continue
            inspect(archive.name + ':' + item.filename, z.read(item))
            if item.filename.startswith('Mosaic.app/Contents/Resources/'):
                assert path.name in resources, f'Unexpected resource: {path.name}'
            if item.filename.startswith('Mosaic.app/'):
                local = mount / item.filename
                assert local.exists(), f'DMG missing {item.filename}'
                mode = item.external_attr >> 16
                if (mode & 0o170000) == 0o120000:
                    assert local.is_symlink() and os.readlink(local).encode() == z.read(item)
                    assert local.resolve().is_relative_to(mounted_app.resolve())
                else:
                    assert local.read_bytes() == z.read(item), f'ZIP/DMG mismatch: {item.filename}'
    assert set(p.name for p in mount.iterdir()) <= {'Mosaic.app', 'Applications', 'Click here for installation instructions.txt', '.background', '.fseventsd', '.Trashes'}
    assert (mount / 'Applications').is_symlink() and os.readlink(mount / 'Applications') == '/Applications'
    for p in mount.rglob('*'):
        if p.is_file() and not p.is_symlink():
            inspect(dmg.name + ':' + str(p.relative_to(mount)), p.read_bytes())
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(mounted_app)], check=True)
    assert subprocess.check_output(['lipo', '-archs', str(mounted_app / 'Contents/MacOS/Mosaic')], text=True).strip() == arch
    report = reports / f'{arch}-dmg-gitleaks.json'
    scan = subprocess.run([str(args.scanner), 'dir', str(mount), '--redact=100', '--no-banner', '--no-color', '--ignore-gitleaks-allow', '--report-format', 'json', '--report-path', str(report)], capture_output=True)
    assert scan.returncode in (0, 1), f'Scanner failed: {scan.returncode}'
    findings = json.loads(report.read_text())
    for f in findings:
        issues.append((Path(f['File']).name, 'Gitleaks: ' + f['RuleID']))
    for file in [archive, dmg]:
        manifest[file.name] = hashlib.sha256(file.read_bytes()).hexdigest()
    print(f'{arch}: ZIP/DMG contents match; build {args.build}; signatures and architecture verified.')
if issues:
    print(json.dumps({'findings': issues}, indent=2))
    raise SystemExit(1)
(reports / 'approved-sha256.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('No detected personal identifiers or secrets in release contents. Exact artifact hashes recorded.')
