/// Standalone debug server for querying ObjectBox database
/// Run: dart run scripts/debug_server.dart
/// Then: curl http://localhost:8888/invocations/imported?limit=5

import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../lib/objectbox.g.dart';
import '../lib/persistence/objectbox/wrappers/invocation_ob.dart';

void main() async {
  print('🔧 Starting standalone debug server...');

  // Open ObjectBox store
  final store = await openStore(directory: 'objectbox');
  print('📂 Opened ObjectBox database\n');

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler((request) => _handleRequest(request, store));

  final server = await shelf_io.serve(handler, 'localhost', 8888);
  print('🌐 Debug server running on http://localhost:${server.port}\n');
  print('Available endpoints:');
  print('  GET /invocations/imported?limit=5&offset=0');
  print('  GET /invocations/count');
  print('  GET /health');
  print('');
  print('Press Ctrl+C to stop\n');
}

Future<Response> _handleRequest(Request request, Store store) async {
  final path = request.url.path;
  final params = request.url.queryParameters;

  try {
    if (path == 'health') {
      return _jsonResponse({'status': 'ok', 'timestamp': DateTime.now().toIso8601String()});
    }

    if (path == 'invocations/count') {
      final box = store.box<InvocationOB>();
      final all = box.getAll();
      final imported = all.where((inv) => inv.implementer == 'claude_import').length;

      return _jsonResponse({
        'total': all.length,
        'imported': imported,
      });
    }

    if (path == 'invocations/imported') {
      final limit = int.tryParse(params['limit'] ?? '10') ?? 10;
      final offset = int.tryParse(params['offset'] ?? '0') ?? 0;

      final box = store.box<InvocationOB>();
      final all = box.getAll();
      final imported = all.where((inv) => inv.implementer == 'claude_import').toList();

      // Sort by created date (newest first)
      imported.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      final page = imported.skip(offset).take(limit).toList();

      return _jsonResponse({
        'total': imported.length,
        'offset': offset,
        'limit': limit,
        'results': page.map((inv) => {
          'uuid': inv.uuid,
          'eventId': inv.eventId,
          'createdAt': inv.createdAt.toIso8601String(),
          'input': {
            'prompt': inv.input?['prompt'],
          },
          'output': {
            'response': inv.output?['response'],
          },
        }).toList(),
      });
    }

    return Response.notFound(jsonEncode({
      'error': 'Unknown endpoint',
      'available': [
        '/health',
        '/invocations/count',
        '/invocations/imported?limit=5&offset=0',
      ],
    }), headers: {'Content-Type': 'application/json'});
  } catch (e, stack) {
    return Response.internalServerError(
      body: jsonEncode({
        'error': e.toString(),
        'stack': stack.toString().split('\n').take(10).toList(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Response _jsonResponse(Map<String, dynamic> data) {
  return Response.ok(
    jsonEncode(data),
    headers: {'Content-Type': 'application/json'},
  );
}
