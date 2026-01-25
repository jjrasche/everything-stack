/// # WebSocket Transport (tungstenite)
///
/// Replaces dart:io WebSocket on native platforms.
/// Uses tungstenite for cross-platform WebSocket support.
///
/// ## Architecture
/// - Connection registry: DashMap<u64, Connection>
/// - Receive task: Spawned on Tokio runtime, pushes to StreamSink
/// - Send: Direct via WebSocketStream
///
/// ## State Machine
/// Disconnected → Connecting → Connected → Disconnecting → Disconnected

use dashmap::DashMap;
use once_cell::sync::Lazy;
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::net::TcpStream;
use tokio_tungstenite::{
    connect_async, tungstenite::protocol::Message, MaybeTlsStream, WebSocketStream,
};
use url::Url;

use crate::runtime::RUNTIME;

/// Global connection registry.
/// Rust owns WebSocket connections, Dart gets handles.
static CONNECTIONS: Lazy<DashMap<u64, Connection>> = Lazy::new(DashMap::new);

/// Global handle counter.
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

/// WebSocket configuration.
#[derive(Clone)]
pub struct WebSocketConfig {
    pub url: String,
    pub headers: Vec<(String, String)>,
}

/// WebSocket connection state.
pub enum Connection {
    Connecting,
    Connected {
        ws: WebSocketStream<MaybeTlsStream<TcpStream>>,
    },
    Disconnected,
}

/// WebSocket connection management.
pub struct WebSocketConnection;

impl WebSocketConnection {
    /// Connect to WebSocket server.
    pub fn connect(config: WebSocketConfig) -> Result<u64, String> {
        let handle = NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);

        // Parse URL
        let url = Url::parse(&config.url).map_err(|e| format!("Invalid URL: {}", e))?;

        // Insert connecting state
        CONNECTIONS.insert(handle, Connection::Connecting);

        // Connect synchronously (block until complete)
        let result = RUNTIME.block_on(async move {
            Self::connect_async(url, config.headers).await
        });

        match result {
            Ok(ws) => {
                // Update to connected state
                CONNECTIONS.insert(handle, Connection::Connected { ws });
                Ok(handle)
            }
            Err(e) => {
                eprintln!("WebSocket connection failed: {}", e);
                CONNECTIONS.remove(&handle);
                Err(e)
            }
        }
    }

    /// Async connect using tungstenite.
    async fn connect_async(
        url: Url,
        _headers: Vec<(String, String)>,
    ) -> Result<WebSocketStream<MaybeTlsStream<TcpStream>>, String> {
        // Convert Url to string for tungstenite
        let (ws_stream, _response) = connect_async(url.as_str())
            .await
            .map_err(|e| format!("Connection failed: {}", e))?;

        Ok(ws_stream)
    }

    /// Send binary data to WebSocket.
    pub fn send(handle: u64, data: Vec<u8>) -> Result<(), String> {
        let mut conn = CONNECTIONS
            .get_mut(&handle)
            .ok_or_else(|| "Connection not found".to_string())?;

        match &mut *conn {
            Connection::Connected { ws } => {
                // Spawn send task
                RUNTIME.block_on(async {
                    use futures::SinkExt;
                    ws.send(Message::Binary(data.into()))
                        .await
                        .map_err(|e| format!("Send failed: {}", e))
                })
            }
            _ => Err("Not connected".to_string()),
        }
    }

    /// Close WebSocket connection.
    pub fn close(handle: u64) -> Result<(), String> {
        let mut conn = CONNECTIONS
            .get_mut(&handle)
            .ok_or_else(|| "Connection not found".to_string())?;

        match &mut *conn {
            Connection::Connected { ws } => {
                RUNTIME.block_on(async {
                    use futures::SinkExt;
                    ws.close(None)
                        .await
                        .map_err(|e| format!("Close failed: {}", e))
                })?;

                // Update state
                *conn = Connection::Disconnected;
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Dispose connection and free resources.
    pub fn dispose(handle: u64) {
        CONNECTIONS.remove(&handle);
    }

    /// Get connection state as string (for debugging).
    pub fn state(handle: u64) -> Result<String, String> {
        let conn = CONNECTIONS
            .get(&handle)
            .ok_or_else(|| "Connection not found".to_string())?;

        let state_str = match &*conn {
            Connection::Connecting => "Connecting",
            Connection::Connected { .. } => "Connected",
            Connection::Disconnected => "Disconnected",
        };

        Ok(state_str.to_string())
    }
}
