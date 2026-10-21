import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models/data_manifest.dart';
import 'services/content_store.dart';
import 'services/diff_engine.dart';
import 'services/index_manager.dart';
import 'services/source_manager.dart';
import 'storage/storage_adapter.dart';

enum SyncStage {
  idle,
  checking,
  downloading,
  validating,
  committing,
  success,
  failed
}

class DataSyncService extends ChangeNotifier {
  final StorageAdapter storage;
  final SourceManager sources;
  final String appVersion;
  final IndexManager indexManager;
  late final ContentStore content = ContentStore(storage);
  DataManifest? current, remote;
  DataManifest? servingManifest;
  DataSnapshot snapshot = const DataSnapshot();
  DataSyncPlan? plan;
  SyncStage stage = SyncStage.idle;
  int downloadedBytes = 0, completedObjects = 0;
  DateTime? lastSuccess;
  String? error, lastLog;
  String? failureDetails;
  bool autoUpdate = true;
  Future<bool>? _running;
  Uint8List? _activeBytes;
  Map<String, dynamic>? _state;
  DateTime? _lastAutoCheck;
  bool _loaded = false;
  bool get isSyncing => _running != null;
  String get databaseVersion =>
      servingManifest?.dataVersion ??
      (current == null ? '尚未下载' : '${current!.dataVersion}（需要修复）');
  double? get progress => stage == SyncStage.downloading && plan != null
      ? (plan!.downloads.isEmpty
          ? 1
          : completedObjects / plan!.downloads.length)
      : null;

  DataSyncService(
      {required this.storage,
      required this.sources,
      required this.appVersion,
      IndexManager? indexManager})
      : indexManager = indexManager ?? IndexManager();

  Future<void> initialize() async {
    _loaded = false;
    final settings = await storage.readText('settings/sync');
    if (settings != null) {
      final value = jsonDecode(settings) as Map<String, dynamic>;
      autoUpdate = value['autoUpdate'] != false;
      sources.preferredSource = value['preferredSource'] as String?;
      if (!sources.sources
          .any((s) => s.baseUrl.toString() == sources.preferredSource)) {
        sources.preferredSource = null;
      }
    }
    _activeBytes = await storage.read(StorageAdapter.activeKey);
    if (_activeBytes == null) {
      _loaded = true;
      return;
    }
    _state = jsonDecode(utf8.decode(_activeBytes!)) as Map<String, dynamic>;
    current = await DataManifest.restore(
        Map<String, dynamic>.from(_state!['active'] as Map),
        sources.trustedKeys,
        appVersion);
    lastSuccess = DateTime.tryParse(_state!['lastSuccess'] as String? ?? '');
    lastLog = _state!['lastLog'] as String?;
    sources.currentSource = _state!['source'] as String?;
    if (_state!['highestSequence'] != current!.sequence ||
        _state!['acceptedHash'] != current!.hash) {
      throw StateError('本地版本指针与防回放记录不一致');
    }
    _loaded = true;
    try {
      snapshot = await _prepare(current!);
      servingManifest = current;
    } catch (e) {
      // A broken object is repaired against this same signed manifest, never
      // resurrected from assets or a scan of orphan objects.
      error = '本地资料需要校验与修复：$e';
      stage = SyncStage.failed;
      if (_state!['previous'] != null) {
        try {
          final previous = await DataManifest.restore(
              Map<String, dynamic>.from(_state!['previous'] as Map),
              sources.trustedKeys,
              appVersion);
          snapshot = await _prepare(previous);
          servingManifest = previous;
          error = '$error；当前暂用完整的 ${previous.dataVersion} 版本。';
        } catch (_) {/* No verified fallback; keep the database unavailable. */}
      }
    }
  }

