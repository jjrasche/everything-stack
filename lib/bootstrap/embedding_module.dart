import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'bootstrap_module.dart';
import '../bootstrap.dart';
import '../services/embedding_service.dart';
import '../services/tokenizer_service.dart';
import '../services/service_registry.dart';
import '../services/service_builders.dart';

class EmbeddingModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    final embeddingConfig = ServiceConfig(
      provider: config.embeddingProvider ?? 'jina',
      credentials: {
        if (config.jinaApiKey != null) 'apiKey': config.jinaApiKey!,
        if (config.geminiApiKey != null) 'apiKey': config.geminiApiKey!,
      },
    );

    try {
      final service =
          createService<EmbeddingService>('embedding', embeddingConfig);
      EmbeddingService.instance = service;

      if (service is! NullEmbeddingService) {
        await service.initialize();
        debugPrint('✅ Embedding: ${service.runtimeType}');
      } else {
        debugPrint('ℹ️ Embedding: disabled');
      }

      ServiceRegistry.register<EmbeddingService>('embedding', service);
    } catch (e) {
      debugPrint('⚠️ Embedding init failed: $e');
    }

    getIt.registerSingleton<EmbeddingService>(EmbeddingService.instance);
    getIt.registerSingleton<TokenizerService>(TokenizerService.instance);
  }
}
