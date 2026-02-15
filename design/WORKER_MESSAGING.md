# Worker Messaging: Safe Marshalled Communication for FasterBASIC Workers

## 1. Motivation

FasterBASIC's WORKER system provides isolated, thread-safe concurrency with a clean
`SPAWN` / `AWAIT` lifecycle. However, the current model only supports **one-shot
communication**: arguments go in at spawn time, a single result comes out at await
time. There is no way for a running worker to exchange data with the main program
or with other workers while it is executing.

This limitation prevents several important use cases:

| Use Case | Why Current Model Falls Short |
|----------|-------------------------------|
| **Progress reporting** | A long-running worker cannot report percentage complete back to the main program |
| **Streaming results** | A worker processing a large data set cannot emit partial results as they become available |
| **Dynamic work distribution** | The main program cannot feed new tasks to a running worker |
| **Cooperative pipelines** | Worker A cannot pass intermediate results to Worker B without going through main + AWAIT + re-SPAWN |
| **Cancellation** | The main program has no way to signal a worker to stop early |
| **Interactive computation** | A worker cannot ask the main program for additional data mid-computation |

### 1.1 Design Principles

Any messaging extension must preserve FasterBASIC's core worker guarantees:

1. **Isolation** — No shared mutable state. All data crossing a thread boundary is
   deep-copied via marshalling.
2. **Compile-time safety** — Violations are caught by the semantic analyser, not at
   runtime.
3. **Simplicity** — The API must be approachable for BASIC programmers. No channels,
   mutexes, atomics, or select statements.
4. **Value semantics** — Every message is an independent copy. The sender and receiver
   never alias the same memory.
5. **Deterministic resource cleanup** — Message queues are drained and freed when a
   worker is awaited or when the program exits.

### 1.2 Non-Goals

- **Shared memory regions** — Contradicts isolation.
- **Unbounded fan-out** — Workers cannot spawn sub-workers (existing rule preserved).
- **Priority queues** — Messages are FIFO. Priority adds complexity with little benefit
  for BASIC-level concurrency.
- **Distributed messaging / networking** — This is in-process, in-memory only.

---

## 2. Design Overview

The design extends the existing `FutureHandle` to carry **two bounded, thread-safe
message queues** — one for each direction of communication. Messages are always
marshalled blobs, enforced by the compiler. The BASIC programmer interacts with six
new keywords/builtins.

```
                    ┌──────────────┐
                    │  Main Thread │
                    └──────┬───────┘
                           │
              SPAWN ───────┤
                           │
                    ┌──────▼───────┐
                    │ FutureHandle │
                    │              │
                    │  outbox ──────────► worker reads via RECEIVE(PARENT)
                    │  (main→worker)│
                    │              │
                    │  inbox ◄──────────  worker writes via SEND PARENT, msg
                    │  (worker→main)│
                    └──────┬───────┘
                           │
              AWAIT ───────┘
```

The main program uses the future handle directly. The worker uses the `PARENT`
pseudo-handle, which the compiler resolves to a pointer threaded through the
worker's argument block.

---

## 3. Syntax

### 3.1 Sending a Message

```basic
' From main program to a running worker:
SEND future_handle, expression

' From inside a worker back to main:
SEND PARENT, expression
```

`SEND` is non-blocking. It marshalls the expression, enqueues the blob, and returns
immediately. If the queue is full, `SEND` blocks until space is available (bounded
back-pressure — see §6.2).

The expression can be:
- A scalar (`DOUBLE`, `INTEGER`, `STRING`)
- A `MARSHALLED` blob (from an explicit `MARSHALL()` call)
- A UDT variable (auto-marshalled by the compiler)

The compiler determines the expression type and emits the appropriate marshalling
call automatically. The programmer never needs to manually `MARSHALL` for `SEND` —
it is done implicitly. Explicit `MARSHALL()` is still accepted for symmetry with
existing worker arguments.

### 3.2 Receiving a Message

```basic
' Main program receives from a worker (blocking):
DIM msg AS DOUBLE
msg = RECEIVE(future_handle)

' Worker receives from main (blocking):
DIM cmd AS INTEGER
cmd = RECEIVE(PARENT)

' Receiving a UDT:
DIM point AS Vec3
point = RECEIVE(future_handle)   ' auto-unmarshalled into Vec3
```

`RECEIVE` blocks until a message is available. The message blob is unmarshalled
into the target variable's type automatically.

### 3.3 Non-Blocking Check

```basic
IF HASMESSAGE(future_handle) THEN
    DIM value AS DOUBLE
    value = RECEIVE(future_handle)
END IF

' Inside a worker:
IF HASMESSAGE(PARENT) THEN
    DIM cmd AS INTEGER
    cmd = RECEIVE(PARENT)
END IF
```

`HASMESSAGE(handle)` returns `1` if at least one message is queued, `0` otherwise.
This is the polling primitive that lets workers and the main program remain
responsive.

### 3.4 The PARENT Pseudo-Handle

Inside a `WORKER` body, `PARENT` is a keyword that refers to the message channel
back to whoever spawned this worker. It is only valid inside a `WORKER` block —
using it anywhere else is a compile-time error.

`PARENT` is implemented as a hidden parameter injected by the compiler into
messaging-enabled workers (see §7).

### 3.5 Complete Syntax Summary

| Keyword | Context | Blocking? | Description |
|---------|---------|-----------|-------------|
| `SEND handle, expr` | Main or Worker | Semi¹ | Send a message to the other side |
| `RECEIVE(handle)` | Main or Worker | Yes | Block until a message arrives, return it |
| `HASMESSAGE(handle)` | Main or Worker | No | Check if a message is available |
| `PARENT` | Worker only | — | Pseudo-handle referring to the spawner |

¹ Non-blocking unless the queue is full (bounded back-pressure).

---

## 4. Message Types and Auto-Marshalling

### 4.1 Type Tagging

Each message blob carries a **type tag** so the receiver can validate and
unmarshall correctly. The tag is a small header prepended to the marshalled data:

```
┌────────────────────────────────────────┐
│ MessageBlob                            │
│                                        │
│  tag        : uint8   (type code)      │
│  flags      : uint8   (reserved)       │
│  payload_len: uint32  (byte count)     │
│  payload    : [payload_len] bytes      │
└────────────────────────────────────────┘
```

Type codes:

