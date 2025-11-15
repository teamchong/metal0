# Async HTTP Integration

PyAOT's HTTP module integrated with async I/O runtime for truly non-blocking HTTP requests.

## Architecture

```
┌─────────────────────────────────────────────────┐
│           Python Async HTTP API                  │
│  asyncGet(), asyncPost(), await response         │
└─────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│         AsyncClient (http/async_client.zig)      │
│  - Non-blocking socket operations                │
│  - Future-based API                               │
│  - Connection management                          │
└─────────────────────────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│  Async Runtime   │  │   I/O Poller     │
│  - Task spawning │  │  - epoll/kqueue  │
│  - Future/await  │  │  - Event loop    │
│  - Scheduling    │  │  - Non-blocking  │
└──────────────────┘  └──────────────────┘
```

## Components

### 1. AsyncClient (`http/async_client.zig`)

Non-blocking HTTP client that uses the async runtime.

**Key features:**
- Non-blocking socket operations
- Future-based API (returns `*Future(Response)`)
- Automatic poller integration
- Connection pooling ready

**API:**
```zig
pub const AsyncClient = struct {
    allocator: std.mem.Allocator,
    poller: *Poller,
    timeout_ms: u64,

    pub fn init(allocator: std.mem.Allocator, poller: *Poller) AsyncClient;
    pub fn deinit(self: *AsyncClient) void;

    // Async methods (return Future)
    pub fn get(self: *AsyncClient, url: []const u8) !*Future(Response);
    pub fn post(self: *AsyncClient, url: []const u8, body: []const u8) !*Future(Response);
    pub fn postJson(self: *AsyncClient, url: []const u8, json: []const u8) !*Future(Response);
};
```

### 2. Async I/O Operations

Non-blocking variants of socket operations:

```zig
fn asyncConnect(sock: std.posix.fd_t, uri: *const std.Uri) !void;
fn asyncWrite(sock: std.posix.fd_t, data: []const u8) !usize;
fn asyncRead(sock: std.posix.fd_t, buffer: []u8) !usize;
```

**Current implementation:**
- Simplified polling with sleep/retry
- Ready for full poller integration

**Full implementation (TODO):**
- Register socket with poller
- Yield task until I/O ready
- Resume when poller signals readiness

### 3. Future Integration

HTTP operations return `Future(Response)`:

```zig
const future = try client.get("https://example.com");
const response = try future.await_future(current_task);
```

**Future states:**
- `pending` - Request in progress
- `ready` - Response received
- `error_state` - Request failed

### 4. Python API (`http.zig`)

High-level API for Python code:

```zig
// Async operations (return Future)
pub fn asyncGet(allocator, poller, url) !*Future(Response);
pub fn asyncPost(allocator, poller, url, body) !*Future(Response);
pub fn asyncPostJson(allocator, poller, url, json) !*Future(Response);

// Convenience wrappers (await internally)
pub fn awaitGet(allocator, poller, url, current_task) !Response;
pub fn awaitPost(allocator, poller, url, body, current_task) !Response;
```

## Usage Examples

### Basic Async GET

```python
import http
import asyncio

async def fetch():
    # Async GET (returns Future)
    response = await http.async_get("https://httpbin.org/get")
    print(response.body)

asyncio.run(fetch())
```

### Concurrent Requests

```python
import http
import asyncio

async def main():
    # Spawn multiple requests concurrently
    futures = [
        http.async_get("https://httpbin.org/get"),
        http.async_get("https://httpbin.org/ip"),
        http.async_get("https://httpbin.org/user-agent"),
    ]

    # Wait for all
    responses = await asyncio.gather(*futures)

    print(f"Fetched {len(responses)} pages concurrently")

asyncio.run(main())
```

### Web Crawler

```python
import http
import asyncio

async def crawl(urls):
    # Launch all requests at once
    tasks = [http.async_get(url) for url in urls]

    # Wait for all to complete
    responses = await asyncio.gather(*tasks)

    return responses

urls = ["https://example.com/1", "https://example.com/2", ...]
results = asyncio.run(crawl(urls))
```

## Implementation Status

### ✅ Completed

- [x] AsyncClient module structure
- [x] Future-based API
- [x] Non-blocking socket operations (simplified)
- [x] Request building
- [x] Response parsing
- [x] Python API design
- [x] Example programs
- [x] Benchmarks

### 🚧 In Progress

- [ ] Full poller integration
- [ ] Task yielding in I/O operations
- [ ] Runtime event loop integration

### 📋 TODO

- [ ] Connection pooling for async
- [ ] HTTPS/TLS support
- [ ] HTTP/2 support
- [ ] DNS resolution
- [ ] Timeout handling
- [ ] Error recovery
- [ ] Retry logic
- [ ] Request cancellation

