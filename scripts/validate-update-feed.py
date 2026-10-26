#!/usr/bin/env python3
"""Check feed metadata and verify archive/feed signatures with Sparkle's tool."""
import base64
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET


def validate(feed, archive, app, verifier):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version = info['CFBundleShortVersionString']
    architecture = subprocess.check_output(['lipo', '-archs', str(app / 'Contents/MacOS/Tunerfenster')], text=True).strip()
    if architecture not in ('arm64', 'x86_64'):
        raise ValueError('Release app must contain a single CPU architecture')
    if archive.suffix not in ('.dmg', '.zip') or archive.name != f'Tunerfenster-{version}-{architecture}{archive.suffix}':
        raise ValueError('Installer filename does not match the app')
    namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    items = ET.parse(feed).getroot().findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected one update in the architecture-specific feed')
    item = items[0]
    if item.findtext(namespace + 'version') != info['CFBundleVersion']:
        raise ValueError('Update build number does not match the app')
    if item.findtext(namespace + 'shortVersionString') != version:
        raise ValueError('Update version does not match the app')
    enclosure = item.find('enclosure')
    expected = f'https://github.com/NemoN/Tunerfenster/releases/download/v{version}/{archive.name}'
    if enclosure is None or enclosure.get('url') != expected or int(enclosure.get('length', '0')) != archive.stat().st_size:
        raise ValueError('Update URL or size does not match the installer')
    signature = enclosure.get(namespace + 'edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Missing Ed25519 archive signature')
    subprocess.run([str(verifier), '--account', 'Tunerfenster', '--verify', str(archive), signature], check=True)
    subprocess.run([str(verifier), '--account', 'Tunerfenster', '--verify', str(feed)], check=True)
    print(f'Update feed, archive signature and signed XML verified ({architecture}).')


if __name__ == '__main__':
    validate(*(pathlib.Path(value) for value in sys.argv[1:5]))
