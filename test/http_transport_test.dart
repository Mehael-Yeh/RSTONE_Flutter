import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rst_flutter/data_sync/services/source_manager.dart';
import 'support/sync_fixture.dart';

void main() {
  test(
      'response limit uses decoded stream bytes rather than compressed Content-Length',
      () async {
    final client = MockClient.streaming((_, __) async => http.StreamedResponse(
        Stream.value(raw('small')), 200,
        contentLength: 100, headers: {'content-encoding': 'gzip'}));
    final transport = HttpDataTransport(client: client);
    expect(
        await transport.get(Uri.parse('https://test.invalid/object'),
            maxBytes: 5),
        raw('small'));
    transport.close();
  });

  test('decoded response exceeding the limit is rejected', () async {
    final client = MockClient.streaming((_, __) async => http.StreamedResponse(
        Stream.fromIterable([raw('123'), raw('456')]), 200));
    final transport = HttpDataTransport(client: client);
    await expectLater(
        transport.get(Uri.parse('https://test.invalid/object'), maxBytes: 5),
        throwsStateError);
    transport.close();
  });
}