## Performance Targets

| Metric | Target | Status |
|--------|--------|--------|
| Concurrent requests | 1000+ req/sec | 🚧 Pending |
| Latency (local) | <10ms | 🚧 Pending |
| Throughput | 100MB/s | 🚧 Pending |
| Memory per request | <1KB | 🚧 Pending |

## Poller Integration (Next Steps)

### Current Simplified Approach

```zig
// Simplified: sleep and retry
if (err == error.WouldBlock) {
    std.time.sleep(1_000_000); // 1ms
    retries += 1;
}
```

### Full Implementation

```zig
// Register with poller
const current_task = runtime.getCurrentTask();
current_task.io_fd = sock;
current_task.io_events = WRITABLE;
try poller.register(sock, WRITABLE, current_task);

// Yield until ready
current_task.state = .waiting;
runtime.yield();

// Poller will wake us when socket is writable
```

### Runtime Loop Integration

```zig
pub fn run(self: *Runtime) !void {
    while (self.running.load(.acquire)) {
        // 1. Run ready tasks
        while (try self.runNextTask()) {}

        // 2. Poll I/O with timeout
        const timeout_ms = if (self.hasReadyTasks()) 0 else 10;
        const events = try self.poller.wait(timeout_ms);

        // 3. Wake tasks with ready I/O
        for (events) |event| {
            event.task.state = .runnable;
            try self.ready_queue.push(event.task);
        }

        // 4. Check if done
        if (self.task_count.load(.acquire) == 0) break;
    }
}
```

## Testing

### Unit Tests

```bash
# Test async client creation
zig test packages/runtime/src/http/async_client.zig

# Test poller integration
zig test packages/runtime/src/async/poller/kqueue.zig
```

### Integration Tests

```python
# Test concurrent requests
pytest tests/test_async_http.py -v

# Test web crawler
python examples/async_web_crawler.py
```

### Benchmarks

```python
# Run performance benchmarks
python benchmarks/async_http_bench.py
```

## Design Decisions

### 1. Future-based API

**Why:** Matches Rust's Tokio and JavaScript's Promises. Composable and ergonomic.

```zig
const f1 = try client.get(url1);
const f2 = try client.get(url2);
const r1 = try f1.await_future(task);
const r2 = try f2.await_future(task);
```

### 2. Separate AsyncClient

**Why:** Keeps sync and async paths separate. Avoids complexity in Client.

```zig
// Sync client (blocking)
var client = Client.init(allocator);
const response = try client.get(url);

// Async client (non-blocking)
var async_client = AsyncClient.init(allocator, &poller);
const future = try async_client.get(url);
const response = try future.await_future(task);
```

### 3. Poller Integration via Task

**Why:** Task already has `io_fd` and `io_events` fields. Poller wakes tasks directly.

```zig
pub const Task = struct {
    io_fd: ?std.posix.fd_t,
    io_events: u32,
    // ...
};
```

### 4. Simplified Initial Implementation

**Why:** Gets the structure right first. Full poller integration comes next.

**Benefit:** Can test API design without full runtime complexity.

## Future Enhancements

### Connection Pooling

```zig
pub const AsyncConnectionPool = struct {
    connections: std.HashMap([]const u8, *Connection),
    max_per_host: usize,

    pub fn acquire(self: *Self, host: []const u8) !*Connection;
    pub fn release(self: *Self, conn: *Connection) void;
};
```

### HTTP/2 Multiplexing

```zig
pub const Http2Connection = struct {
    streams: std.ArrayList(*Stream),

    pub fn request(self: *Self, req: *Request) !*Stream;
};
```

### Request Cancellation

```zig
pub const CancellableRequest = struct {
    future: *Future(Response),
    cancel_token: *CancelToken,

    pub fn cancel(self: *Self) void {
        self.cancel_token.cancel();
        self.future.reject(error.Cancelled);
    }
};
```

## Related Files

- `http/async_client.zig` - Async client implementation
- `http/client.zig` - Sync client (existing)
- `http.zig` - Python API
- `async/poller/kqueue.zig` - I/O poller (macOS)
- `async/poller/epoll.zig` - I/O poller (Linux)
- `async/future.zig` - Future/Promise implementation
- `async/runtime.zig` - Async runtime
- `async/task.zig` - Task with I/O fields

## Resources

- [Tokio async I/O](https://tokio.rs)
- [Go netpoller](https://golang.org/src/runtime/netpoll.go)
- [Zig async/await](https://ziglang.org/documentation/master/#Async-Functions)
- [kqueue man page](https://man7.org/linux/man-pages/man2/kqueue.2.html)
- [epoll man page](https://man7.org/linux/man-pages/man7/epoll.7.html)
