"""Guard the 0.x to 1.0.0 protocol-shell release transition."""
import unittest
from next_app_version import next_version


class ReleaseVersionTest(unittest.TestCase):
    def test_new_shell_floor_survives_old_tags(self):
        for channel, tag in [("alpha", "v0.0.263-alpha"),
                             ("production", "v0.0.263")]:
            self.assertEqual(next_version("1.0.0", [tag], channel), "1.0.0")

    def test_empty_tags_use_pubspec(self):
        self.assertEqual(next_version("1.0.0", [], "production"), "1.0.0")

    def test_existing_current_version_is_incremented(self):
        self.assertEqual(next_version("1.0.0", ["v1.0.0-alpha"], "alpha"), "1.0.1")

    def test_channels_are_independent(self):
        self.assertEqual(next_version("1.0.0", ["v2.0.5-alpha"], "production"), "1.0.0")

    def test_numeric_version_order(self):
        self.assertEqual(next_version("1.0.0", ["v1.0.9", "v1.0.10"], "production"), "1.0.11")


if __name__ == "__main__":
    unittest.main()
