"""Keep data credentials and Full/Lite resources out of incorrect release assets."""
import io
import json
import unittest
import zipfile

from verify_release_apks import ASSET_ROOT, FONTS, assert_upgrade_compatible, audit_assets


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
               'versionCode': 30000000, 'versionName': '2.0.0', 'minSdk': 21}
        for version in ['0.0.263', '1.0.9']:
            old = dict(new, versionName=version, versionCode=29749969)
            assert_upgrade_compatible(new, old)

    def test_upgrade_rejects_new_identity_and_old_version_code(self):
        old = {'package': 'com.rstone.rstone_flutter', 'certificateSha256': 'same',
               'versionCode': 29749969, 'versionName': '1.0.9', 'minSdk': 21}
        new = dict(old, versionCode=30000000, versionName='2.0.0')
        for change in [{'package': 'another.app'}, {'certificateSha256': 'different'},
                       {'versionCode': 29749969}, {'versionName': '1.0.0'}, {'minSdk': 23}]:
            with self.assertRaises(ValueError):
                assert_upgrade_compatible(dict(new, **change), old)


if __name__ == '__main__':
    unittest.main()