| Code | Tag Name | Payload |
|------|----------|---------|
| 0 | `MSG_DOUBLE` | 8 bytes (IEEE 754 double) |
| 1 | `MSG_INTEGER` | 4 bytes (int32) |
| 2 | `MSG_STRING` | Length-prefixed string data (deep copy) |
| 3 | `MSG_UDT` | Flat or deep-marshalled UDT blob |
| 4 | `MSG_ARRAY` | ArrayDescriptor + element data |
| 5 | `MSG_CLASS` | Marshalled class object blob |
| 6 | `MSG_MARSHALLED` | Pre-marshalled opaque blob (pass-through) |
| 7 | `MSG_SIGNAL` | Zero-length control signal (see §5.4) |

### 4.2 Compiler-Driven Auto-Marshalling

The compiler knows the type of every expression at the `SEND` call site and the
declared type of every `RECEIVE` target. It inserts the correct marshalling and
unmarshalling calls automatically:

```basic
' The programmer writes:
SEND f, myVec3

' The compiler emits (pseudo-code):
blob = msg_marshall_udt(&myVec3, SIZEOF(Vec3), string_offsets, num_string_fields)
msg_queue_push(future_handle.outbox, blob)
```

```basic
' The programmer writes:
DIM v AS Vec3
v = RECEIVE(f)

' The compiler emits:
blob = msg_queue_pop(future_handle.inbox)       ' blocks
msg_unmarshall_udt(blob, &v, SIZEOF(Vec3), string_offsets, num_string_fields)
msg_blob_free(blob)
```

For scalars, marshalling is trivial — the 8-byte value is stored directly in the
payload with no heap allocation for the data itself (only the header+payload
envelope).

### 4.3 Type Safety

The compiler enforces that `RECEIVE` targets have a declared type. The runtime
checks the message's type tag against the expected type and raises a runtime error
on mismatch:

```
Runtime error: RECEIVE expected MSG_DOUBLE (tag 0) but got MSG_UDT (tag 3)
```

This prevents silent data corruption while keeping the API simple. In a future
version, a `RECEIVE ANY` variant could return a tagged union for dynamic dispatch.

### 4.4 String Deep-Copy

Strings in messages are always deep-copied, just as in existing `MARSHALL`
operations. The `MSG_STRING` payload contains the string bytes inline. On
`RECEIVE`, a new `StringDescriptor` is allocated via `string_clone()` and the
receiver owns it entirely. The existing `marshall_udt_deep` / `unmarshall_udt_deep`
path handles UDTs with string fields.

---

## 5. Usage Patterns

### 5.1 Progress Reporting

```basic
WORKER Crunch(blob AS MARSHALLED) AS DOUBLE
    DIM data(1000) AS DOUBLE
    UNMARSHALL data, blob
    DIM total AS DOUBLE = 0
    DIM i AS INTEGER
    FOR i = 0 TO 999
        total = total + SQR(data(i))
        IF i MOD 100 = 0 THEN
            SEND PARENT, INT((i / 1000) * 100)   ' progress %
        END IF
    NEXT i
    RETURN total
END WORKER

DIM f AS DOUBLE
f = SPAWN Crunch(MARSHALL(bigArray))

' Poll for progress while waiting
DO WHILE NOT READY(f)
    IF HASMESSAGE(f) THEN
        DIM pct AS INTEGER
        pct = RECEIVE(f)
        PRINT "Progress: "; pct; "%"
    END IF
    SLEEP 50
LOOP

DIM result AS DOUBLE
result = AWAIT f
PRINT "Result: "; result
```

### 5.2 Streaming Results

```basic
TYPE DataPoint
    x AS DOUBLE
    y AS DOUBLE
END TYPE

WORKER GeneratePoints(n AS DOUBLE) AS DOUBLE
    DIM i AS INTEGER
    DIM pt AS DataPoint
    FOR i = 1 TO INT(n)
        pt.x = RND * 100
        pt.y = RND * 100
        SEND PARENT, pt         ' stream each point as it is generated
    NEXT i
    RETURN n                    ' final return value = count
END WORKER

DIM f AS DOUBLE
f = SPAWN GeneratePoints(50)

DIM received AS INTEGER = 0
DO WHILE NOT READY(f) OR HASMESSAGE(f)
    IF HASMESSAGE(f) THEN
        DIM p AS DataPoint
        p = RECEIVE(f)
        PRINT "Point: "; p.x; ", "; p.y
        received = received + 1
    ELSE
        SLEEP 10
    END IF
LOOP

DIM total AS DOUBLE
total = AWAIT f
PRINT "Received "; received; " of "; total; " points"
```

### 5.3 Dynamic Work Distribution (Producer–Consumer)

```basic
WORKER Consumer() AS DOUBLE
    DIM count AS DOUBLE = 0
    DO
        IF HASMESSAGE(PARENT) THEN
            DIM item AS DOUBLE
            item = RECEIVE(PARENT)
            IF item < 0 THEN EXIT DO      ' sentinel: stop
            count = count + item
        ELSE
            SLEEP 1
        END IF
    LOOP
    RETURN count
END WORKER

DIM f AS DOUBLE
f = SPAWN Consumer()

' Feed work items to the worker
DIM i AS INTEGER
FOR i = 1 TO 100
    SEND f, CDbl(i)
NEXT i
SEND f, -1.0                     ' sentinel to stop

DIM total AS DOUBLE
total = AWAIT f
PRINT "Total: "; total           ' 5050
```

### 5.4 Cooperative Cancellation

Workers cannot be forcefully killed (that would violate resource safety). Instead,
the main program sends a **signal** and the worker checks for it:

```basic
WORKER LongTask() AS DOUBLE
    DIM result AS DOUBLE = 0
    DIM i AS INTEGER
    FOR i = 1 TO 1000000
        result = result + SQR(CDbl(i))
        IF i MOD 1000 = 0 THEN
            IF HASMESSAGE(PARENT) THEN
                DIM sig AS INTEGER
                sig = RECEIVE(PARENT)
                IF sig = -1 THEN
                    RETURN result      ' early exit, clean return
                END IF
            END IF
        END IF
    NEXT i
    RETURN result
END WORKER

DIM f AS DOUBLE
f = SPAWN LongTask()
SLEEP 100                           ' let it run for a bit
SEND f, -1                          ' request cancellation
DIM partial AS DOUBLE
partial = AWAIT f
PRINT "Partial result: "; partial
```

There is also a dedicated zero-cost signal mechanism:

