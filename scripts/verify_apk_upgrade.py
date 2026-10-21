"""Verify historical APK identity and real in-place upgrades on an isolated emulator."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time
import xml.etree.ElementTree as ET

from verify_release_apks import ABIS, apk_identity, assert_upgrade_compatible, build_tools_directory

PACKAGE = 'com.rstone.rstone_flutter'
PERSONAL_NAME = 'RS999999'
PERSONAL = '---\n标签:\n  - 升级验证\n---\n# RSTONE-UPGRADE-PERSONAL\n'.encode('utf-8')
RULES = 'UPGRADE -> 升级验证\n'.encode('utf-8')
NOTE = 'RSTONE-UPGRADE-NOTE'


def command(args, check=True):
    result = subprocess.run([str(arg) for arg in args], capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stdout.decode('utf-8', 'replace') + result.stderr.decode('utf-8', 'replace'))
    return result


def prepare(args):
    output = Path(args.directory)
    output.mkdir(parents=True, exist_ok=True)
    specs = {(tag, lite, abi) for tag, editions in [('v0.0.263-alpha', [False, True]), ('v1.0.9', [False])]
             for lite in editions for abi in ABIS}
    # Also preserve monotonic versionCode and identity against the latest releases.
    releases = json.loads(command(['gh', 'api', f'repos/{args.repository}/releases?per_page=100']).stdout)
    for prerelease in [False, True]:
        latest = next((r for r in releases if not r['draft'] and r['prerelease'] == prerelease), None)
        if latest is None:
            continue
        tag = latest['tag_name']
        if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-alpha)?', tag):
            raise ValueError('Unexpected latest release tag')
        names = {asset['name'] for asset in latest['assets']}
        for lite in [False, True]:
            suffix = '-Lite' if lite else ''
            if f'RSTONE-{tag}{suffix}-x86_64-release.apk' in names:
                specs.add((tag, lite, 'x86_64'))

    def download(spec):
        tag, lite, abi = spec
        suffix = '-Lite' if lite else ''
        name = f'RSTONE-{tag}{suffix}-{abi}-release.apk'
        command(['gh', 'release', 'download', tag, '--repo', args.repository,
                 '--pattern', name, '--dir', output, '--skip-existing'])
        return spec, output / name

    with ThreadPoolExecutor(max_workers=3) as pool:
        paths = list(pool.map(download, sorted(specs)))
    tools = build_tools_directory(args.build_tools)
    records = []
    for (tag, lite, abi), path in paths:
        identity = apk_identity(path, tools)
        if identity['package'] != PACKAGE or identity['abis'] != [abi]:
            raise ValueError('Unexpected historical APK application ID or ABI')
        records.append(dict(identity, tag=tag, lite=lite, abi=abi, path=str(path)))
    if len({r['certificateSha256'] for r in records}) != 1:
        raise ValueError('Historical signing identities differ; a single replacement APK cannot cover them')
    (output / 'manifest.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    minimum = max(record['versionCode'] for record in records) + 1
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as target:
            target.write(f'minimum_build_code={minimum}\n')
    print(f'Historical APKs verified: {len(records)}, minimum new versionCode: {minimum}', flush=True)


class Device:
    def __init__(self, serial):
        if not serial.startswith('emulator-'):
            raise ValueError('Upgrade testing may only reset an isolated Android emulator')
        self.serial = serial
        if self.shell('getprop', 'ro.kernel.qemu').strip() != '1':
            raise ValueError('A virtual test device is required')
        self.adb('root')
        self.adb('wait-for-device')
        if self.shell('id', '-u').strip() != '0':
            raise ValueError('A rootable AOSP emulator is required to seed legacy private test data')

    def adb(self, *args, check=True):
        return command(['adb', '-s', self.serial, *args], check=check)

    def shell(self, *args, check=True):
        return self.adb('shell', ' '.join(shlex.quote(str(v)) for v in args), check=check).stdout.decode('utf-8', 'replace')

    def read(self, path, check=True):
        return self.adb('exec-out', 'cat', path, check=check).stdout

    def uid(self):
        match = re.search(r'\buserId=(\d+)', self.shell('dumpsys', 'package', PACKAGE))
        if match is None:
            raise ValueError('Installed application UID not found')
        return match.group(1)

    def launch(self, activity):
        if activity:
            self.shell('am', 'start', '-W', '-n', PACKAGE + '/' + activity)
        else:
            self.shell('monkey', '-p', PACKAGE, '-c', 'android.intent.category.LAUNCHER', '1')
        time.sleep(3)
        alive = self.shell('pidof', PACKAGE, check=False).strip()
        if not alive:
            alive = any(line.rstrip().endswith(' ' + PACKAGE) for line in self.shell('ps').splitlines())
        if not alive:
            raise ValueError('Application did not remain running after launch')


def preference_values(raw):
    values = {}
    for child in ET.fromstring(raw):
        values[child.attrib['name']] = child.text if child.tag == 'string' else child.attrib.get('value')
    return values


def exercise(args):
    records = json.loads(Path(args.baselines).read_text(encoding='utf-8'))
    tools = build_tools_directory(args.build_tools)
    device = Device(args.serial)
    api = int(device.shell('getprop', 'ro.build.version.sdk').strip())
    if args.expected_api is not None and api != args.expected_api:
        raise ValueError('The emulator API does not match the requested upgrade test')
    # This test must work without relying on official data being downloaded first.
    device.shell('svc', 'wifi', 'disable')
    device.shell('svc', 'data', 'disable')
    cases = [(record, record['lite']) for record in records if record['abi'] == 'x86_64']
    cross = next(r for r in records if r['tag'] == 'v0.0.263-alpha' and r['abi'] == 'x86_64' and not r['lite'])
    cases.append((cross, True))
    output = Path('build/upgrade-device-seed')
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for index, (old, lite) in enumerate(cases):
        suffix = '-Lite' if lite else ''
        new_apk = Path(args.directory) / f'RSTONE-{args.tag}{suffix}-x86_64-release.apk'
        new = apk_identity(new_apk, tools)
        assert_upgrade_compatible(new, old, android_api=api)
        # Each independent case starts fresh. There is NO uninstall or data clear
        # between installing the historical APK and installing its replacement.
        device.adb('uninstall', PACKAGE, check=False)
        device.adb('install', '--no-streaming', old['path'])
        uid = device.uid()
        root = '/data/user/0/' + PACKAGE
        legacy = root + '/app_flutter/rst_data'
        modern = root + '/files/rst_data'
        is_legacy = int(old['versionName'].split('.')[0]) < 2
        source = legacy if is_legacy else modern + '/user'
        files = {source + '/产品列表/' + PERSONAL_NAME + '.md': PERSONAL}
        if is_legacy:
            files[legacy + '/manual_items.json'] = json.dumps({'products': [PERSONAL_NAME], 'applications': [], 'formulas': []}).encode()
            files[legacy + '/tag_alias_rules.custom.txt'] = RULES
        else:
            files[modern + '/user/custom_rules/tag_alias_rules.custom.txt'] = RULES
        prefs = ET.Element('map')
        expected = {'flutter.product_notes': json.dumps({PERSONAL_NAME: NOTE}), 'flutter.theme_mode': 'dark'}
        for key, value in expected.items():
            ET.SubElement(prefs, 'string', name=key).text = value
        ET.SubElement(prefs, 'boolean', name='flutter.product_list_sort_desc', value='true')
        preference_path = root + '/shared_prefs/FlutterSharedPreferences.xml'
        files[preference_path] = ET.tostring(prefs, encoding='utf-8', xml_declaration=True)
        for number, (remote, data) in enumerate(files.items()):
            local = output / f'{index}-{number}.bin'
            local.write_bytes(data)
            device.shell('mkdir', '-p', remote.rsplit('/', 1)[0])
            device.adb('push', local, remote)
        for parent in ['app_flutter', 'files', 'shared_prefs']:
            device.shell('chown', '-R', uid + ':' + uid, root + '/' + parent, check=False)
        device.shell('restorecon', '-RF', root)
        context = re.search(r'u:object_r:[^\s]+', device.shell('ls', '-Zd', root))
        if context and device.shell('sh', '-c', 'command -v chcon', check=False).strip():
            for parent in ['app_flutter', 'files', 'shared_prefs']:
                device.shell('chcon', '-R', context.group(0), root + '/' + parent, check=False)
        device.launch(old['activity'])
        device.shell('am', 'force-stop', PACKAGE)
        if preference_values(device.read(preference_path)).get('flutter.product_notes') != expected['flutter.product_notes']:
            raise ValueError('Legacy application did not preserve the seeded notes')

        # Real PackageManager replacement. No downgrade flag is used.
        installed = device.adb('install', '--no-streaming', '-r', new_apk)
        if 'Success' not in installed.stdout.decode('utf-8', 'replace') or device.uid() != uid:
            raise ValueError('Package replacement failed or changed application identity')
        device.launch(new['activity'])
        migrated = modern + '/user/产品列表/' + PERSONAL_NAME + '.md'
        migrated_rules = modern + '/user/custom_rules/tag_alias_rules.custom.txt'
        deadline = time.monotonic() + 45
        while time.monotonic() < deadline and (device.read(migrated, check=False) != PERSONAL
                                               or device.read(migrated_rules, check=False) != RULES):
            time.sleep(1)
        if device.read(migrated) != PERSONAL:
            raise ValueError('Personal Markdown was not retained/migrated')
        if device.read(migrated_rules) != RULES:
            raise ValueError('Personal tag rules were not retained')
        values = preference_values(device.read(preference_path))
        if any(values.get(key) != value for key, value in expected.items()) or values.get('flutter.product_list_sort_desc') != 'true':
            raise ValueError('Notes, theme or sorting preferences changed during upgrade')
        if is_legacy and device.read(legacy + '/产品列表/' + PERSONAL_NAME + '.md') != PERSONAL:
            raise ValueError('Original personal data was removed')
        results.append({'from': old['tag'], 'fromLite': old['lite'], 'toLite': lite,
                        'oldVersionCode': old['versionCode'], 'newVersionCode': new['versionCode'],
                        'replaceInstall': True, 'uidPreserved': True, 'notesPreserved': True,
                        'personalMarkdownPreserved': True, 'customRulesPreserved': True, 'preferencesPreserved': True})
        print('Upgrade passed: ' + json.dumps(results[-1]), flush=True)
    Path(args.report).write_text(json.dumps({'tag': args.tag, 'androidApi': api, 'cases': results}, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='mode', required=True)
    baseline = commands.add_parser('prepare')
    baseline.add_argument('--repository', default='Mehael-Yeh/RSTONE_Flutter')
    baseline.add_argument('--directory', default='build/upgrade-baseline')
    baseline.add_argument('--build-tools')
    device_parser = commands.add_parser('device')
    device_parser.add_argument('--serial', default='emulator-5554')
    device_parser.add_argument('--baselines', default='build/upgrade-baseline/manifest.json')
    device_parser.add_argument('--directory', default='build/app/outputs/flutter-apk')
    device_parser.add_argument('--tag', required=True)
    device_parser.add_argument('--build-tools')
    device_parser.add_argument('--expected-api', type=int)
    device_parser.add_argument('--report', default='build/android-upgrade-verification.json')
    args = parser.parse_args()
    prepare(args) if args.mode == 'prepare' else exercise(args)
