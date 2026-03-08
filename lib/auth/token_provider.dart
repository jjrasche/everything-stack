/// Provides access tokens for authenticated API calls.
/// Auth is a peer of IO: it produces tokens, IO consumes them as config.
abstract class TokenProvider {
  /// Get a valid access token, refreshing if expired.
  Future<String> getAccessToken();

  /// Whether valid credentials exist.
  bool get isAuthenticated;

  /// Release resources (cancel refresh timers, etc.)
  void dispose();
}

/// TokenProvider that returns a fixed token.
/// Useful for CLI tools where the token comes from az CLI or env vars.
class StaticTokenProvider implements TokenProvider {
  final String _token;

  StaticTokenProvider(this._token);

  @override
  Future<String> getAccessToken() async => _token;

  @override
  bool get isAuthenticated => _token.isNotEmpty;

  @override
  void dispose() {}
}
