import 'package:flutter/foundation.dart';
import '../protocol/rstone_protocol.dart';

Future<bool> verifyContent(DataFile file, Uint8List bytes) =>
    bytes.length < 256 * 1024
        ? verifyObject(file, bytes)
        : compute(_verifyInWorker, (file, bytes));

Future<bool> _verifyInWorker((DataFile, Uint8List) input) =>
    verifyObject(input.$1, input.$2);