  Future<void> setAutoUpdate(bool enabled) async {
    autoUpdate = enabled;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> selectSource(String? url) async {
    sources.preferredSource = url;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> _saveSettings() => storage.writeText(
      'settings/sync',
      jsonEncode({
        'autoUpdate': autoUpdate,
        'preferredSource': sources.preferredSource,
      }));

  void checkAutomatically() {
    if (!autoUpdate ||
        isSyncing ||
        sources.sources.isEmpty ||
        sources.trustedKeys.isEmpty) {
      return;
    }
    final now = DateTime.now();
    if (_lastAutoCheck != null &&
        now.difference(_lastAutoCheck!) < const Duration(minutes: 15)) {
      return;
    }
    _lastAutoCheck = now;
    unawaited(synchronize());
  }

  /// One flight for launch, resume, check and repair actions.
  Future<bool> synchronize({bool repair = false}) {
    if (_running != null) return _running!;
    final completer = Completer<bool>();
    _running = completer.future;
    () async {
      try {
        completer.complete(await _synchronize(repair: repair));
      } catch (e, stack) {
        completer.completeError(e, stack);
      } finally {
        _running = null;
        notifyListeners();
      }
    }();
    return completer.future;
  }

  void _stage(SyncStage value) {
    stage = value;
    notifyListeners();
  }

  Future<bool> _synchronize({required bool repair}) async {
    error = null;
    failureDetails = null;
    downloadedBytes = 0;
    completedObjects = 0;
    plan = null;
    _stage(SyncStage.checking);
    try {
      if (!_loaded) throw StateError('本地版本记录未通过校验，请先恢复有效的本地存储');
      // Another app window may have committed while this one was idle.
      if (!sameBytes(
          await storage.read(StorageAdapter.activeKey), _activeBytes)) {
        await initialize();
      }
      DataManifest target;
      try {
        target = (await sources.latest(
                appVersion: appVersion,
                highestSequence: current?.sequence ?? 0,
                acceptedHash: current?.hash))
            .manifest;
        remote = target;
      } catch (_) {
        if (!repair || current == null) rethrow;
        // Repair the installed signed version even if latest is unavailable.
        target = current!;
      }
      final valid = await content.validHashes(target.files, full: repair);
      plan = DataDiffEngine().compare(current, target, valid);
      _stage(SyncStage.downloading);
      for (final file in plan!.downloads) {
        final bytes = await sources.object(file);
        await content.save(file, bytes);
        downloadedBytes += bytes.length;
        completedObjects++;
        notifyListeners();
      }
      _stage(SyncStage.validating);
      // Build the entire next business snapshot before the pointer changes.
      // An index/parser failure leaves both the old pointer and old UI intact.
      final prepared = await _prepare(target);
      final timestamp = DateTime.now().toUtc();
      final log =
          '新增 ${plan!.count(DataChange.add)}，修改 ${plan!.count(DataChange.modify)}，'
          '删除 ${plan!.count(DataChange.delete)}，修复 ${plan!.count(DataChange.repair)}；'
          '实际下载 $downloadedBytes 字节';
      final nextState = <String, dynamic>{
        'active': target.toJson(),
        'highestSequence': target.sequence,
        'acceptedHash': target.hash,
        'previous': current?.sequence == target.sequence
            ? (_state?['previous'])
            : current?.toJson(),
        'lastSuccess': timestamp.toIso8601String(),
        'lastLog': log,
        'source': sources.currentSource,
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(nextState)));
      _stage(SyncStage.committing);
      await storage.commitActive(_activeBytes, bytes);
      // No await or potentially throwing index construction between these
      // assignments. Readers observe one complete in-memory generation.
      _activeBytes = bytes;
      _state = nextState;
      current = target;
      servingManifest = target;
      snapshot = prepared;
      lastSuccess = timestamp;
      lastLog = log;
      _stage(SyncStage.success);
      return true;
    } catch (e) {
      failureDetails = '$e';
      final details = '$e';
      error = details.contains('Unknown signing keyId') ||
              details.contains('Application upgrade required') ||
              details.contains('Unsupported schema')
          ? '当前客户端不支持该资料版本或签名密钥，请升级应用。已保留本地资料。'
          : details.contains('尚未配置')
              ? '官方数据源或签名公钥尚未配置。'
              : '更新未完成，已保留本地资料。请检查网络后重试，或运行数据校验与修复。';
      try {
        await storage.writeText(
            'logs/last_failure',
            jsonEncode({
              'time': DateTime.now().toUtc().toIso8601String(),
              'details': details
            }));
      } catch (_) {
        /* A full disk must not turn rollback into another failure. */
      }
      _stage(SyncStage.failed);
      return false;
    }
  }

  Future<DataSnapshot> _prepare(DataManifest manifest) async {
    final files = <String, String>{};
    for (final file in manifest.files) {
      if (!await content.containsValid(file)) {
        throw StateError('文件缺失或损坏：${file.path}');
      }
      final raw = await storage.read(content.key(file.sha256));
      if (raw == null) throw StateError('读取资料失败：${file.path}');
      files[file.path] = utf8.decode(raw);
    }
    return indexManager.prepare(files);
  }

  /// Local rollback would violate the replay watermark. Restores are issued by
  /// the publisher with a newer sequence; this message is also used in Settings.
  String get rollbackGuidance =>
      '恢复历史资料需要发布端发布新的恢复版本；本地不会降低已接受的版本序号。更新失败会自动保留原数据库。';

  // Old CAS objects are intentionally retained. No automatic GC runs until a
  // cross-process reader/maintenance lease is available on every platform.
}
