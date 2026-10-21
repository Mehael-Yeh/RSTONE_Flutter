import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/data_manifest.dart';
import '../protocol/rstone_protocol.dart';
import 'integrity_verifier.dart';

class DataSource {
  final String name;
  final Uri baseUrl;
  DataSource(this.name, String url)
      : baseUrl = Uri.parse(url.endsWith('/') ? url : '$url/') {
    if (baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        baseUrl.userInfo.isNotEmpty) {
      throw ArgumentError('数据源必须是无凭证的 HTTPS 地址');
    }
  }
}

abstract class DataTransport {
  Future<Uint8List> get(Uri url, {required int maxBytes});
  void close();
}

class HttpDataTransport implements DataTransport {
  final http.Client _client;
  final Duration timeout;
  HttpDataTransport(
      {http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();
  @override
  Future<Uint8List> get(Uri url, {required int maxBytes}) async {
    final request = http.Request('GET', url)..followRedirects = false;
    // No cookies, authorization, or custom headers requiring CORS preflight.
    final response = await _client.send(request).timeout(timeout);
    // Content-Length may describe the compressed wire representation while
    // http yields decoded bytes. Enforce the limit on the byte stream below.
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('下载失败 (${response.statusCode})');
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(timeout)) {
      if (body.length + chunk.length > maxBytes) throw StateError('下载内容超出大小限制');
      body.add(chunk);
    }
    return body.takeBytes();
  }

  @override
  void close() => _client.close();
}

class ManifestCandidate {
  final DataManifest manifest;
  final DataSource source;
  ManifestCandidate(this.manifest, this.source);
}

class SourceManager {
  final List<DataSource> sources;
  final DataTransport transport;
  final Map<String, String> trustedKeys;
  String? preferredSource;
  String? currentSource;
  final List<String> failures = [];
  SourceManager(
      {required this.sources,
      required this.trustedKeys,
      DataTransport? transport})
      : transport = transport ?? HttpDataTransport();

  List<DataSource> get ordered => [
        for (final source in sources)
          if (source.baseUrl.toString() == preferredSource) source,
        for (final source in sources)
          if (source.baseUrl.toString() != preferredSource) source,
      ];

  Future<ManifestCandidate> latest(
      {required String appVersion,
      int highestSequence = 0,
      String? acceptedHash}) async {
    failures.clear();
    if (sources.isEmpty || trustedKeys.isEmpty) {
      throw StateError('官方数据源或签名公钥尚未配置');
    }
    final candidates = <ManifestCandidate>[];
    for (final source in ordered) {
      try {
        final pointer = await transport.get(
            source.baseUrl.resolve('latest.json').replace(queryParameters: {
              'rstone_check': DateTime.now().microsecondsSinceEpoch.toString()
            }),
            maxBytes: 16384);
        final index = parseUniqueJson(pointer);
        if (index is! Map ||
            index['sequence'] is! int ||
            index['sequence'] < 1 ||
            index['sequence'] > 9007199254740991) {
          throw const FormatException('无效的数据版本索引');
        }
        final name = index['sequence'].toString().padLeft(6, '0');
        // Construct both paths ourselves; never follow URLs from unsigned JSON.
        final raw = await transport.get(
            source.baseUrl.resolve('manifests/$name.json'),
            maxBytes: 32 * 1024 * 1024);
        final sig = await transport
            .get(source.baseUrl.resolve('manifests/$name.sig'), maxBytes: 512);
        final manifest = await DataManifest.verify(
            latest: pointer,
            manifest: raw,
            signature: sig,
            keys: trustedKeys,
            appVersion: appVersion,
            highestSequence: highestSequence,
            acceptedHash: acceptedHash);
        candidates.add(ManifestCandidate(manifest, source));
      } catch (e) {
        if (e is FormatException &&
            e.message == 'Same-sequence manifest conflict') {
          throw StateError('发现已验签的同序号清单冲突，已停止更新');
        }
        failures.add('${source.name}: $e');
      }
    }
    if (candidates.isEmpty) {
      throw StateError('未能获取可信数据，继续使用本地资料。${failures.join('；')}');
    }
    final hashes = <int, String>{};
    for (final candidate in candidates) {
      final m = candidate.manifest;
      if (hashes.containsKey(m.sequence) && hashes[m.sequence] != m.hash) {
        throw StateError('镜像存在同序号清单冲突，已停止更新');
      }
      hashes[m.sequence] = m.hash;
    }
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.manifest.sequence > best.manifest.sequence) {
        best = candidate;
      }
    }
    currentSource = best.source.name;
    return best;
  }

  Future<Uint8List> object(DataFile file) async {
    for (final source in ordered) {
      try {
        final bytes = await transport.get(
            source.baseUrl.resolve('objects/${file.sha256}'),
            maxBytes: file.size);
        if (!await verifyContent(file, bytes)) {
          throw const FormatException('文件大小或 SHA-256 不匹配');
        }
        currentSource = source.name;
        return bytes;
      } catch (e) {
        failures.add('${source.name}: $e');
      }
    }
    throw StateError('所有数据源均未能提供完整文件，已保留原数据库');
  }
}