```basic
CANCEL f           ' sends MSG_SIGNAL with code CANCEL to the worker

' Inside worker:
IF CANCELLED(PARENT) THEN
    RETURN partial_result
END IF
```

`CANCELLED(PARENT)` is a non-blocking check that tests for the presence of a
`MSG_SIGNAL` with the cancel flag. It does not consume regular messages.

### 5.5 Multi-Worker Pipeline

```basic
WORKER Stage1(blob AS MARSHALLED) AS DOUBLE
    DIM data(100) AS DOUBLE
    UNMARSHALL data, blob
    ' Process and stream results to parent
    DIM i AS INTEGER
    FOR i = 0 TO 99
        SEND PARENT, data(i) * 2.0
    NEXT i
    SEND PARENT, -1.0    ' done sentinel
    RETURN 100
END WORKER

WORKER Stage2() AS DOUBLE
    DIM total AS DOUBLE = 0
    DO
        DIM val AS DOUBLE
        val = RECEIVE(PARENT)
        IF val < 0 THEN EXIT DO
        total = total + val
    LOOP
    RETURN total
END WORKER

' Main orchestrates the pipeline
DIM f1 AS DOUBLE
f1 = SPAWN Stage1(MARSHALL(inputArray))

DIM f2 AS DOUBLE
f2 = SPAWN Stage2()

' Route messages from Stage1 to Stage2
DO
    IF HASMESSAGE(f1) THEN
        DIM v AS DOUBLE
        v = RECEIVE(f1)
        SEND f2, v
        IF v < 0 THEN EXIT DO     ' sentinel propagated
    ELSE
        SLEEP 1
    END IF
LOOP

DIM r1 AS DOUBLE
DIM r2 AS DOUBLE
r1 = AWAIT f1
r2 = AWAIT f2
PRINT "Stage1 processed: "; r1; " items"
PRINT "Stage2 total: "; r2
```

Note: Workers still cannot communicate directly with each other. The main program
acts as the router. This preserves the single-parent ownership model and avoids
the complexity of arbitrary worker-to-worker channels.

---

## 6. Runtime Architecture

### 6.1 MessageQueue Data Structure

Each direction of communication uses a **bounded, lock-free–friendly ring buffer**
protected by a mutex and condition variable (matching the existing `FutureHandle`
pattern):

```
┌───────────────────────────────────────────────────────┐
│  MessageQueue                                         │
│                                                       │
│  slots[MSG_QUEUE_CAPACITY]  : *MessageBlob            │
│  head                       : uint32  (read index)    │
│  tail                       : uint32  (write index)   │
│  count                      : uint32  (current size)  │
│  mutex                      : pthread_mutex_t         │
│  not_empty_cv               : pthread_cond_t          │
│  not_full_cv                : pthread_cond_t          │
│  closed                     : bool                    │
│  cancel_flag                : atomic bool             │
└───────────────────────────────────────────────────────┘
```

Default capacity: **256 messages**. This is large enough for most streaming and
progress-reporting patterns, small enough to bound memory usage. The capacity is
a compile-time constant but could be made configurable per-worker in a future
extension.

### 6.2 Back-Pressure

When the queue is full:

- `SEND` blocks on `not_full_cv` until the receiver consumes a message.
- This provides natural flow control: a fast producer is throttled to match a
  slow consumer.
- A 100ms timeout on the condvar wait prevents deadlocks if the other side has
  exited. After timeout, `SEND` checks whether the worker/main is still alive
  and either retries or returns an error.

When the queue is empty:

- `RECEIVE` blocks on `not_empty_cv` until a message arrives.
- `HASMESSAGE` returns immediately with `0`.

### 6.3 Queue Lifecycle

```
SPAWN
  │
  ├─ Allocate FutureHandle (existing)
  ├─ Allocate outbox MessageQueue  (main → worker)
  ├─ Allocate inbox  MessageQueue  (worker → main)
  ├─ Pass &outbox, &inbox to worker thread via args
  │
  ├─ Worker runs...
  │   ├─ SEND PARENT, msg    → push to inbox
  │   ├─ RECEIVE(PARENT)     → pop from outbox
  │   └─ RETURN result       → (existing path)
  │
  ├─ Main thread...
  │   ├─ SEND f, msg          → push to outbox
  │   ├─ RECEIVE(f)           → pop from inbox
  │   └─ HASMESSAGE(f)        → peek inbox count
  │
  AWAIT
  │
  ├─ Close outbox (signal worker: no more messages incoming)
  ├─ Join thread (existing)
  ├─ Drain inbox  (free any unconsumed messages)
  ├─ Drain outbox (free any unconsumed messages)
  ├─ Free both queues
  └─ Free FutureHandle (existing)
```

### 6.4 Extended FutureHandle

```c
typedef struct {
    /* ── Existing fields ────────────────────────── */
    pthread_t       thread;
    pthread_mutex_t mutex;
    pthread_cond_t  cond;
    int             done;
    double          result;
    int32_t         ret_type;
    void           *func_ptr;
    WorkerArgs     *args;
    int32_t         num_args;

    /* ── New: messaging ─────────────────────────── */
    MessageQueue   *outbox;     /* main → worker */
    MessageQueue   *inbox;      /* worker → main */
} FutureHandle;
```

For workers that never use `SEND`/`RECEIVE`/`HASMESSAGE`, the queues are **not
allocated**. The compiler knows at compile time whether a worker uses messaging
(by scanning the worker body for `PARENT` references) and only emits the queue
allocation calls for messaging workers. Non-messaging workers remain exactly as
efficient as today.

### 6.5 PARENT Handle Resolution

The compiler injects a hidden parameter for messaging-enabled workers:

```
' The programmer writes:
WORKER Foo(x AS DOUBLE) AS DOUBLE
    SEND PARENT, x * 2
    RETURN x
END WORKER

' The compiler emits (conceptual QBE):
function $worker_Foo(d %x, l %parent_handle) {
    ...
    call $msg_send(l %parent_handle, ...)
    ...
}
```

The `%parent_handle` is a pointer to the `FutureHandle`. Inside the worker,
`SEND PARENT` and `RECEIVE(PARENT)` are compiled as calls to `msg_send` and
`msg_receive` with the inbox/outbox pointers extracted from the handle.

The direction is **swapped** inside the worker:
- Worker's `SEND PARENT` → pushes to `handle->inbox` (worker→main)
- Worker's `RECEIVE(PARENT)` → pops from `handle->outbox` (main→worker)

This swap is resolved at compile time, so there is no runtime cost.

