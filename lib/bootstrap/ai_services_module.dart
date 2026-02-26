import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'bootstrap_module.dart';
import 'implementer_selector.dart';
import '../bootstrap.dart';
import '../core/invocation.dart';
import '../core/invocation_repository.dart';
import '../core/adaptation_state_repository.dart';
import '../core/feedback_repository.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/inference_service.dart';
import '../services/service_registry.dart';
import '../services/implementations/stt_implementer.dart';
import '../services/implementations/tts_implementer.dart';
import '../services/implementations/llm_implementer.dart';
import '../services/implementations/groq_implementer.dart';
import '../services/implementations/deepgram_implementer.dart';
import '../services/implementations/deepgram_flux_implementer.dart';
import '../services/implementations/flutter_tts_implementer.dart';
import '../services/implementations/google_cloud_tts_implementer.dart';

class AiServicesModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    final invocationRepo = getIt<InvocationRepository<Invocation>>();
    ServiceRegistry.register<InvocationRepository<Invocation>>(
      'invocation_repo',
      invocationRepo,
    );

    _registerStt(getIt, config, invocationRepo);
    _registerTts(getIt, config, invocationRepo);
    _registerLlm(getIt, config, invocationRepo);
  }

  void _registerStt(
    GetIt getIt,
    EverythingStackConfig config,
    InvocationRepository<Invocation> invocationRepo,
  ) {
    final implementers = <String, STTImplementer>{};
    if (config.deepgramApiKey != null && config.deepgramApiKey!.isNotEmpty) {
      implementers['deepgram_batch'] = DeepgramImplementer(
        apiKey: config.deepgramApiKey!,
        model: 'nova-2',
      );
      implementers['deepgram_flux'] = DeepgramFluxImplementer(
        apiKey: config.deepgramApiKey!,
        model: 'flux-general-en',
      );
    }

    if (implementers.isEmpty) {
      debugPrint('⏭️  STT skipped (no API key)');
      return;
    }

    final defaultImpl = implementers.containsKey('deepgram_flux')
        ? 'deepgram_flux'
        : selectCompatibleImplementer(implementers, 'STT');

    final sttService = STTService(
      implementers: implementers,
      defaultImplementer: defaultImpl,
      invocationRepo: invocationRepo,
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<STTService>(sttService);
    debugPrint('✅ STT: $defaultImpl (${implementers.length} implementers)');
  }

  void _registerTts(
    GetIt getIt,
    EverythingStackConfig config,
    InvocationRepository<Invocation> invocationRepo,
  ) {
    final implementers = <String, TTSImplementer>{
      'flutter_tts': FlutterTtsImplementer(),
    };

    if (config.googleTtsApiKey != null && config.googleTtsApiKey!.isNotEmpty) {
      implementers['google_cloud_tts'] = GoogleCloudTTSImplementer(
        apiKey: config.googleTtsApiKey!,
      );
    }

    final defaultImpl = selectCompatibleImplementer(implementers, 'TTS');

    final ttsService = TTSService(
      implementers: implementers,
      defaultImplementer: defaultImpl,
      invocationRepo: invocationRepo,
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<TTSService>(ttsService);
    debugPrint('✅ TTS: $defaultImpl (${implementers.length} implementers)');
  }

  void _registerLlm(
    GetIt getIt,
    EverythingStackConfig config,
    InvocationRepository<Invocation> invocationRepo,
  ) {
    final implementers = <String, LLMImplementer>{};
    if (config.groqApiKey != null && config.groqApiKey!.isNotEmpty) {
      implementers['groq'] = GroqImplementer(apiKey: config.groqApiKey!);
    }

    if (implementers.isEmpty) {
      debugPrint('⏭️  LLM skipped (no API key)');
      return;
    }

    final defaultImpl = selectCompatibleImplementer(implementers, 'LLM');

    final llmService = InferenceService(
      implementers: implementers,
      defaultImplementer: defaultImpl,
      invocationRepo: invocationRepo,
      adaptationStateRepo: getIt<AdaptationStateRepository>(),
      feedbackRepo: getIt<FeedbackRepository>(),
    );
    getIt.registerSingleton<InferenceService>(llmService);
    debugPrint('✅ LLM: $defaultImpl (${implementers.length} implementers)');
  }
}
