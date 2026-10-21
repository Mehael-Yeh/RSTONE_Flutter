import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
export 'package:share_plus/share_plus.dart' show XFile;

Future<XFile> shareFileBytes(Uint8List bytes,
    {required String name,
    required String mimeType,
    String? subject,
    String? text}) async {
  final file = XFile.fromData(bytes, name: name, mimeType: mimeType);
  await Share.shareXFiles([file],
      subject: subject, text: text, fileNameOverrides: [name]);
  return file;
}
