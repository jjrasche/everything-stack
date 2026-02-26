import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import '../../bootstrap/bootstrap_module.dart';
import '../../bootstrap.dart';
import '../../core/chunk_repository.dart';
import '../../core/invocation.dart';
import '../../core/invocation_repository.dart';
import '../../core/entity_repository.dart';
import '../../core/enrichment_queue_repository.dart';
import '../../core/repository_registry.dart';
import '../../core/persistence/persistence_adapter.dart';
import '../embedding_service.dart';
import '../tokenizer_service.dart';
import '../chunking_service.dart';
import '../chunking/semantic_chunker.dart';
import '../chunking/chunking_config.dart';
import '../hnsw_index.dart';
import '../hnsw_index_store.dart';
import 'semantic_search_service.dart';
import 'entity_loader_impl.dart';
import '../enrichment/enrichment_runner.dart';
import '../enrichment/semantic_enrichment_worker.dart';
import '../../services/hnsw_index_store_web.dart'
    if (dart.library.io) '../../services/hnsw_index_store_native.dart';

class SemanticSearchModule extends BootstrapModule {
  @override
  Future<void> register(GetIt getIt, EverythingStackConfig config) async {
    if (kIsWeb) return;

    final (hnswIndex, indexStore, needsRebuild) =
        await _loadOrCreateIndex(getIt);
    _registerChunking(getIt, hnswIndex);
    if (needsRebuild) {
      await _rebuildIndex(getIt, hnswIndex, indexStore);
    }
    await _registerEnrichment(getIt);
    _registerSearch(getIt, hnswIndex);
    _wireInvocationRepository(getIt);
  }

  Future<(HnswIndex, HnswIndexStore, bool)> _loadOrCreateIndex(
    GetIt getIt,
  ) async {
    final indexStore = createHnswIndexStore(_getIndexStorePath());
    final loadResult = await indexStore.loadIndex();

    final hnswIndex = loadResult.isLoaded
        ? loadResult.index!
        : HnswIndex(dimensions: 384);

    getIt.registerSingleton<HnswIndexStore>(indexStore);
    getIt.registerSingleton<HnswIndex>(hnswIndex);

    return (hnswIndex, indexStore, !loadResult.isLoaded);
  }

  void _registerChunking(GetIt getIt, HnswIndex hnswIndex) {
    getIt.registerSingleton<ChunkingService>(ChunkingService(
      index: hnswIndex,
      embeddingService: EmbeddingService.instance,
      tokenizerService: TokenizerService.instance,
      parentChunker: SemanticChunker(config: ChunkingConfig.parent()),
      childChunker: SemanticChunker(config: ChunkingConfig.child()),
      chunkRepo: getIt<ChunkRepository>(),
    ));
  }

  Future<void> _registerEnrichment(GetIt getIt) async {
    final repoRegistry = RepositoryRegistry();
    getIt.registerSingleton<RepositoryRegistry>(repoRegistry);

    try {
      final enrichmentQueueRepo = EnrichmentQueueRepository(
        adapter: getIt<EnrichmentQueueAdapter>(),
      );
      getIt.registerSingleton<EnrichmentQueueRepository>(enrichmentQueueRepo);

      final enrichmentRunner = EnrichmentRunner(
        queueRepo: enrichmentQueueRepo,
        workers: [
          SemanticEnrichmentWorker(
            chunkingService: getIt<ChunkingService>(),
            repoRegistry: repoRegistry,
          ),
        ],
        batchSize: 10,
      );
      getIt.registerSingleton<EnrichmentRunner>(enrichmentRunner);
      await enrichmentRunner.initialize();
    } catch (_) {
      // Enrichment is optional — search works without it
    }
  }

  void _registerSearch(GetIt getIt, HnswIndex hnswIndex) {
    final entityLoader = EntityLoaderImpl();
    entityLoader.registerDefaults();
    getIt.registerSingleton<SemanticSearchService>(SemanticSearchService(
      index: hnswIndex,
      embeddingService: EmbeddingService.instance,
      entityLoader: entityLoader,
      chunkingService: getIt<ChunkingService>(),
    ));
  }

  void _wireInvocationRepository(GetIt getIt) {
    final invocationRepo = createInvocationRepository(
      adapter: getIt<InvocationRepository<Invocation>>()
          as PersistenceAdapter<Invocation>,
      embeddingService: EmbeddingService.instance,
      chunkingService: getIt<ChunkingService>(),
      enrichmentRunner: getIt.isRegistered<EnrichmentRunner>()
          ? getIt<EnrichmentRunner>()
          : null,
    );
    getIt.registerSingleton<EntityRepository<Invocation>>(invocationRepo);
    getIt<RepositoryRegistry>().register<Invocation>(invocationRepo);
  }

  Future<void> _rebuildIndex(
    GetIt getIt,
    HnswIndex hnswIndex,
    HnswIndexStore indexStore,
  ) async {
    await getIt<ChunkingService>().rebuildIndexFromStorage();
    if (hnswIndex.size > 0) {
      indexStore.saveIndex(hnswIndex).catchError((_) {});
    }
  }

  String _getIndexStorePath() {
    if (kIsWeb) return '';
    return 'objectbox';
  }
}
