#!/usr/bin/env python3
"""Publish-ready Sparkle feed: only advertise the exact notarized GitHub asset.

Run after uploading the release, then review and commit website/appcast.xml.
Private Ed25519 material stays in the login Keychain.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'iamrainhard/sofa'
ACCOUNT = 'com.rain.sofa.sparkle'
TEAM = '3FAL2BXWLS'
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate_app(info, config):
    if info.get('CFBundleIdentifier') != 'com.rain.luma-remote':
        raise ValueError('Not the production Sofa bundle')
    if 'SofaPreviewState' in info:
        raise ValueError('Preview bundles cannot enter the update feed')
    build = str(info.get('CFBundleVersion', ''))
    if not build.isdecimal() or int(build) < 15:
        raise ValueError('Expected an updater-enabled, numeric production build')
    for key in ('SUPublicEDKey', 'SUFeedURL', 'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction'):
        if info.get(key) != config.get(key):
            raise ValueError(f'Update configuration mismatch: {key}')
    return build, info['CFBundleShortVersionString']


def validate_release(release, filename, size, digest, tag):
    if release.get('draft') or release.get('tag_name') != tag:
        raise ValueError('Release must be published with the matching build tag')
    matches = [asset for asset in release.get('assets', []) if asset['name'] == filename]
    if len(matches) != 1:
        raise ValueError('Upload this exact archive to the release before updating the feed')
    asset = matches[0]
    expected = f'https://github.com/{REPOSITORY}/releases/download/{tag}/{filename}'
    if asset.get('browser_download_url') != expected or asset.get('size') != size:
        raise ValueError('Published asset URL or size differs from the local archive')
    if asset.get('digest') != f'sha256:{digest}':
        raise ValueError('GitHub SHA-256 does not match. Do not advertise an unverified asset.')
    return expected


def run(*args, **kwargs):
    return subprocess.run(args, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, help='Notarized ZIP created by scripts/package.sh')
    parser.add_argument('--notes', required=True, type=Path, help='Release notes in Markdown')
    args = parser.parse_args()
    archive = args.archive.resolve()
    if archive.suffix != '.zip' or not archive.name.endswith('-arm64-notarized.zip'):
        parser.error('Use the notarized Apple silicon ZIP from scripts/package.sh')
    tools = Path(os.environ.get('SPARKLE_TOOLS', ROOT / '.build/artifacts/sparkle/Sparkle/bin'))
    if not (tools / 'generate_appcast').is_file():
        parser.error('Run swift package resolve, or set SPARKLE_TOOLS to the official Sparkle bin folder')
    config = plistlib.loads((ROOT / 'Resources/Updater.plist').read_bytes())
    public_key = run(str(tools / 'generate_keys'), '--account', ACCOUNT, '-p', capture_output=True).stdout.strip()
    if public_key != config['SUPublicEDKey']:
        raise ValueError('Signing key does not match the app public key')
    with tempfile.TemporaryDirectory(prefix='sofa-feed-') as temp:
        workspace = Path(temp)
        extracted = workspace / 'extracted'
        run('ditto', '-x', '-k', str(archive), str(extracted))
        app = extracted / 'Sofa.app'
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        build, version = validate_app(info, config)
        expected_name = f'Sofa-{version}-build{build}-arm64-notarized.zip'
        if archive.name != expected_name:
            raise ValueError('Archive filename and bundled version differ')
        run('codesign', '--verify', '--deep', '--strict', str(app))
        signing = run('codesign', '-d', '--verbose=4', str(app), capture_output=True).stderr
        if f'TeamIdentifier={TEAM}' not in signing:
            raise ValueError('App is not signed by the Sofa release team')
        run('xcrun', 'stapler', 'validate', str(app))
        run('spctl', '--assess', '--type', 'execute', '--verbose=2', str(app))
        tag = f'v{version}-build{build}'
        release = json.loads(run('gh', 'api', f'repos/{REPOSITORY}/releases/tags/{tag}', capture_output=True).stdout)
        with archive.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        url = validate_release(release, archive.name, archive.stat().st_size, digest, tag)
        feed = ROOT / 'website/appcast.xml'
        previous = ET.parse(feed).findall(f'channel/item/{SPARKLE}version')
        if any(int(item.text) >= int(build) for item in previous):
            raise ValueError('Feed already contains this or a newer build; review instead of overwriting it')
        staging = workspace / 'feed'
        staging.mkdir()
        shutil.copy2(archive, staging / archive.name)
        shutil.copy2(feed, staging / 'appcast.xml')
        shutil.copy2(args.notes, staging / f'{archive.stem}.md')
        run(str(tools / 'generate_appcast'), '--account', ACCOUNT, '--versions', build,
            '--maximum-deltas', '0', '--embed-release-notes', '--download-url-prefix', url.rsplit('/', 1)[0] + '/',
            '--link', 'https://iamrainhard.github.io/sofa/', str(staging))
        generated = staging / 'appcast.xml'
        run(str(tools / 'sign_update'), '--account', ACCOUNT, '--verify', str(generated))
        item = next(i for i in ET.parse(generated).findall('channel/item') if i.findtext(f'{SPARKLE}version') == build)
        enclosure = item.find('enclosure')
        if enclosure.get('url') != url or int(enclosure.get('length', 0)) != archive.stat().st_size:
            raise ValueError('Generated enclosure does not match the verified release')
        signature = enclosure.get(f'{SPARKLE}edSignature')
        if not signature:
            raise ValueError('Update archive signature missing')
        run(str(tools / 'sign_update'), '--account', ACCOUNT, '--verify', str(archive), signature)
        pending = feed.with_suffix('.pending')
        shutil.copy2(generated, pending)
        pending.replace(feed)
        print(f'Prepared signed feed for build {build}. Review, commit and deploy website/appcast.xml.')


if __name__ == '__main__':
    main()
