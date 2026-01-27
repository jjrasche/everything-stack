/**
 * WebSocket Echo Server for Nerve System Integration Tests
 *
 * Endpoints:
 *   /echo              - Echo all messages (text and binary)
 *   /fail-connect      - Reject connection immediately
 *   /disconnect-after/N - Disconnect after N messages
 *   /slow-echo/MS      - Echo with MS millisecond delay
 */

const { WebSocketServer } = require('ws');
const http = require('http');
const url = require('url');

const PORT = process.env.PORT || 8080;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('Nerve Echo Server');
});

const wss = new WebSocketServer({ server });

wss.on('connection', (ws, req) => {
  const pathname = url.parse(req.url).pathname;

  // /fail-connect - reject immediately
  if (pathname === '/fail-connect') {
    ws.close(1008, 'Connection rejected');
    return;
  }

  // /disconnect-after/N - disconnect after N messages
  const disconnectMatch = pathname.match(/^\/disconnect-after\/(\d+)$/);
  if (disconnectMatch) {
    let count = 0;
    const limit = parseInt(disconnectMatch[1], 10);
    ws.on('message', (data, isBinary) => {
      count++;
      ws.send(data, { binary: isBinary });
      if (count >= limit) {
        ws.close(1000, `Disconnected after ${limit} messages`);
      }
    });
    return;
  }

  // /slow-echo/MS - echo with delay
  const slowMatch = pathname.match(/^\/slow-echo\/(\d+)$/);
  if (slowMatch) {
    const delay = parseInt(slowMatch[1], 10);
    ws.on('message', (data, isBinary) => {
      setTimeout(() => {
        if (ws.readyState === ws.OPEN) {
          ws.send(data, { binary: isBinary });
        }
      }, delay);
    });
    return;
  }

  // Default: /echo or any other path - simple echo
  ws.on('message', (data, isBinary) => {
    ws.send(data, { binary: isBinary });
  });
});

server.listen(PORT, () => {
  console.log(`Nerve Echo Server running on ws://localhost:${PORT}`);
  console.log('Endpoints:');
  console.log('  /echo              - Echo all messages');
  console.log('  /fail-connect      - Reject connection');
  console.log('  /disconnect-after/N - Disconnect after N messages');
  console.log('  /slow-echo/MS      - Echo with delay');
});
