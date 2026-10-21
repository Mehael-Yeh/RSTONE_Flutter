"""Audit the six real release APKs before they become publicly downloadable."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

ASSET_ROOT = 'assets/flutter_assets/'
FONTS = {'MicrosoftYaHei.ttf', 'MicrosoftYaHeiBold.ttf', 'SimHei.ttf'}
ABIS = ['arm64-v8a', 'armeabi-v7a', 'x86_64']
MIN_ANDROID_API = 29


def build_tools_directory(value=None):
    if value:
        return Path(value)
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise ValueError('Android SDK location is required')
    tools = Path(sdk) / 'build-tools' / '35.0.0'
    if not (tools / ('aapt.exe' if os.name == 'nt' else 'aapt')).exists():
        raise ValueError('Install the pinned Android build-tools 35.0.0')
    return tools


def parse_identity(metadata, signed_output, abis):
    # Android tooling can add/reorder package attributes and signer qualifiers.
    lines = [line.strip() for line in metadata.splitlines()]
    package_line = next((line for line in lines if line.startswith('package:')), '')
    fields = dict(re.findall(r"([A-Za-z0-9_]+)='([^']*)'", package_line))
    activity = re.search(r"^launchable-activity:.*?\bname='([^']+)'", metadata, re.M)
    minimum = re.search(r"^(?:sdkVersion|minSdkVersion):\s*'([0-9]+)'", metadata, re.M)
    certs = {value.lower() for value in re.findall(
        r'^Signer[^\n]*? certificate SHA-256 digest:\s*([0-9a-fA-F]{64})\s*$', signed_output, re.M)}
    if (not all(key in fields for key in ['name', 'versionCode', 'versionName'])
            or not abis or minimum is None or len(certs) != 1):
        raise ValueError('Cannot verify APK identity: ' + repr({'packageFields': fields, 'abis': abis,
                         'minSdkFound': minimum is not None, 'certificates': sorted(certs),
                         'signerOutput': signed_output[:1800]}))
    return {'package': fields['name'], 'versionCode': int(fields['versionCode']) + (int(fields.get('versionCodeMajor', '0')) << 32),
            'versionName': fields['versionName'], 'abis': sorted(abis),
            'activity': activity.group(1) if activity else None,
            'certificateSha256': next(iter(certs)), 'minSdk': int(minimum.group(1))}


def apk_identity(apk, build_tools):
    tools = build_tools_directory(build_tools)
    aapt = tools / ('aapt.exe' if os.name == 'nt' else 'aapt')
    signer = tools / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
    metadata = subprocess.run([str(aapt), 'dump', 'badging', str(apk)],
                              check=True, capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
    verified = subprocess.run([str(signer), 'verify', '--print-certs', str(apk)],
                              check=True, capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
    with zipfile.ZipFile(apk) as archive:
        abis = {match.group(1) for name in archive.namelist()
                for match in [re.fullmatch(r'lib/([^/]+)/[^/]+\.so', name)] if match}
    return parse_identity(metadata, verified, abis)


def assert_upgrade_compatible(new, old, *, android_api=MIN_ANDROID_API):
    if new['package'] != old['package'] or new['certificateSha256'] != old['certificateSha256']:
        raise ValueError('Direct upgrade requires the same application ID and signing certificate')
    if new['versionCode'] <= old['versionCode']:
        raise ValueError('Direct upgrade requires a strictly higher versionCode')
    if max(new['minSdk'], old['minSdk']) > android_api:
        raise ValueError(f'Both APKs must support the upgrade test system: Android API {android_api}')
    if tuple(map(int, new['versionName'].split('.'))) < tuple(map(int, old['versionName'].split('.'))):
        raise ValueError('The new displayed version cannot be lower than the installed version')


def audit_assets(archive, config, lite):
    names = archive.namelist()
    if any(name.startswith(ASSET_ROOT) and name.endswith('.md') for name in names):
        raise ValueError('Official Markdown must not be bundled in an APK')
    installed = json.loads(archive.read(ASSET_ROOT + 'assets/data_sync_config.json'))
    if installed != config:
        raise ValueError('The APK must contain the reviewed production trust configuration')
    fonts = {name.rsplit('/', 1)[-1] for name in names
             if name.startswith(ASSET_ROOT + 'assets/fonts/') and name.endswith('.ttf')}
    if fonts != (set() if lite else FONTS):
        raise ValueError('Full/Lite font boundary differs from the expected edition')


def run(args):
    output = Path(args.directory)
    config = json.loads(Path('assets/data_sync_config.json').read_text(encoding='utf-8'))
    version, code = args.version.split('+')
    tools = build_tools_directory(args.build_tools)
    baseline = json.loads(Path(args.baselines).read_text(encoding='utf-8')) if args.baselines else []
    expected = {f'RSTONE-{args.tag}{suffix}-{abi}-release.apk': (suffix != '', abi)
                for suffix in ['', '-Lite'] for abi in ABIS}
    actual = {p.name for p in output.glob('RSTONE-*.apk')}
    if actual != set(expected):
        raise ValueError('Expected exactly six named Full/Lite release APKs')
    digests, certificates = [], set()
    for name, (lite, abi) in sorted(expected.items()):
        apk = output / name
        with zipfile.ZipFile(apk) as archive:
            audit_assets(archive, config, lite)
        identity = apk_identity(apk, tools)
        if identity['minSdk'] != MIN_ANDROID_API:
            raise ValueError('Release APKs must require Android 10 (API 29)')
        if (identity['package'] != 'com.rstone.rstone_flutter' or identity['versionCode'] != int(code)
                or identity['versionName'] != version or set(identity['abis']) != {abi}):
            raise ValueError(f'Incorrect package version or ABI: {name}')
        for old in baseline:
            assert_upgrade_compatible(identity, old)
        certificates.add(identity['certificateSha256'])
        digest = hashlib.sha256()
        with apk.open('rb') as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b''):
                digest.update(chunk)
        digests.append(f'{digest.hexdigest()}  {name}\n')
    if len(certificates) != 1:
        raise ValueError('All editions and ABIs must have the same signing identity')
    (output / 'SHA256SUMS.txt').write_text(''.join(digests), encoding='utf-8')
    print('Six signed APKs verified: versions, ABIs, pinned data configuration, fonts, no bundled Markdown')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', default='build/app/outputs/flutter-apk')
    parser.add_argument('--tag', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build-tools', required=True)
    parser.add_argument('--baselines')
    run(parser.parse_args())
