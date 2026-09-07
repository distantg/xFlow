#!/usr/bin/env python3
"""Verify packaged release structure and signed update metadata without publishing."""
import base64
import argparse
import plistlib
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--require-updates', action='store_true')
args = parser.parse_args()
ROOT = Path(__file__).resolve().parent.parent
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
public_key = (ROOT / 'Config/SparklePublicKey.txt').read_text().strip()
assert len(base64.b64decode(public_key, validate=True)) == 32
versions = set()
for arch, folder in [('arm64', 'Apple Silicon'), ('x86_64', 'Intel')]:
    app = ROOT / 'dist' / folder / 'Mosaic.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.distantg.xflow'
    assert info['SUPublicEDKey'] == public_key
    assert info['SUFeedURL'] == f'https://raw.githubusercontent.com/distantg/xFlow/main/updates/{arch}/appcast.xml'
    assert info['SUScheduledCheckInterval'] == 43200
    assert info['SUAutomaticallyUpdate'] is False
    assert 'SUEnableAutomaticChecks' not in info  # Preserve Sparkle's opt-in prompt.
    assert info['SUVerifyUpdateBeforeExtraction'] is True
    assert info['SUEnableInstallerLauncherService'] is True
    assert 'NSAppTransportSecurity' not in info
    versions.add((info['CFBundleShortVersionString'], info['CFBundleVersion']))
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    ent = plistlib.loads(subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(app)], stderr=subprocess.DEVNULL))
    assert ent['com.apple.security.app-sandbox'] is True
    assert set(ent['com.apple.security.temporary-exception.mach-lookup.global-name']) == {'com.distantg.xflow-spki', 'com.distantg.xflow-spks'}
    binary = app / 'Contents/MacOS/Mosaic'
    assert subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip() == arch
    paths = subprocess.check_output(['otool', '-l', str(binary)], text=True)
    assert '@executable_path/../Frameworks' in paths
    framework = app / 'Contents/Frameworks/Sparkle.framework/Versions/B'
    for helper in ['Autoupdate', 'Updater.app', 'XPCServices/Installer.xpc', 'XPCServices/Downloader.xpc']:
        assert (framework / helper).exists()
    assert (app / 'Contents/Resources/Sparkle-LICENSE.txt').exists()
    feed_path = ROOT / 'dist/updates' / arch / 'appcast.xml'
    if args.require_updates and not feed_path.exists():
        raise SystemExit(f'Missing update feed: {feed_path}')
    if feed_path.exists():
        items = ET.parse(feed_path).findall('./channel/item')
        item = next(i for i in items if i.findtext(SPARKLE + 'version') == info['CFBundleVersion'])
        assert item.findtext(SPARKLE + 'shortVersionString') == info['CFBundleShortVersionString']
        assert item.find(SPARKLE + 'phasedRolloutInterval') is None
        enclosure = item.find('enclosure')
        assert enclosure is not None
        url = enclosure.attrib['url']
        assert url.startswith(f'https://github.com/distantg/xFlow/releases/download/v{info["CFBundleShortVersionString"]}/')
        archive = feed_path.parent / url.rsplit('/', 1)[1]
        assert archive.stat().st_size == int(enclosure.attrib['length'])
        assert len(base64.b64decode(enclosure.attrib[SPARKLE + 'edSignature'], validate=True)) == 64
    print(f'{folder}: verified build {info["CFBundleVersion"]}')
assert len(versions) == 1, 'Architecture releases must use the same version and build'
