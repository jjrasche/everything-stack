/// # Global Tokio Runtime
///
/// Single global Tokio runtime for all async operations.
/// Lazy-initialized on first use to avoid startup overhead.
///
/// ## Why Global?
/// - Avoid creating multiple runtimes (expensive)
/// - Shared across all WebSocket connections
/// - Lives for entire application lifetime

use once_cell::sync::Lazy;
use tokio::runtime::Runtime;

/// Global Tokio runtime.
/// Initialized on first access.
pub static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    Runtime::new().expect("Failed to create Tokio runtime")
});

/// Ensure runtime is initialized.
/// Call this from init() to catch startup failures early.
pub fn ensure_runtime() {
    let _ = &*RUNTIME;
}
