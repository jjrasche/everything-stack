import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';

typedef ActionHandler = Future<Map<String, dynamic>> Function(Map<String, String> params);
typedef ScreenshotCallback = Future<String?> Function();

class DebugServer {
  static DebugServer? _instance;
  static DebugServer get instance => _instance ??= DebugServer._();

  DebugServer._();

  HttpServer? _server;
  final Map<String, dynamic Function()> _stateProviders = {};
  final Map<String, ActionHandler> _actions = {};
  ScreenshotCallback? _screenshotCallback;
  final List<String> _logs = [];
  static const int _maxLogs = 500;

  /// Register a state provider (called to get current state)
  void registerStateProvider(String name, dynamic Function() provider) {
    _stateProviders[name] = provider;
  }

  /// Register an action that can be triggered via HTTP
  void registerAction(String name, ActionHandler handler) {
    _actions[name] = handler;
  }

  /// Set the screenshot callback (called when /screenshot is requested)
  void setScreenshotCallback(ScreenshotCallback callback) {
    _screenshotCallback = callback;
  }

  /// Add a log entry
  void log(String message) {
    final entry = '[${DateTime.now().toIso8601String()}] $message';
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
  }

  /// Start the debug server
  Future<void> start({int port = 9999}) async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      log('DebugServer started on http://localhost:$port');
      print('🔧 [DebugServer] Started on http://localhost:$port');

      _server!.listen(_handleRequest);
    } catch (e) {
      print('⚠️ [DebugServer] Failed to start: $e');
      log('Failed to start: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final params = request.uri.queryParameters;

    log('${request.method} $path');

    try {
      if (path == '/state') {
        await _handleState(request);
      } else if (path == '/screenshot') {
        await _handleScreenshot(request);
      } else if (path == '/search') {
        await _handleSearch(request, params);
      } else if (path.startsWith('/entity/')) {
        final uuid = path.substring('/entity/'.length);
        await _handleEntity(request, uuid);
      } else if (path == '/chunks') {
        await _handleChunks(request, params);
      } else if (path == '/logs') {
        await _handleLogs(request);
      } else if (path.startsWith('/ui/')) {
        // UI automation endpoints: /ui/tap, /ui/type, /ui/slide, /ui/tree, /ui/find, /ui/state
        final uiAction = path.substring(1); // Strip leading '/' → 'ui/tap', etc.
        await _handleAction(request, uiAction, params);
      } else if (path.startsWith('/action/')) {
        final actionName = path.substring('/action/'.length);
        await _handleAction(request, actionName, params);
      } else if (path == '/health') {
        await _respondJson(request, {'status': 'ok', 'timestamp': DateTime.now().toIso8601String()});
      } else {
        await _respondJson(request, {
          'error': 'Unknown endpoint',
          'availableEndpoints': [
            'GET /state',
            'GET /screenshot',
            'GET /search?q=...',
            'GET /entity/{uuid}',
            'GET /chunks?entityId=...',
            'GET /logs',
            'POST /action/{name}',
            'GET /health',
            'POST /ui/tap?target=...',
            'POST /ui/type?target=...&text=...&submit=true',
            'POST /ui/slide?target=...&value=0.5',
            'POST /ui/long_press?target=...',
            'GET /ui/tree',
            'GET /ui/find?label=...',
          ]
        }, statusCode: 404);
      }
    } catch (e, stack) {
      log('Error handling $path: $e');
      await _respondJson(request, {
        'error': e.toString(),
        'stack': stack.toString().split('\n').take(10).toList(),
      }, statusCode: 500);
    }
  }

  Future<void> _handleState(HttpRequest request) async {
    final state = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'providers': _stateProviders.keys.toList(),
    };

    for (final entry in _stateProviders.entries) {
      try {
        state[entry.key] = entry.value();
      } catch (e) {
        state[entry.key] = {'error': e.toString()};
      }
    }

    await _respondJson(request, state);
  }

  Future<void> _handleScreenshot(HttpRequest request) async {
    if (_screenshotCallback == null) {
      await _respondJson(request, {'error': 'Screenshot callback not registered'}, statusCode: 501);
      return;
    }

    final path = await _screenshotCallback!();
    if (path != null) {
      await _respondJson(request, {'screenshot': path, 'timestamp': DateTime.now().toIso8601String()});
    } else {
      await _respondJson(request, {'error': 'Failed to capture screenshot'}, statusCode: 500);
    }
  }

  Future<void> _handleSearch(HttpRequest request, Map<String, String> params) async {
    final query = params['q'];
    if (query == null || query.isEmpty) {
      await _respondJson(request, {'error': 'Missing query parameter: q'}, statusCode: 400);
      return;
    }

    final searchAction = _actions['search'];
    if (searchAction == null) {
      await _respondJson(request, {'error': 'Search action not registered'}, statusCode: 501);
      return;
    }

    final result = await searchAction(params);
    await _respondJson(request, result);
  }

  Future<void> _handleEntity(HttpRequest request, String uuid) async {
    final entityAction = _actions['getEntity'];
    if (entityAction == null) {
      await _respondJson(request, {'error': 'Entity action not registered'}, statusCode: 501);
      return;
    }

    final result = await entityAction({'uuid': uuid});
    await _respondJson(request, result);
  }

  Future<void> _handleChunks(HttpRequest request, Map<String, String> params) async {
    final chunksAction = _actions['getChunks'];
    if (chunksAction == null) {
      await _respondJson(request, {'error': 'Chunks action not registered'}, statusCode: 501);
      return;
    }

    final result = await chunksAction(params);
    await _respondJson(request, result);
  }

  Future<void> _handleLogs(HttpRequest request) async {
    await _respondJson(request, {
      'count': _logs.length,
      'logs': _logs.reversed.take(100).toList(),
    });
  }

  Future<void> _handleAction(HttpRequest request, String actionName, Map<String, String> params) async {
    final action = _actions[actionName];
    if (action == null) {
      await _respondJson(request, {
        'error': 'Unknown action: $actionName',
        'availableActions': _actions.keys.toList(),
      }, statusCode: 404);
      return;
    }

    final result = await action(params);
    await _respondJson(request, result);
  }

  Future<void> _respondJson(HttpRequest request, Map<String, dynamic> data, {int statusCode = 200}) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(const JsonEncoder.withIndent('  ').convert(data));
    await request.response.close();
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    log('DebugServer stopped');
  }
}
