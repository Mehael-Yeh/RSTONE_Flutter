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


def build_tools_directory(value=None):
    if value:
        return Path(value)
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if not sdk:
        raise ValueError('Android SDK location is required')
    candidates = list((Path(sdk) / 'build-tools').glob('*'))
    candidates = [path for path in candidates if (path / ('aapt.exe' if os.name == 'nt' else 'aapt')).exists()]
    if not candidates:
        raise ValueError('Android build-tools are required')
    return max(candidates, key=lambda path: tuple(map(int, re.findall(r'\d+', path.name))))


def apk_identity(apk, build_tools):
    tools = build_tools_directory(build_tools)
    aapt = tools / ('aapt.exe' if os.name == 'nt' else 'aapt')
    signer = tools / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
    metadata = subprocess.run([str(aapt), 'dump', 'badging', str(apk)],
                              check=True, capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
    package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata, re.M)
    native = re.search(r'^native-code: (.+)$', metadata, re.M)
    activity = re.search(r"^launchable-activity: name='([^']+)'", metadata, re.M)
    minimum = re.search(r"^sdkVersion:'([0-9]+)'", metadata, re.M)
    verified = subprocess.run([str(signer), 'verify', '--print-certs', str(apk)],
                              check=True, capture_output=True, text=True, encoding='utf-8', errors='replace').stdout
    certs = re.findall(r'^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-f]+)$', verified, re.M)
    if package is None or native is None or activity is None or minimum is None or len(certs) != 1:
        raise ValueError(f'Expected one verified APK signer and a launchable app: {apk}')
    return {'package': package.group(1), 'versionCode': int(package.group(2)),
            'versionName': package.group(3), 'abis': re.findall(r"'([^']+)'", native.group(1)),
            'activity': activity.group(1), 'certificateSha256': certs[0], 'minSdk': int(minimum.group(1))}


def assert_upgrade_compatible(new, old):
    if new['package'] != old['package'] or new['certificateSha256'] != old['certificateSha256']:
        raise ValueError('Direct upgrade requires the same application ID and signing certificate')
    if new['versionCode'] <= old['versionCode']:
        raise ValueError('Direct upgrade requires a strictly higher versionCode')
    if new['minSdk'] > old['minSdk']:
        raise ValueError('Direct upgrade must retain the historical Android system minimum')
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
