/// Web stub for Platform.environment access
///
/// On web, there is no access to OS environment variables.
/// This stub returns null for all environment variable lookups.
library;

/// Get environment variable by key (web stub - always returns null)
String? getPlatformEnvironmentVariable(String key) => null;
