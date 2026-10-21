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
    tools = Path(args.build_tools)
    aapt = tools / ('aapt.exe' if os.name == 'nt' else 'aapt')
    signer = tools / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
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
        metadata = subprocess.run([str(aapt), 'dump', 'badging', str(apk)],
                                  check=True, capture_output=True, text=True).stdout
        package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", metadata, re.M)
        native = re.search(r'^native-code: (.+)$', metadata, re.M)
        if (package is None or package.groups() != ('com.rstone.rstone_flutter', code, version)
                or native is None or set(re.findall(r"'([^']+)'", native.group(1))) != {abi}):
            raise ValueError(f'Incorrect package version or ABI: {name}')
        verified = subprocess.run([str(signer), 'verify', '--print-certs', str(apk)],
                                  check=True, capture_output=True, text=True).stdout
        certs = re.findall(r'^Signer #[0-9]+ certificate SHA-256 digest: ([0-9a-f]+)$', verified, re.M)
        if len(certs) != 1:
            raise ValueError(f'Expected one verified signer: {name}')
        certificates.update(certs)
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
    run(parser.parse_args())
