# IO Layer

**Definition:** The IO layer handles ALL digital communication with the outside world, regardless of protocol or transport mechanism.

## What IO Is

IO (Input/Output) is the **communication substrate** for Everything Stack. Any service or tool that sends/receives data to/from external systems goes through the IO layer.

**Current implementations:**
- WebSocket communication (Rust FFI for performance)
- Message framing and protocols
- Channel management

**Future implementations:**
- HTTP/REST APIs
- gRPC
- MQTT
- Bluetooth
- Serial communication
- Any other digital communication protocol

## Architectural Position

**IO is NOT a leaf dependency.** It is a **foundational layer** that sits between:
- Core/Services/Tools (consumers)
- External world (network, devices, APIs)

```
[Core/Services/Tools]
         ↓
     [IO Layer] ← ALL digital communication passes through here
         ↓
  [External World]
```

Every service that communicates externally depends on IO:
- STT service → IO → Deepgram WebSocket
- LLM service → IO → Groq HTTP API
- Tool executor → IO → External APIs
- Future services → IO → Any protocol

## Design Principles

1. **Protocol agnostic** - IO provides abstractions, not protocol-specific APIs
2. **Performance critical** - Uses Rust FFI where needed for efficiency
3. **Cross-platform** - Works on all 6 platforms (Android, iOS, macOS, Windows, Linux, Web)
4. **Trainable** - Communication patterns can be learned and optimized

## Current Structure

```
lib/io/
├── channel/               # Communication channel abstraction
├── protocol/              # Message protocols
├── transport/             # Transport layer (WebSocket, future HTTP/gRPC)
├── io.dart                # Main exports
├── io_exception.dart      # Exception types
└── README.md              # This file
```

## Adding New Protocols

When adding HTTP, gRPC, or other protocols:

1. Create protocol-specific files in `transport/` (e.g., `http_transport.dart`)
2. Implement common `Transport` interface
3. Add platform-specific adapters if needed
4. Register with transport factory for runtime selection

The IO layer provides the **pattern** for all digital communication, not just one protocol.