---

## 7. Compiler Changes

### 7.1 Lexer

New tokens:

| Token | Keyword |
|-------|---------|
| `TOK_SEND` | `SEND` |
| `TOK_RECEIVE` | `RECEIVE` |
| `TOK_HASMESSAGE` | `HASMESSAGE` |
| `TOK_PARENT` | `PARENT` |
| `TOK_CANCEL` | `CANCEL` |
| `TOK_CANCELLED` | `CANCELLED` |

### 7.2 Parser / AST

New AST node types:

```zig
/// SEND handle, expression
const SendStmt = struct {
    handle: *Expression,    // future handle or PARENT
    message: *Expression,   // value to send
};

/// RECEIVE(handle) — used as an expression
const ReceiveExpr = struct {
    handle: *Expression,    // future handle or PARENT
    target_type: ?TypeDescriptor,  // resolved by semantic analysis
};

/// HASMESSAGE(handle) — boolean expression
const HasMessageExpr = struct {
    handle: *Expression,    // future handle or PARENT
};

/// CANCEL handle — statement
const CancelStmt = struct {
    handle: *Expression,    // future handle
};

/// CANCELLED(PARENT) — boolean expression (worker only)
const CancelledExpr = struct {};
```

### 7.3 Semantic Analyser

New validation rules:

1. **`PARENT` only in workers** — If `PARENT` appears outside a `WORKER` block,
   emit error: `"PARENT can only be used inside a WORKER block"`.

2. **`SEND`/`RECEIVE` type checking** — The semantic analyser resolves the
   message expression type for `SEND` and ensures the `RECEIVE` target has a
   declared type. It records these types in the AST for codegen.

3. **Worker messaging flag** — When the analyser encounters `PARENT`, `SEND`,
   `RECEIVE`, `HASMESSAGE`, or `CANCELLED` inside a worker body, it sets
   `FunctionSymbol.uses_messaging = true`. This flag tells codegen to allocate
   message queues and inject the hidden parameter.

4. **No RECEIVE in non-messaging contexts** — `RECEIVE(f)` in the main program
   is only valid if `f` was returned by `SPAWN` of a messaging-enabled worker.
   This is checked at compile time via the `uses_messaging` flag on the worker's
   `FunctionSymbol`.

5. **SEND to non-messaging worker** — `SEND f, expr` where `f` is a handle to a
   non-messaging worker is a compile-time error: `"Worker 'Foo' does not use
   messaging. Cannot SEND to it."` This prevents messages from being silently
   lost in a queue that nobody reads.

6. **CANCEL only on future handles** — `CANCEL` is valid only when applied to a
   variable that holds a future handle.

### 7.4 Code Generation (QBE)

For a messaging-enabled worker, codegen emits:

**At SPAWN site:**

```
; Allocate message queues
%outbox =l call $msg_queue_create()
%inbox  =l call $msg_queue_create()

; Store in future handle
storel %outbox, %future_handle + OFFSET_OUTBOX
storel %inbox,  %future_handle + OFFSET_INBOX

; Pass handle pointer as hidden last argument
call $worker_args_set_ptr(%args, %hidden_index, %future_handle)
```

**SEND (main → worker):**

```
; Marshall the expression
%blob =l call $msg_marshall_<type>(%expr_ptr, %expr_size, ...)

; Push to outbox (main → worker direction)
%outbox =l loadl %future_handle + OFFSET_OUTBOX
call $msg_queue_push(%outbox, %blob)
```

**RECEIVE (main ← worker):**

```
; Pop from inbox (worker → main direction)
%inbox =l loadl %future_handle + OFFSET_INBOX
%blob  =l call $msg_queue_pop(%inbox)

; Unmarshall into target variable
call $msg_unmarshall_<type>(%blob, %target_ptr, %target_size, ...)
call $msg_blob_free(%blob)
```

**Inside worker — SEND PARENT:**

```
; %parent_handle is the hidden parameter
%inbox =l loadl %parent_handle + OFFSET_INBOX   ; worker writes to "inbox" = worker→main
%blob  =l call $msg_marshall_<type>(...)
call $msg_queue_push(%inbox, %blob)
```

**Inside worker — RECEIVE(PARENT):**

```
%outbox =l loadl %parent_handle + OFFSET_OUTBOX  ; worker reads from "outbox" = main→worker
%blob   =l call $msg_queue_pop(%outbox)
call $msg_unmarshall_<type>(...)
call $msg_blob_free(%blob)
```

---

## 8. Runtime API

### 8.1 C-Linkage Functions

These are the runtime functions called by generated code. All maintain C ABI
compatibility for the QBE backend.

```c
/* ── Queue management ──────────────────────────────────────────── */

/* Create a new message queue with default capacity (256 slots). */
MessageQueue *msg_queue_create(void);

/* Destroy a queue, freeing all unconsumed messages. */
void msg_queue_destroy(MessageQueue *q);

/* Push a message blob onto the queue. Blocks if full. */
void msg_queue_push(MessageQueue *q, MessageBlob *blob);

/* Pop a message from the queue. Blocks if empty. */
MessageBlob *msg_queue_pop(MessageQueue *q);

/* Non-blocking check: returns 1 if at least one message is queued. */
int32_t msg_queue_has_message(MessageQueue *q);

/* Close the queue (no more pushes allowed; pops drain remaining). */
void msg_queue_close(MessageQueue *q);

/* ── Message blob construction ─────────────────────────────────── */

/* Marshall a double into a message blob. */
MessageBlob *msg_marshall_double(double value);

/* Marshall an int32 into a message blob. */
MessageBlob *msg_marshall_int(int32_t value);

/* Marshall a string (deep copy) into a message blob. */
MessageBlob *msg_marshall_string(void *str_desc);

/* Marshall a UDT (flat or deep) into a message blob. */
MessageBlob *msg_marshall_udt(void *udt_ptr, int32_t size,
                              int32_t *string_offsets, int32_t num_offsets);

/* Marshall an array into a message blob. */
MessageBlob *msg_marshall_array(void *array_desc);

/* Marshall a pre-marshalled blob (wraps it in a message envelope). */
MessageBlob *msg_marshall_blob(void *blob_ptr, int32_t size);

/* Create a zero-length signal message. */
MessageBlob *msg_marshall_signal(int32_t signal_code);

/* ── Message blob extraction ───────────────────────────────────── */

/* Unmarshall a double from a message blob. */
double msg_unmarshall_double(MessageBlob *blob);

/* Unmarshall an int32 from a message blob. */
int32_t msg_unmarshall_int(MessageBlob *blob);

/* Unmarshall a string from a message blob (allocates new descriptor). */
void *msg_unmarshall_string(MessageBlob *blob);

/* Unmarshall a UDT from a message blob into target memory. */
void msg_unmarshall_udt(MessageBlob *blob, void *target, int32_t size,
                        int32_t *string_offsets, int32_t num_offsets);

/* Unmarshall an array from a message blob into a descriptor. */
void msg_unmarshall_array(MessageBlob *blob, void *array_desc);

/* Free a message blob and its payload. */
void msg_blob_free(MessageBlob *blob);

/* ── Cancellation ──────────────────────────────────────────────── */

/* Send a cancellation signal to a worker. */
void msg_cancel(FutureHandle *handle);

/* Check if cancellation was requested (non-blocking, no queue). */
int32_t msg_is_cancelled(FutureHandle *handle);
```

