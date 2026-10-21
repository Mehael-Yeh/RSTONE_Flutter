"""Guard PackageManager identity parsing used by the real APK upgrade gate."""
import unittest

from verify_apk_upgrade import PACKAGE, package_uid


class PackageUidTest(unittest.TestCase):
    def test_reads_only_the_exact_installed_package(self):
        listing = (f'package:{PACKAGE}.other uid:10045\n'
                   f'package:{PACKAGE} uid:10123\n')
        self.assertEqual(package_uid(listing), '10123')

    def test_missing_ambiguous_or_privileged_uid_is_rejected(self):
        for listing in ['', f'package:{PACKAGE}.other uid:10123\n',
                        f'package:{PACKAGE} uid:1000\n',
                        f'package:{PACKAGE} uid:10123\npackage:{PACKAGE} uid:10124\n']:
            with self.assertRaises(ValueError):
                package_uid(listing)


if __name__ == '__main__':
    unittest.main()
