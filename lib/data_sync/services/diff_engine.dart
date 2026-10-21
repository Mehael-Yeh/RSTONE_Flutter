import '../models/data_manifest.dart';
import '../protocol/rstone_protocol.dart';

enum DataChange { add, modify, delete, unchanged, repair }

class DataSyncPlan {
  final Map<String, DataChange> changes;
  final List<DataFile> downloads;
  DataSyncPlan(this.changes, this.downloads);
  int count(DataChange kind) => changes.values.where((v) => v == kind).length;
  int get downloadBytes => downloads.fold(0, (sum, f) => sum + f.size);
}

class DataDiffEngine {
  DataSyncPlan compare(
      DataManifest? current, DataManifest target, Set<String> validObjects) {
    final base = planSync(current?.verified, target.verified, validObjects);
    final changes = <String, DataChange>{
      for (final p in base.added) p: DataChange.add,
      for (final p in base.modified) p: DataChange.modify,
      for (final p in base.deleted) p: DataChange.delete,
      for (final p in base.unchanged) p: DataChange.unchanged,
    };
    for (final file in target.files) {
      if (changes[file.path] == DataChange.unchanged &&
          !validObjects.contains(file.sha256)) {
        changes[file.path] = DataChange.repair;
      }
    }
    return DataSyncPlan(
        Map.unmodifiable(changes), List.unmodifiable(base.missingObjects));
  }
}
