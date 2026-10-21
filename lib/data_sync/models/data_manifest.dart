import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import '../protocol/rstone_protocol.dart';

/// The protocol implementation is vendored from RSTONE_Data, without changing
/// its wire format. This envelope retains the exact signed bytes for recovery.
class DataManifest {
  final VerifiedManifest verified;
  final Uint8List latestBytes, manifestBytes, signatureBytes;
  DataManifest._(
      this.verified, this.latestBytes, this.manifestBytes, this.signatureBytes);
  int get sequence => verified.sequence;
  String get dataVersion => verified.dataVersion;
  String get hash => verified.manifestSha256;
  List<DataFile> get files => verified.files;

  static Future<DataManifest> verify({
    required Uint8List latest,
    required Uint8List manifest,
    required Uint8List signature,
    required Map<String, String> keys,
    required String appVersion,
    int highestSequence = 0,
    String? acceptedHash,
  }) async {
    final args = <String, Object?>{
      'latest': latest,
      'manifest': manifest,
      'signature': signature,
      'keys': keys,
      'appVersion': appVersion,
      'highestSequence': highestSequence,
      'acceptedHash': acceptedHash
    };
    final verified = manifest.length > 256 * 1024
        ? await compute(_verifyInWorker, args)
        : await _verifyInWorker(args);
    return DataManifest._(verified, latest, manifest, signature);
  }

  Map<String, dynamic> toJson() => {
        'latest': base64Encode(latestBytes),
        'manifest': base64Encode(manifestBytes),
        'signature': base64Encode(signatureBytes),
      };

  static Future<DataManifest> restore(Map<String, dynamic> json,
          Map<String, String> keys, String appVersion) =>
      verify(
        latest: base64Decode(json['latest'] as String),
        manifest: base64Decode(json['manifest'] as String),
        signature: base64Decode(json['signature'] as String),
        keys: keys,
        appVersion: appVersion,
      );
}

Future<VerifiedManifest> _verifyInWorker(Map<String, Object?> args) =>
    verifyManifest(
      latestBytes: args['latest'] as Uint8List,
      manifestBytes: args['manifest'] as Uint8List,
      signatureBytes: args['signature'] as Uint8List,
      trustedKeys: args['keys'] as Map<String, String>,
      appVersion: args['appVersion'] as String,
      highestSequence: args['highestSequence'] as int,
      acceptedManifestSha256: args['acceptedHash'] as String?,
    );
