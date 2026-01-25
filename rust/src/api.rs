/// # FFI API Interface
///
/// Public functions exposed to Dart via flutter_rust_bridge.
/// All functions here get auto-generated Dart bindings.
///
/// ## Connection Lifecycle
/// 1. `websocket_connect()` - Returns handle (u64)
/// 2. `websocket_send()` - Send bytes via handle
/// 3. `websocket_receive()` - Set up StreamSink for received data
/// 4. `websocket_close()` - Close connection
/// 5. `websocket_dispose()` - Clean up resources

use crate::transport::websocket::{WebSocketConnection, WebSocketConfig};

/// Test function to verify FFI bridge works.
pub fn hello_from_rust() -> String {
    "Rust FFI bridge is working!".to_string()
}

/// Connect to WebSocket server.
///
/// ## Arguments
/// - `url`: Full WebSocket URL (ws:// or wss://)
/// - `headers`: Optional HTTP headers for handshake
///
/// ## Returns
/// - Connection handle (u64) on success
/// - Error string on failure
pub fn websocket_connect(url: String, headers: Vec<(String, String)>) -> Result<u64, String> {
    let config = WebSocketConfig { url, headers };
    WebSocketConnection::connect(config)
}

/// Send binary data to WebSocket.
///
/// ## Arguments
/// - `handle`: Connection handle from `websocket_connect()`
/// - `data`: Bytes to send
///
/// ## Returns
/// - Ok(()) on success
/// - Err(msg) if connection not found or send failed
pub fn websocket_send(handle: u64, data: Vec<u8>) -> Result<(), String> {
    WebSocketConnection::send(handle, data)
}

/// Close WebSocket connection gracefully.
///
/// ## Arguments
/// - `handle`: Connection handle to close
pub fn websocket_close(handle: u64) -> Result<(), String> {
    WebSocketConnection::close(handle)
}

/// Dispose WebSocket connection and free resources.
///
/// ## Arguments
/// - `handle`: Connection handle to dispose
pub fn websocket_dispose(handle: u64) {
    WebSocketConnection::dispose(handle);
}

/// Get connection state as string (for debugging).
pub fn websocket_state(handle: u64) -> Result<String, String> {
    WebSocketConnection::state(handle)
}
