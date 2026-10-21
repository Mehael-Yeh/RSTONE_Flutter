"""Keep data credentials and Full/Lite resources out of incorrect release assets."""
import io
import json
import unittest
import zipfile

from verify_release_apks import ASSET_ROOT, FONTS, audit_assets


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


if __name__ == '__main__':
    unittest.main()