### 8.2 Zig Runtime Implementation Location

The messaging runtime will be implemented in a new file:

```
zig_compiler/runtime/messaging.zig
```

This follows the pattern established by `marshalling.zig` and `samm_core.zig`.
All functions export with `callconv(.c)` for C ABI compatibility.

The `MessageQueue` struct and `MessageBlob` struct will be defined in Zig with
`extern struct` layout so they can also be referenced from the C side
(`worker_runtime.c`) if needed during transition.

### 8.3 Integration with Existing Marshalling

The `msg_marshall_udt` and `msg_marshall_array` functions internally call the
existing `marshall_udt_deep` and `marshall_array` functions from `marshalling.zig`,
then wrap the result in a `MessageBlob` envelope. This avoids code duplication and
ensures marshalling semantics remain consistent.

```
msg_marshall_udt(ptr, size, offsets, n)
  │
  ├─ blob.payload = marshall_udt_deep(ptr, size, offsets, n)   // existing
  ├─ blob.tag     = MSG_UDT
  ├─ blob.payload_len = size
  └─ return blob
```

---

## 9. Memory Safety

### 9.1 Ownership Model

Every message blob has exactly **one owner** at any given time:

1. The sender creates and owns the blob until `msg_queue_push` transfers
   ownership to the queue.
2. The queue owns the blob until `msg_queue_pop` transfers ownership to the
   receiver.
3. The receiver owns the blob until `msg_unmarshall_*` + `msg_blob_free`
   releases it.

There is no sharing, no reference counting, and no possibility of use-after-free
(assuming correct codegen, which the compiler guarantees).

### 9.2 Queue Draining on AWAIT

When `worker_await` is called:

1. The worker thread is joined (existing behaviour).
2. **The outbox is closed** — no more messages can be pushed from main to worker
   (the worker is already done anyway).
3. **The inbox is drained** — any unconsumed worker→main messages are freed.
4. **The outbox is drained** — any unconsumed main→worker messages are freed.
5. Both queues are destroyed.
6. The `FutureHandle` is freed (existing behaviour).

This ensures no memory is leaked regardless of how many messages were sent or
received.

### 9.3 SAMM Integration

Message queue allocations are **not** tracked by SAMM. They are managed
exclusively by the messaging runtime via explicit `malloc`/`free` paired with
the queue lifecycle (create at SPAWN, destroy at AWAIT). This is the same pattern
used by `FutureHandle` itself and avoids complexity from SAMM's scope-based
cleanup attempting to free messaging structures.

Message blobs that contain SAMM-tracked objects (e.g., CLASS instances) are
marshalled as deep copies — the original remains tracked by SAMM in its scope,
and the copy in the blob is an independent allocation freed by the messaging
runtime. There is no cross-contamination between SAMM scopes and message queues.

### 9.4 Thread Safety Guarantees

| Operation | Thread Safety Mechanism |
|-----------|------------------------|
| `msg_queue_push` | Mutex-protected, condvar signal |
| `msg_queue_pop` | Mutex-protected, condvar wait |
| `msg_queue_has_message` | Mutex-protected read of count |
| `msg_is_cancelled` | Atomic bool read (no mutex needed) |
| Message blob create/free | Per-blob, single-owner, no sharing |

---

## 10. Interaction with Existing Worker Features

### 10.1 SPAWN / AWAIT — Unchanged

`SPAWN` and `AWAIT` continue to work exactly as before. Messaging is **additive**
— a worker that does not use `PARENT`, `SEND`, `RECEIVE`, or `HASMESSAGE` has
zero overhead from the messaging system. No queues are allocated, no hidden
parameter is injected.

### 10.2 READY — Enhanced

`READY(f)` continues to check if the worker thread has completed. Its semantics
do not change. It does **not** check for messages — that's what `HASMESSAGE` is
for. The two are orthogonal:

| `READY(f)` | `HASMESSAGE(f)` | Meaning |
|-------------|------------------|---------|
| 0 | 0 | Worker running, no messages yet |
| 0 | 1 | Worker running, has sent messages |
| 1 | 0 | Worker finished, no unread messages |
| 1 | 1 | Worker finished, unread messages remain |

The typical polling loop checks both:

```basic
DO WHILE NOT READY(f)
    DO WHILE HASMESSAGE(f)
        msg = RECEIVE(f)
        ' process msg
    LOOP
    SLEEP 10
LOOP
' After READY, drain remaining messages before AWAIT
DO WHILE HASMESSAGE(f)
    msg = RECEIVE(f)
LOOP
result = AWAIT f
```

### 10.3 MARSHALL / UNMARSHALL — Coexist

Explicit `MARSHALL()` / `UNMARSHALL` remain available for worker arguments and
return values. `SEND` auto-marshalls, so explicit `MARSHALL` is not required for
messages but is accepted:

```basic
' Both are valid:
SEND f, myUDT                      ' auto-marshalled
SEND f, MARSHALL(myUDT)            ' explicit — wrapped in MSG_MARSHALLED envelope
```

### 10.4 Worker Restrictions — Preserved

All existing restrictions on workers are preserved:

- No I/O (`PRINT`, `INPUT`, file operations)
- No global/shared variable access
- No graphics, audio, sprites, timers
- No nested `SPAWN`
- No nested `WORKER` definitions

`SEND` and `RECEIVE` are the **only** new capabilities granted to workers. They
do not open any door to shared state — messages are always deep copies.

---

## 11. Error Handling

