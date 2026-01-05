/// # Component Type Constants
///
/// Centralized constants for component types.
/// Prevents typos, ensures consistency across the codebase.
class ComponentType {
  // Core pipeline services
  static const String llm = 'llm';
  static const String stt = 'stt';
  static const String tts = 'tts';

  // Trainable orchestration components
  static const String toolSelector = 'tool_selector';
  static const String namespaceSelector = 'namespace_selector';
  static const String contextInjector = 'context_injector';
  static const String llmConfigSelector = 'llm_config_selector';

  // Execution
  static const String toolExecutor = 'tool_executor';
}
