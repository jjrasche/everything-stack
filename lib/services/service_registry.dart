import 'trainable.dart';

/// Configuration for any service with multiple implementations
class ServiceConfig {
  /// Provider identifier: 'groq', 'claude', 'deepgram', 'google', etc.
  final String provider;

  /// Provider-specific credentials and settings
  /// Examples:
  /// - {'apiKey': 'gsk_...'}
  /// - {'apiKey': 'sk-...', 'baseUrl': 'https://...'}
  /// - {'projectId': '...', 'region': 'us-central1'}
  final Map<String, dynamic> credentials;

  const ServiceConfig({
    required this.provider,
    this.credentials = const {},
  });

  @override
  String toString() => 'ServiceConfig(provider=$provider)';
}

/// Unified service registry for all multi-implementation services
class ServiceRegistry {
  static final Map<String, dynamic> _services = {};

  /// Register a service instance
  ///
  /// Example:
  /// ```dart
  /// ServiceRegistry.register<InferenceService>('llm', groqService);
  /// ```
  static void register<T>(String name, T service) {
    _services[name] = service;
    print('📦 Registered service: $name = ${service.runtimeType}');
  }

  /// Get current service instance
  ///
  /// Throws if service not registered
  static T get<T>(String name) {
    if (!_services.containsKey(name)) {
      throw ServiceRegistryException(
        'Service "$name" not registered. Available: ${_services.keys.join(", ")}',
      );
    }
    return _services[name] as T;
  }

  /// Get service safely (returns null if not registered)
  static T? getOrNull<T>(String name) {
    return _services[name] as T?;
  }

  /// Switch provider at runtime (no rebuild needed!)
  ///
  /// Example:
  /// ```dart
  /// await ServiceRegistry.switchProvider<InferenceService>(
  ///   'llm',
  ///   ServiceConfig(provider: 'claude', credentials: {...}),
  ///   InferenceServiceFactory.create,
  /// );
  /// ```
  static Future<void> switchProvider<T>(
    String serviceName,
    ServiceConfig config,
    T Function(ServiceConfig) factory,
  ) async {
    print('\n🔄 Switching provider for $serviceName to: ${config.provider}');

    final newService = factory(config);
    print('✅ Created new ${newService.runtimeType}');

    register<T>(serviceName, newService);
    print('✅ Switched to ${config.provider}');
  }

  /// Get all registered services
  static Map<String, Type> getAllServices() {
    return _services.map((key, value) => MapEntry(key, value.runtimeType));
  }

  /// Clear all services (useful for testing)
  static void clear() {
    _services.clear();
  }
}

/// Exception thrown by service registry
class ServiceRegistryException implements Exception {
  final String message;

  ServiceRegistryException(this.message);

  @override
  String toString() => 'ServiceRegistryException: $message';
}