### 11.1 Compile-Time Errors

| Error | Condition |
|-------|-----------|
| `PARENT used outside WORKER block` | `PARENT` keyword in main program or SUB/FUNCTION |
| `Cannot SEND to non-messaging worker 'X'` | `SEND f, ...` where `X` does not use `PARENT` |
| `RECEIVE requires a typed target` | `RECEIVE(f)` without assignment to a typed variable |
| `CANCELLED only valid inside WORKER` | `CANCELLED(PARENT)` outside a worker body |
| `CANCEL requires a future handle` | `CANCEL x` where `x` is not a future handle |

### 11.2 Runtime Errors

| Error | Condition | Behaviour |
|-------|-----------|-----------|
| `RECEIVE type mismatch` | Message tag ≠ expected type | Print error, abort program |
| `SEND to closed queue` | Worker already finished, main sends | Message silently discarded + warning to stderr |
| `RECEIVE on destroyed queue` | AWAIT already called, then RECEIVE | Null handle check, return zero/empty |
| `Queue allocation failure` | Out of memory | Print error, abort (same as existing malloc failure handling) |

### 11.3 Deadlock Prevention

The bounded queue with back-pressure creates a potential deadlock if both sides
are blocked in `RECEIVE` simultaneously (each waiting for the other to `SEND`).
The runtime mitigates this with:

1. **Timeout on RECEIVE** — After 5 seconds of blocking, `RECEIVE` checks if the
   other side is still alive. If the worker has exited (the `done` flag is set),
   `RECEIVE` returns a default zero-value and prints a warning. If the main thread
   has moved past `AWAIT`, the worker's `RECEIVE(PARENT)` unblocks with a
   zero-value.

2. **Compile-time lint (future)** — A static analysis pass could detect workers
   that call `RECEIVE(PARENT)` without a preceding `HASMESSAGE(PARENT)` check
   and warn about potential blocking.

3. **Documentation** — Best practices (§12) strongly recommend `HASMESSAGE`
   polling loops over bare `RECEIVE` for responsive programs.

---

## 12. Best Practices

### 12.1 Prefer Non-Blocking Patterns

```basic
' GOOD: Non-blocking receive loop
DO WHILE NOT READY(f)
    IF HASMESSAGE(f) THEN
        DIM msg AS DOUBLE
        msg = RECEIVE(f)
        ' process
    END IF
    SLEEP 10    ' don't spin-loop
LOOP
```

```basic
' RISKY: Blocking receive without timeout
DIM msg AS DOUBLE
msg = RECEIVE(f)    ' if worker never sends, this hangs
```

### 12.2 Use Sentinels for Termination

```basic
' GOOD: Clear end-of-stream signal
SEND f, -1.0        ' sentinel value
' or:
CANCEL f             ' explicit cancellation
```

### 12.3 Drain Messages Before AWAIT

```basic
' GOOD: Don't lose messages
DO WHILE HASMESSAGE(f)
    process(RECEIVE(f))
LOOP
result = AWAIT f
```

```basic
' BAD: Messages may be silently freed by AWAIT
result = AWAIT f     ' any unsent messages are lost
```

### 12.4 Keep Messages Small

Marshalling copies data. Sending a 100MB array as a message on every iteration
will be slow. Instead, send lightweight progress indicators or small result
chunks.

### 12.5 One Consumer Per Queue

Each future handle's message queues are designed for exactly one producer and one
consumer (the main thread and the worker). Do not pass a future handle to another
worker and have it call `RECEIVE` — this is not supported and violates the
ownership model. (The compiler enforces this: `RECEIVE(f)` in a worker body is
a compile-time error unless `f` is `PARENT`.)

---

## 13. Implementation Plan

### Phase 1: Core Messaging Runtime

**Files:** `zig_compiler/runtime/messaging.zig`

- `MessageBlob` struct with type tag and payload
- `MessageQueue` struct with ring buffer, mutex, condvars
- `msg_queue_create`, `msg_queue_destroy`, `msg_queue_push`, `msg_queue_pop`
- `msg_queue_has_message`, `msg_queue_close`
- `msg_marshall_double`, `msg_marshall_int`, `msg_unmarshall_double`, `msg_unmarshall_int`
- `msg_blob_free`
- Unit tests for queue operations (push/pop, blocking, full/empty, close)

### Phase 2: Extended FutureHandle

**Files:** `zig_compiler/runtime/worker_runtime.c`

- Add `outbox`/`inbox` fields to `FutureHandle`
- Modify `worker_spawn` to optionally allocate queues
- Modify `worker_await` to drain and destroy queues
- Add `msg_cancel` and `msg_is_cancelled`
- Pass handle pointer as hidden argument for messaging workers

### Phase 3: Complex Type Marshalling for Messages

**Files:** `zig_compiler/runtime/messaging.zig`

- `msg_marshall_string`, `msg_unmarshall_string`
- `msg_marshall_udt`, `msg_unmarshall_udt` (wrapping existing `marshall_udt_deep`)
- `msg_marshall_array`, `msg_unmarshall_array` (wrapping existing `marshall_array`)
- `msg_marshall_blob` (for pre-marshalled data)

### Phase 4: Compiler Support

**Files:** `zig_compiler/src/lexer.zig`, `parser.zig`, `ast.zig`, `semantic.zig`, `codegen.zig`, `cfg.zig`

- Lexer: Add `SEND`, `RECEIVE`, `HASMESSAGE`, `PARENT`, `CANCEL`, `CANCELLED` tokens
- Parser: Parse `SEND` statement, `RECEIVE()` expression, `HASMESSAGE()` expression
- AST: Add `SendStmt`, `ReceiveExpr`, `HasMessageExpr`, `CancelStmt`, `CancelledExpr` nodes
- Semantic: Validate `PARENT` only in workers, type-check messages, set `uses_messaging` flag
- Codegen: Emit queue allocation at SPAWN, auto-marshal at SEND, auto-unmarshal at RECEIVE
- CFG: Process messaging statements in worker bodies

### Phase 5: Tests

**Files:** `tests/workers/`

- `test_worker_send_receive.bas` — basic SEND/RECEIVE between main and worker
- `test_worker_progress.bas` — progress reporting pattern
- `test_worker_streaming.bas` — streaming results pattern
- `test_worker_cancel.bas` — cancellation pattern
- `test_worker_producer_consumer.bas` — dynamic work distribution
- `test_worker_msg_udt.bas` — sending UDTs as messages
- `test_worker_msg_string.bas` — sending strings as messages
- `test_worker_msg_array.bas` — sending arrays as messages
- `test_worker_no_msg_overhead.bas` — verify non-messaging workers have no overhead
- `test_worker_msg_drain.bas` — verify AWAIT drains unconsumed messages

