"""Keep data credentials and Full/Lite resources out of incorrect release assets."""
import io
import json
import unittest
import zipfile

from verify_release_apks import ASSET_ROOT, FONTS, assert_upgrade_compatible, audit_assets, parse_identity


class ReleaseAssetsTest(unittest.TestCase):
    def archive(self, lite=False, markdown=False, config=None):
        handle = io.BytesIO()
        with zipfile.ZipFile(handle, 'w') as archive:
            archive.writestr(ASSET_ROOT + 'assets/data_sync_config.json', json.dumps(config or {'keys': {'production': 'pinned'}}))
            for name in ([] if lite else FONTS):
                archive.writestr(ASSET_ROOT + 'assets/fonts/' + name, b'font')
            if markdown:
                archive.writestr(ASSET_ROOT + 'assets/products/RS1.md', b'old asset')
        return zipfile.ZipFile(handle)

    def test_both_editions_have_their_expected_assets(self):
        for lite in [False, True]:
            with self.archive(lite=lite) as archive:
                audit_assets(archive, {'keys': {'production': 'pinned'}}, lite)

    def test_old_markdown_cannot_ship(self):
        with self.archive(markdown=True) as archive:
            with self.assertRaisesRegex(ValueError, 'Markdown'):
                audit_assets(archive, {'keys': {'production': 'pinned'}}, False)

    def test_incorrect_trust_configuration_is_rejected(self):
        with self.archive(config={'keys': {'test': 'example'}}) as archive:
            with self.assertRaisesRegex(ValueError, 'trust configuration'):
                audit_assets(archive, {'keys': {'production': 'pinned'}}, False)

    def test_full_fonts_cannot_ship_in_lite(self):
        with self.archive(lite=False) as archive:
            with self.assertRaisesRegex(ValueError, 'font boundary'):
                audit_assets(archive, {'keys': {'production': 'pinned'}}, True)

    def test_upgrade_accepts_legacy_stable_and_alpha(self):
        new = {'package': 'com.rstone.rstone_flutter', 'certificateSha256': 'same',
               'versionCode': 30000000, 'versionName': '2.0.0', 'minSdk': 29}
        for version in ['0.0.263', '1.0.9']:
            old = dict(new, versionName=version, versionCode=29749969, minSdk=21)
            assert_upgrade_compatible(new, old)
            assert_upgrade_compatible(new, old, android_api=35)
            with self.assertRaises(ValueError):
                assert_upgrade_compatible(new, old, android_api=28)

    def test_upgrade_rejects_new_identity_and_old_version_code(self):
        old = {'package': 'com.rstone.rstone_flutter', 'certificateSha256': 'same',
               'versionCode': 29749969, 'versionName': '1.0.9', 'minSdk': 21}
        new = dict(old, versionCode=30000000, versionName='2.0.0', minSdk=29)
        for change in [{'package': 'another.app'}, {'certificateSha256': 'different'},
                       {'versionCode': 29749969}, {'versionName': '1.0.0'}, {'minSdk': 30}]:
            with self.assertRaises(ValueError):
                assert_upgrade_compatible(dict(new, **change), old)


class ApkMetadataTest(unittest.TestCase):
    metadata = ("package: name='com.rstone.rstone_flutter' versionName='2.0.0' versionCodeMajor='0' versionCode='30000000'\n"
                "sdkVersion:'21'\n")

    def test_tool_attribute_order_and_qualified_uppercase_certificate(self):
        cert = '8A593A18B7F62500F1F47F27643C04456F51C5756DEFD9D9460365E058495658'
        value = parse_identity(self.metadata, f'Signer #1 (SDK range) certificate SHA-256 digest: {cert}\n', {'x86_64'})
        self.assertEqual(value['certificateSha256'], cert.lower())
        self.assertEqual(value['versionCode'], 30000000)
        self.assertEqual(value['minSdk'], 21)

    def test_distinct_signing_identities_cannot_be_merged(self):
        signatures = ''.join(f'Signer #{i} certificate SHA-256 digest: {str(i) * 64}\n' for i in [1, 2])
        with self.assertRaises(ValueError):
            parse_identity(self.metadata, signatures, {'x86_64'})

    def test_missing_native_payload_cannot_be_verified(self):
        with self.assertRaises(ValueError):
            parse_identity(self.metadata, 'Signer #1 certificate SHA-256 digest: ' + 'a' * 64, set())


if __name__ == '__main__':
    unittest.main()
