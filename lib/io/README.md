# IO Layer

**Definition:** The IO layer handles ALL digital communication with the outside world, regardless of protocol or transport mechanism.

## Architecture

Two universal layers, three communication patterns.

### Universal Layers

- **Transport**: how bytes move. WebSocket, HTTP, SSE, Bluetooth, serial. Platform-specific (Rust FFI fixes Windows WebSocket TLS bug).
- **Protocol**: how bytes become messages. JSON framing, Phoenix channels, protobuf, custom wire formats. Pure Dart.

### Communication Patterns

Built on Transport + Protocol, each with its own interaction shape:

| Pattern | Example | Shape |
|---|---|---|
| DuplexStream | Deepgram WebSocket | send + receive simultaneously |
| RequestResponse | Groq HTTP, Jina API | request in, response out |
| Subscription | Supabase Realtime | connect, receive stream |

All three share Transport + Protocol underneath. Logging, metrics, retry attach at those layers and apply to all patterns.

### Why Rust?

`dart:io` WebSocket on Windows converts `wss://` to `https://` during HTTP upgrade, breaking TLS. Rust tungstenite handles this correctly. Rust is a platform bug workaround for one transport, not an architectural choice.

## Current Structure

```
lib/io/
├── transport/              # How bytes move (WebSocket via Rust/dart:io/web)
├── protocol/               # How bytes become messages
├── channel/                # DuplexStream pattern (legacy name, used by Deepgram)
├── patterns/               # Communication pattern interfaces
│   ├── subscription.dart   # Subscription pattern (Supabase Realtime)
│   └── request_response.dart  # RequestResponse pattern (HTTP APIs)
├── subscriptions/          # Subscription implementations
│   └── supabase_comm_subscription.dart
├── request_response/       # RequestResponse implementations
│   └── http_request_response.dart
├── io.dart                 # Main exports
├── io_exception.dart       # Exception types
└── README.md
```

## Current Status

- **DuplexStream**: Implemented as `Channel` (Deepgram STT).
- **Subscription**: Implemented for Supabase Realtime (comms ingestion).
- **RequestResponse**: Implemented as `HttpRequestResponse`. Supports base URI, auth token injection via `TokenProvider`, timeouts. Groq/Jina still use `dart:http` directly: migrate next.

## Design Principles

1. **Protocol agnostic** : abstractions, not protocol-specific APIs
2. **Performance where needed** : Rust FFI for transports with platform bugs
3. **Cross-platform** : all 6 platforms (iOS, Android, macOS, Windows, Linux, Web)
4. **Trainable** : communication patterns can be learned and optimized