### Phase 6: Documentation

- Update `articles/workers.md` with messaging section
- Add messaging examples to test suite
- Update worker limitations list (remove "No message passing")

---

## 14. MATCH RECEIVE — Typed Message Dispatch

### 14.1 Overview

`MATCH RECEIVE` pops a message from a worker's queue and dispatches on
its type tag, binding the unmarshalled value to a variable in the
matched arm.  It supports scalar types (DOUBLE, INTEGER, STRING) as well
as **specific UDT type names** and **specific CLASS names**.

### 14.2 Syntax

```basic
MATCH RECEIVE(handle)
    CASE DOUBLE x
        ' x is a DOUBLE variable
        PRINT "Got double: "; x
    CASE INTEGER n%
        ' n% is an INTEGER variable
        PRINT "Got integer: "; n%
    CASE STRING s$
        ' s$ is a STRING variable
        PRINT "Got string: "; s$
    CASE Point pt
        ' pt is bound to the unmarshalled Point UDT
        PRINT "Got Point: "; pt.x; " "; pt.y
    CASE Dog d
        ' d is bound to the unmarshalled Dog CLASS instance
        PRINT "Got Dog: "; d.Name()
    CASE ELSE
        PRINT "Unknown message type"
END MATCH
```

`handle` is either a future handle variable (in the main program) or
`PARENT` (inside a worker).  Direction is resolved at compile time:

| Context | Queue read |
|---------|------------|
| Main program, `MATCH RECEIVE(f)` | inbox (worker → main) |
| Worker body, `MATCH RECEIVE(PARENT)` | outbox (main → worker) |

### 14.3 MessageBlob `type_id` Extension

To distinguish specific UDT types and CLASS instances that share the
same tag (`MSG_UDT = 3` or `MSG_CLASS = 5`), the `MessageBlob` struct
now carries a `type_id` field in place of the former `_pad` bytes:

```c
typedef struct MessageBlob {
    uint8_t   tag;          // MSG_DOUBLE, MSG_INTEGER, …
    uint8_t   flags;        // reserved
    int16_t   type_id;      // UDT type_id or CLASS class_id (0 = untyped)
    uint32_t  payload_len;
    void     *payload;
    uint64_t  inline_value; // scalar storage
} MessageBlob;
```

The `type_id` is stamped at send time:

- **SEND of a UDT variable**: codegen calls `msg_send_udt_typed(…, type_id)`
  where `type_id` comes from `SymbolTable.getTypeId(type_name)`.
- **SEND of a CLASS variable**: codegen calls `msg_send_class(…, class_id)`
  where `class_id` comes from `ClassSymbol.class_id`.
- **SEND of a scalar**: `type_id` is 0 (irrelevant, tag alone suffices).

At receive time, `MATCH RECEIVE` performs:

1. `msg_queue_pop(queue)` → raw `MessageBlob*`
2. `msg_blob_tag(blob)` → tag (u8 widened to i32)
3. `msg_blob_type_id(blob)` → type_id (i16 widened to i32)
4. For each CASE arm, compare tag (and type_id for UDT/CLASS arms)
5. On match, unmarshall the value into the binding variable
6. On no match, fall through to CASE ELSE (or discard)

### 14.4 Typed SEND (Phase 2)

The SEND statement now emits typed sends based on the expression's
semantic type, replacing the phase-1 "always send as double" behaviour:

| Expression type | Runtime call | Tag |
|----------------|-------------|-----|
| DOUBLE | `msg_send_double` | `MSG_DOUBLE (0)` |
| INTEGER | `msg_send_int` | `MSG_INTEGER (1)` |
| STRING | `msg_send_string` | `MSG_STRING (2)` |
| UDT (e.g. `Point`) | `msg_send_udt_typed(…, type_id)` | `MSG_UDT (3)` |
| CLASS (e.g. `Dog`) | `msg_send_class(…, class_id)` | `MSG_CLASS (5)` |

The type is resolved via `resolveSendType()` in the codegen, which
checks function-local variables, global variables, and expression types
in the symbol table.

### 14.5 Codegen Architecture

The CFG for `MATCH RECEIVE` reuses the existing `case_entry` /
`case_test` / `case_body` / `case_exit` block pattern (identical to
`MATCH TYPE` and `SELECT CASE`).

Three codegen functions implement the feature:

1. **`emitMatchReceiveInit`** — emitted in the entry block:
   - Resolves the queue (inbox or outbox depending on direction)
   - Calls `msg_queue_pop` (blocking) to get the blob
   - Calls `msg_blob_tag` and `msg_blob_type_id` to read metadata
   - Stores the context (`MatchReceiveContext`) for case_test blocks

2. **`findMatchReceiveContext`** — walks CFG predecessors to find the
   entry block's context (same pattern as `findMatchTypeContext`).

3. **`emitMatchReceiveTest`** — emitted per case_test block:
   - For scalar arms: pre-loads the binding variable from
     `inline_value` (offset 16 in blob), then branches on `tag == expected`.
   - For UDT/CLASS arms: branches on `tag == expected` AND
     `type_id == expected_type_id`, then emits a **trampoline block**
     (`@mr_extract_N`) that:
     - Allocates UDT memory via `basic_malloc` if the binding variable
       slot is null (no prior `DIM`)
     - Reads the payload pointer from the blob (offset 8)
     - Calls `unmarshall_udt` / `unmarshall_udt_deep` to copy data
     - Jumps to the body block

### 14.6 New Runtime Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `msg_marshall_udt_typed` | `MessageBlob* (void*, i32, i32*, i32, i32)` | Marshall UDT with type_id |
| `msg_marshall_class` | `MessageBlob* (void*, i32, i32*, i32, i32)` | Marshall CLASS with class_id |
| `msg_send_udt_typed` | `i32 (MessageQueue*, void*, i32, i32*, i32, i32)` | Send UDT with type_id |
| `msg_send_class` | `i32 (MessageQueue*, void*, i32, i32*, i32, i32)` | Send CLASS with class_id |
| `msg_blob_tag` | `i32 (MessageBlob*)` | Read tag (non-destructive) |
| `msg_blob_type_id` | `i32 (MessageBlob*)` | Read type_id (non-destructive) |

