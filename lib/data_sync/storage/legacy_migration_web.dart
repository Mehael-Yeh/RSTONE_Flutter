import 'storage_adapter.dart';

Future<void> migrateLegacyData(StorageAdapter storage) async {
  // The previous Web app did not persist manual Markdown; preferences keep
  // their existing keys in SharedPreferences/localStorage.
  if (await storage.read('migration/v1') == null) {
    await storage.writeText('migration/v1', '{"imported":[],"quarantined":[]}');
  }
}
