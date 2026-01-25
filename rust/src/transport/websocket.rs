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

use futures::stream::{SplitSink, SplitStream};
use std::sync::Arc;
use tokio::sync::Mutex;

/// WebSocket connection state.
pub enum Connection {
    Connecting,
    Connected {
        sink: SplitSink<WebSocketStream<MaybeTlsStream<TcpStream>>, Message>,
        stream: Option<SplitStream<WebSocketStream<MaybeTlsStream<TcpStream>>>>,
        received_queue: Arc<Mutex<Vec<Vec<u8>>>>,
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
                // Split WebSocket into sink (send) and stream (receive)
                use futures::StreamExt;
                let (sink, stream) = ws.split();

                // Create queue for received messages
                let received_queue = Arc::new(Mutex::new(Vec::new()));

                // Update to connected state
                CONNECTIONS.insert(handle, Connection::Connected {
                    sink,
                    stream: Some(stream),
                    received_queue,
                });
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
            Connection::Connected { sink, .. } => {
                // Send via sink
                RUNTIME.block_on(async {
                    use futures::SinkExt;
                    sink.send(Message::Binary(data.into()))
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
            Connection::Connected { sink, .. } => {
                RUNTIME.block_on(async {
                    use futures::SinkExt;
                    sink.close()
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

    /// Start receiving data from WebSocket and push to queue.
    ///
    /// Takes ownership of the receive stream and spawns a task that reads
    /// messages and queues them for Dart to poll.
    ///
    /// ## Important
    /// - Can only be called once per connection
    /// - Subsequent calls will fail (stream already taken)
    pub fn start_receive(handle: u64) -> Result<(), String> {
        // Get connection and extract stream + queue
        let mut conn = CONNECTIONS
            .get_mut(&handle)
            .ok_or_else(|| "Connection not found".to_string())?;

        let (stream, queue) = match &mut *conn {
            Connection::Connected { stream, received_queue, .. } => {
                let s = stream.take().ok_or_else(|| "Receive already started".to_string())?;
                let q = Arc::clone(received_queue);
                (s, q)
            }
            _ => return Err("Not connected".to_string()),
        };

        // Drop the mutex guard before spawning task
        drop(conn);

        // Spawn receive task
        RUNTIME.spawn(async move {
            use futures::StreamExt;
            let mut stream = stream;

            while let Some(msg_result) = stream.next().await {
                match msg_result {
                    Ok(Message::Binary(data)) => {
                        // Push to queue
                        let mut q = queue.lock().await;
                        q.push(data.to_vec());
                    }
                    Ok(Message::Text(text)) => {
                        // Convert text to bytes and push
                        let mut q = queue.lock().await;
                        q.push(text.as_bytes().to_vec());
                    }
                    Ok(Message::Close(_)) => {
                        println!("🦀 WebSocket closed by server");
                        break;
                    }
                    Ok(_) => {} // Ping/Pong handled automatically
                    Err(e) => {
                        eprintln!("🦀 Receive error: {}", e);
                        break;
                    }
                }
            }

            // Clean up connection when stream ends
            CONNECTIONS.remove(&handle);
        });

        Ok(())
    }

    /// Poll for received messages.
    ///
    /// Returns all queued messages and clears the queue.
    pub fn poll_receive(handle: u64) -> Result<Vec<Vec<u8>>, String> {
        let conn = CONNECTIONS
            .get(&handle)
            .ok_or_else(|| "Connection not found".to_string())?;

        match &*conn {
            Connection::Connected { received_queue, .. } => {
                // Get all messages from queue
                let messages = RUNTIME.block_on(async {
                    let mut q = received_queue.lock().await;
                    let messages = q.drain(..).collect();
                    messages
                });
                Ok(messages)
            }
            _ => Err("Not connected".to_string()),
        }
    }
}
