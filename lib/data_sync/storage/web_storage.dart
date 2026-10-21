import 'package:idb_shim/idb_browser.dart';
import 'indexed_db_storage.dart';
import 'storage_adapter.dart';

Future<StorageAdapter> openStorage() => IndexedDbStorage.open(idbFactoryNative);