### 14.7 Semantic & Parser Notes

- The parser dispatches from `parseMatchTypeStatement` when it sees
  `MATCH RECEIVE` (the `RECEIVE` keyword after `MATCH`).
- CASE arms with identifiers (e.g. `CASE Point pt`) set both
  `is_udt_match` and `is_class_match` to `true`; the codegen resolves
  which one it is via `lookupClass` vs `lookupType` in the symbol table.
- Binding variables are auto-registered in the semantic pass
  (`collectDeclaration`) with the correct `TypeDescriptor` (UDT or
  CLASS), so downstream type inference works correctly.

---

## 15. Future Extensions

### 15.1 SELECT RECEIVE (Multi-Handle Polling)

A future version could support waiting on multiple handles:

```basic
SELECT RECEIVE
    CASE f1
        DIM v AS DOUBLE
        v = RECEIVE(f1)
    CASE f2
        DIM s AS STRING
        s = RECEIVE(f2)
    CASE TIMEOUT 1000
        PRINT "No messages for 1 second"
END SELECT
```

This would require a `poll`-like mechanism internally but could provide a very
clean API for managing multiple workers.

### 15.2 Typed Channels

Instead of auto-typed messages, allow declaring the message type at the worker
level:

```basic
WORKER Foo(x AS DOUBLE) AS DOUBLE MESSAGES DOUBLE
    ' This worker only sends/receives DOUBLEs
    SEND PARENT, x * 2
    RETURN x
END WORKER
```

This would enable full compile-time type checking of `RECEIVE` without needing
runtime tag checks.

### 15.3 Worker Groups

A higher-level abstraction for managing pools of identical workers:

```basic
DIM pool AS WORKERGROUP(4)    ' 4 workers
FOR i = 1 TO 100
    SEND pool, task(i)         ' auto-distributes to next available worker
NEXT i
DIM results AS DOUBLE
results = AWAITALL(pool)
```

### 15.4 Broadcast

```basic
SENDALL handles(), message    ' send same message to all workers in array
```

---

## 16. Appendix: Full API Reference

### 16.1 BASIC Language Additions

| Keyword | Syntax | Description |
|---------|--------|-------------|
| `SEND` | `SEND handle, expression` | Send a typed, marshalled message |
| `RECEIVE` | `var = RECEIVE(handle)` | Receive and unmarshall a message (blocking) |
| `HASMESSAGE` | `HASMESSAGE(handle)` | Non-blocking message availability check |
| `PARENT` | `SEND PARENT, expr` / `RECEIVE(PARENT)` | Worker's handle to its spawner |
| `CANCEL` | `CANCEL handle` | Send cancellation signal to worker |
| `CANCELLED` | `CANCELLED(PARENT)` | Check if cancellation was requested |
| `MATCH RECEIVE` | `MATCH RECEIVE(handle) … END MATCH` | Pop message and dispatch on type |

### 16.2 Runtime C-Linkage Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `msg_queue_create` | `MessageQueue* msg_queue_create(void)` | Create a bounded message queue |
| `msg_queue_destroy` | `void msg_queue_destroy(MessageQueue*)` | Destroy queue, free all blobs |
| `msg_queue_push` | `void msg_queue_push(MessageQueue*, MessageBlob*)` | Enqueue (blocks if full) |
| `msg_queue_pop` | `MessageBlob* msg_queue_pop(MessageQueue*)` | Dequeue (blocks if empty) |
| `msg_queue_has_message` | `int32_t msg_queue_has_message(MessageQueue*)` | Peek (non-blocking) |
| `msg_queue_close` | `void msg_queue_close(MessageQueue*)` | Mark queue as closed |
| `msg_marshall_double` | `MessageBlob* msg_marshall_double(double)` | Wrap double in blob |
| `msg_marshall_int` | `MessageBlob* msg_marshall_int(int32_t)` | Wrap int in blob |
| `msg_marshall_string` | `MessageBlob* msg_marshall_string(void*)` | Deep-copy string into blob |
| `msg_marshall_udt` | `MessageBlob* msg_marshall_udt(void*, int32_t, int32_t*, int32_t)` | Marshall UDT into blob |
| `msg_marshall_array` | `MessageBlob* msg_marshall_array(void*)` | Marshall array into blob |
| `msg_marshall_blob` | `MessageBlob* msg_marshall_blob(void*, int32_t)` | Wrap pre-marshalled data |
| `msg_marshall_signal` | `MessageBlob* msg_marshall_signal(int32_t)` | Create signal blob |
| `msg_unmarshall_double` | `double msg_unmarshall_double(MessageBlob*)` | Extract double |
| `msg_unmarshall_int` | `int32_t msg_unmarshall_int(MessageBlob*)` | Extract int |
| `msg_unmarshall_string` | `void* msg_unmarshall_string(MessageBlob*)` | Extract string (new alloc) |
| `msg_unmarshall_udt` | `void msg_unmarshall_udt(MessageBlob*, void*, int32_t, int32_t*, int32_t)` | Extract UDT |
| `msg_unmarshall_array` | `void msg_unmarshall_array(MessageBlob*, void*)` | Extract array |
| `msg_blob_free` | `void msg_blob_free(MessageBlob*)` | Free blob + payload |
| `msg_cancel` | `void msg_cancel(FutureHandle*)` | Set cancel flag |
| `msg_is_cancelled` | `int32_t msg_is_cancelled(FutureHandle*)` | Read cancel flag (atomic) |
| `msg_marshall_udt_typed` | `MessageBlob* msg_marshall_udt_typed(void*, int32_t, int32_t*, int32_t, int32_t)` | Marshall UDT with type_id |
| `msg_marshall_class` | `MessageBlob* msg_marshall_class(void*, int32_t, int32_t*, int32_t, int32_t)` | Marshall CLASS with class_id |
| `msg_send_udt_typed` | `int32_t msg_send_udt_typed(MessageQueue*, void*, int32_t, int32_t*, int32_t, int32_t)` | Send UDT with type_id |
| `msg_send_class` | `int32_t msg_send_class(MessageQueue*, void*, int32_t, int32_t*, int32_t, int32_t)` | Send CLASS with class_id |
| `msg_blob_tag` | `int32_t msg_blob_tag(MessageBlob*)` | Read tag (non-destructive) |
| `msg_blob_type_id` | `int32_t msg_blob_type_id(MessageBlob*)` | Read type_id (non-destructive) |