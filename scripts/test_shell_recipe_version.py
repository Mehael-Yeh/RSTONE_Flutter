import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def version_tuple(value):
    return tuple(map(int, value.split('.')))


def versions():
    pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    main = (ROOT / 'lib/main.dart').read_text(encoding='utf-8')
    checked = re.search(r'^version:\s*(\d+\.\d+\.\d+)', pubspec, re.M)
    fallback = re.search(
        r"String\.fromEnvironment\('APP_VERSION',\s*defaultValue:\s*'(\d+\.\d+\.\d+)'\)",
        main,
    )
    if checked is None or fallback is None:
        raise AssertionError('shell version metadata unavailable')
    return checked.group(1), fallback.group(1)


class ShellRecipeVersionFloorTest(unittest.TestCase):
    def test_web_source_version_supports_recipe_v2_floor(self):
        checked, _ = versions()
        self.assertGreaterEqual(version_tuple(checked), (2, 0, 5))

    def test_offline_compiled_fallback_supports_recipe_v2_floor(self):
        _, fallback = versions()
        self.assertGreaterEqual(version_tuple(fallback), (2, 0, 5))

    def test_service_default_matches_the_versioned_shell(self):
        checked, _ = versions()
        service = (ROOT / 'lib/services/obsidian_data_service.dart').read_text(encoding='utf-8')
        match = re.search(r"this\.appVersion\s*=\s*'(\d+\.\d+\.\d+)'", service)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), checked)

    def test_web_and_offline_source_versions_stay_in_sync(self):
        checked, fallback = versions()
        self.assertEqual(checked, fallback)
        workflow = (ROOT / '.github/workflows/deploy_web_pages.yml').read_text(encoding='utf-8')
        self.assertIn('pubspec.yaml', workflow)
        self.assertIn('--dart-define=APP_VERSION="$RSTONE_APP_VERSION"', workflow)


if __name__ == '__main__':
    unittest.main()
