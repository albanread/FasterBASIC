# Timer and Multi-Threading Support for Compiled FasterBASIC Programs

## 1. Purpose

This document describes how to extend the FasterBASIC toolchain so that BASIC programs compiled to native executables (via the `fbc_qbe` compiler and QBE backend) can schedule and service `AFTER`/`EVERY` timer constructs at run time. The design assumes a multi-threaded execution model where timer callbacks run in parallel with the main BASIC thread, and further, that BASIC programs themselves may start new threads to exploit multi-core CPUs. This requires careful consideration of thread safety, locking, and coordination for all shared runtime state and APIs.

## 2. Background

### 2.1 Existing Interpreter/Runtime Behavior

- The C++ runtime in `FasterBASICT/runtime` exposes a `TimerManager` that manages millisecond- and frame-based timers.
- Timers enqueue events into an `EventQueue`, which was originally consumed by the interpreter’s Lua-facing event loop.
- Each timer is identified by both a numeric ID and a BASIC subroutine **name** string.
- The interpreter is fundamentally single-threaded, with concurrency only via timer events.

### 2.2 Compiled Executable Behavior Today

- The standalone compiler (`fbc_qbe`) generates QBE IL and links it with the **C runtime** under `runtime_c/`.
- The final binary has no access to the C++ runtime components (`TimerManager`, `EventQueue`, etc.).
- As a result, compiled programs cannot run timer-based BASIC statements even if the frontend parses them.
- There is currently no support for user-created threads in BASIC, so all code runs on the main thread.

## 3. Goals

1. Allow compiled executables to schedule one-shot (`AFTER`) and repeating (`EVERY`) timers, both time- and frame-based.
2. Expose a C ABI that generated machine code can call without needing C++ knowledge.
3. Keep the runtime lightweight: no interpreter dependencies, deterministic cleanup, and minimal impact on binaries that do not use timers.
4. Preserve future flexibility for integrating timers with user event loops or game engines.
5. Enable BASIC programs to create and manage their own threads, allowing true parallelism and full exploitation of modern multi-core CPUs (typically 6–14 cores on supported systems).
6. Ensure all runtime APIs and shared state are robustly thread-safe to support both timer and user-created threads.

## 4. Non-Goals

- Supporting scripting runtimes (Lua, etc.) inside the compiled executable.
- Reintroducing string-based handler lookup at run time.
- Providing a GUI event loop or scheduler beyond timers.

## 5. Design Overview

```
+-------------+       +------------------+       +----------------+        +------------------+
| BASIC Code  |  ---> | Frontend/CodeGen |  ---> | QBE / clang    |  --->  | Native Executable |
| (AFTER/EVERY|       | emits timer API  |       | builds objects |        | linked runtime    |
+-------------+       | calls & thunks   |       +----------------+        +------------------+
                           |                                                   |
                           | uses                                              | includes
                           v                                                   v
                    +------------------+                              +----------------------+
                    | Timer C Wrapper  | <--- C ABI ---- BASIC code   | TimerManager + mini  |
                    | (new file)       |                              | event infrastructure |
                    +------------------+                              +----------------------+
```

Key ideas:

1. **Unified runtime**: ship the timer system inside the compiled executable by linking an additional static library that wraps `TimerManager`.
2. **Callback-based firing**: map BASIC subroutine addresses to native callbacks rather than string names.
3. **Threaded firing**: reuse the existing background thread approach, but have it execute callbacks instead of queueing string-based events.
4. **Lifecycle integration**: initialize timers from `basic_runtime_init()` and shut them down in `basic_runtime_cleanup()`.

## 6. Detailed Design

### 6.1 Timer Runtime ABI

Create a new C-facing wrapper (e.g. `runtime/timer_c_api.cpp` + header) with functions:

```
int fb_timer_after_ms(int duration_ms, FbTimerCallback callback, void *context);
int fb_timer_every_ms(int interval_ms, FbTimerCallback callback, void *context);
int fb_timer_after_frames(int frame_count, FbTimerCallback callback, void *context);
int fb_timer_every_frames(int frame_interval, FbTimerCallback callback, void *context);
void fb_timer_stop(int timer_id);
void fb_timer_stop_by_handler(FbTimerCallback callback, void *context);
void fb_timer_stop_all(void);
void fb_timer_shutdown(void);   // invoked during runtime cleanup
```

Where:

```
typedef void (*FbTimerCallback)(void *context);
```

Internally:

- `TimerEntry` gains callback and context pointers (replaces `handlerName`).
- `fireTimer` invokes `callback(context)` directly.
- Optionally retain ID for cancellation and debugging.

### 6.2 Runtime Initialization

Modify `基本 runtime`:

1. During `basic_runtime_init()`:
   - Instantiate a global `EventQueue` (if still needed).
   - Instantiate `TimerManager`, call `.initialize(queue)` (or omit queue if firing directly).
   - Start the timer processing thread.

2. During `basic_runtime_cleanup()`:
   - Call `TimerManager::stop()`.
   - Destroy timers and release resources.

If the event queue is no longer required for native callbacks, this step can simplify `TimerManager` to invoke callbacks inline.

### 6.3 Code Generation Changes

#### Timers

1. **AST/CFG**: ensure timer statements are represented with metadata about:
   - Delay/interval (ms or frames).
   - Target function symbol.
2. **QBE Lowering**:
   - Emit calls to the new C API (e.g. `fb_timer_after_ms`).
   - Pass addresses of compiled BASIC subroutines as `FbTimerCallback`.
   - If BASIC subroutines use a custom calling convention, generate thin adaptor functions that translate timer callbacks into BASIC runtime calls.
3. **Timer IDs**: if BASIC code can capture timer handles, store the return value in generated temporaries/variables.

#### Threads

The addition of user-level threading has significant impact on code generation:

1. **Thread Entry Thunks**:  
   - For each `THREAD START SubName, ...`, the code generator must emit a C-compatible thunk function that unpacks arguments from a struct and calls the BASIC subroutine.
   - The thunk and argument pointer are passed to the runtime's `fb_thread_start`.
   - The code generator should cache/reuse thunks for identical subroutine signatures.

2. **Argument Marshalling**:  
   - Arguments to threaded subroutines are marshaled into a struct or array.
   - The code generator emits code to allocate and initialize this struct before thread creation.

3. **Thread Handle Variables**:  
   - The result of `THREAD START` is an integer handle. Codegen must ensure these are stored and passed correctly to `THREAD JOIN` and `THREAD ALIVE`.

4. **Synchronization Primitives**:  
   - For each `CRITICAL SECTION ... END CRITICAL` block, the code generator emits calls to runtime lock/unlock functions at the block boundaries (e.g., `fb_critical_enter()` and `fb_critical_exit()`).

5. **Thread-Safe Runtime Calls**:  
   - All runtime calls (strings, arrays, files, etc.) must be assumed to be potentially concurrent. The codegen does not emit locks for every call, but must not assume single-threaded execution.

6. **Stack and Local Variables**:  
   - Each thread has its own stack and local variable context. Codegen must ensure local variables are per-thread, while shared variables (`DIM SHARED`) are global and require user synchronization.

7. **Error Handling**:  
   - Codegen should check the return value of `THREAD START` and emit code to handle errors (e.g., print an error or set a status variable).

8. **Timer/Thread Handler Interoperability**:  
   - Timer callbacks and thread entry points use the same thunk/argument marshalling logic.

##### Example Codegen Flow for THREAD START

1. Allocate and initialize argument struct.
2. Emit thunk function if not already emitted for this subroutine signature.
3. Emit call to `fb_thread_start(thunk, argptr)`.
4. Store returned handle in user variable.

##### Summary Table: Codegen Responsibilities

| Feature                | Codegen Action                                                                 |
|------------------------|-------------------------------------------------------------------------------|
| THREAD START           | Emit thunk, marshal args, call runtime, store handle                          |
| THREAD JOIN/ALIVE      | Pass handle to runtime API                                                    |
| CRITICAL SECTION       | Emit lock/unlock calls at block boundaries                                    |
| Timer/Thread Handlers  | Use same thunk/argument marshalling logic                                     |
| Shared Variables       | No change, but document need for user synchronization                         |
| Error Handling         | Check thread API return values, emit error handling code                      |


### 6.4 Linking and Build Changes

- Extend `build_qbe_basic.sh` to compile the C++ runtime portions required:
  - `TimerManager.cpp`, `EventQueue.cpp`, and the new wrapper.
  - Provide a static library (e.g., `libfasterbasic_runtime.a`).
- Update the link command in `fbc_qbe.cpp` to link that library alongside the existing C runtime archive/source files.
- Ensure C++ runtime objects are compiled with `-fno-exceptions` and `-fno-rtti` if desired for minimal footprint.

### 6.5 Program Execution Model

The design adopts a multi-threaded model where timer events execute in parallel with the main BASIC thread. In addition, BASIC programs may create their own threads, which can run user code concurrently with both the main thread and timer callbacks. This allows for responsive, non-blocking timer handling and parallel computation, but introduces significant thread safety and coordination concerns.

#### Default Multi-Threaded Behavior

- Timer callbacks fire on a dedicated background thread managed by `TimerManager`.
- User-created BASIC threads may run in parallel with the main thread and timer callbacks.
- All BASIC handlers and runtime functions must be thread-safe when accessing shared runtime state (e.g., global variables, arrays, strings).
- The main thread continues executing BASIC code independently, enabling concurrent operations.

#### Thread Safety Considerations

Runtime functions requiring locking include:
- **String operations** (e.g., `basic_string_assign`, `string_concat`): Use a global string mutex to protect reference counting and heap allocations.
- **Array operations** (e.g., `basic_array_access`): Lock array descriptors and bounds checking to prevent concurrent modifications.
- **Global variables**: Protect the global variable vector with a mutex during reads/writes.
- **File I/O**: Existing file table operations should use locking to avoid race conditions on file handles.
- **Memory management**: Arena allocator (`basic_alloc_temp`) needs synchronization to prevent corruption from parallel allocations.

#### Locking Strategy

- Use fine-grained locking: separate mutexes for strings, arrays, globals, and files to minimize contention.
- Prefer reader-writer locks where reads dominate (e.g., for global variable access).
- Avoid holding locks across timer callbacks or user thread entry points to prevent deadlocks; encourage short, atomic operations.
- Provide debug builds with lock order checking to detect potential deadlocks.
- Document and enforce a global lock acquisition order for all runtime locks to reduce deadlock risk in a multi-threaded environment.

#### Alternative Options

1. **Single-Threaded Mode**: Expose `fb_timer_pump(int timeout_ms)` for programs that prefer polling. Callbacks are queued and processed on the main thread during pump calls, eliminating concurrency but requiring user code to periodically invoke the pump.
2. **Hybrid Mode**: Allow user selection via a compile-time flag or runtime option. Multi-threaded by default for performance, with a fallback to queued single-threaded execution.
3. **Callback Serialization**: Use a dedicated worker thread that serializes all timer callbacks, reducing locking needs but potentially introducing latency for high-frequency timers.
4. **Full Multi-Threaded Mode (Recommended)**: All timer callbacks and user-created threads run in parallel, with robust locking and coordination. This mode is preferred given the prevalence of multi-core CPUs in all supported systems, and the performance benefits outweigh the overhead of thread-safe design.

### 6.6 Error Handling & Diagnostics

- Return negative codes or `0` on failure (`fb_timer_after_ms`).
- Add runtime checks for:
  - Invalid durations (e.g., negative).
  - Null callbacks.
  - Timer subsystem not initialized (should not occur if runtime is properly set up).
- Provide `fb_timer_get_active_count()` or debug logging behind conditional compilation.

## 7. Migration Strategy

1. **Phase 1 – Runtime Prep**
   - Introduce callback-capable `TimerEntry`.
   - Add the C ABI wrapper.
   - Update the timer runtime to work without string handlers.
   - Unit-test timer behavior with C harnesses.

2. **Phase 2 – Compiler Changes**
   - Update AST/CFG to flag timer nodes.
   - Emit runtime calls and ensure function pointers are available as constants.
   - Implement cancellation semantics (`STOP TIMER`, etc.).

3. **Phase 3 – Build Integration**
   - Modify `build_qbe_basic.sh` to ship the timer runtime library.
   - Validate linker steps for all supported architectures.

4. **Phase 4 – Validation**
   - Regression tests: compile BASIC programs that use `AFTER`, `EVERY`, `AFTERFRAMES`, `EVERYFRAME`.
   - Verify multi-thread handling (if background thread used) and cleanup on exit.
   - Measure binary size and adjust build flags as needed.

## 8. Open Questions

1. **Threading Model**: Resolved to multi-threaded by default with single-threaded option (see Section 6.5). The choice impacts locking complexity and user code requirements.
2. **Frame-based Timers**: How will compiled programs advance frames? Need an API (`fb_timer_on_frame_complete(frame_number)`) the user calls from her own rendering loop. Consider integrating with a hypothetical `fb_frame_advance()` call.
3. **Timer Granularity**: Do we need higher precision than millisecond resolution? Should the runtime use `steady_clock` with `wait_until` for better accuracy, especially for sub-millisecond intervals?
4. **Optional Inclusion**: Should the timer runtime be linked only when the program uses timer constructs? (Requires codegen to emit a linker hint or use dead-stripping; adds build complexity but reduces binary size.)
5. **Lock Granularity**: How to balance fine-grained vs. coarse-grained locking? Fine-grained reduces contention but increases deadlock risk; consider lock hierarchies or automated detection tools.
6. **Callback Reentrancy**: What if a timer callback triggers another timer registration? Ensure the timer manager handles recursive registrations safely, possibly deferring additions until the current firing cycle completes.

## 9. Summary

Supporting timers in compiled FasterBASIC executables requires:

- Shipping the C++ timer runtime in native binaries with multi-threaded execution.
- Exposing C-callable wrappers that map timer registrations to function pointers.
- Adjusting code generation to emit the relevant API calls.
- Properly initializing and shutting down the timer system alongside the existing C runtime.
- Implementing thread-safe locking for shared runtime state to prevent race conditions.

Once implemented, BASIC programs that rely on `AFTER`/`EVERY` will behave consistently across interpreter and compiled modes, enabling richer interactive applications in native deployments while maintaining thread safety.

---

## 10. User Guidance and Best Practices

### Multi-Threading in BASIC

- BASIC programs may create new threads (API to be defined), which run user code in parallel with the main thread and timer callbacks.
- All shared state (globals, arrays, strings, files) must be accessed with proper synchronization.
- Timer handlers and user thread entry points should be designed for concurrency and avoid holding locks for long periods.

### Writing Thread-Safe BASIC Code with Timers and Threads

- **Avoid writing to global variables or shared arrays from multiple threads (main, timer, or user-created) unless you use explicit locking.**
- **If you must share state, use provided locking primitives (to be added) or design your program so that timer handlers and threads only post messages or set flags, which the main thread checks and acts upon.**
- **Do not perform long-running or blocking operations in timer handlers or user threads, as this can delay other timers and increase contention.**
- **Consider using message queues or atomic flags for communication between threads.**

#### Example: Safe Pattern

```basic
' Shared flag, only written by timer handler or thread, read by main thread
DIM SHARED timer_flag AS INTEGER

SUB OnTimer()
    ' Set flag only
    timer_flag = 1
END SUB

SUB WorkerThread()
    ' Set flag only
    timer_flag = 2
END SUB

' Main loop
DO
    IF timer_flag = 1 THEN
        PRINT "Timer fired!"
        timer_flag = 0
    ELSEIF timer_flag = 2 THEN
        PRINT "Worker thread signaled!"
        timer_flag = 0
    END IF
    ' ... other work ...
LOOP
```

#### Example: Unsafe Pattern

```basic
' Unsafe: main thread, timer handler, and user thread write to shared array
DIM SHARED arr(100) AS INTEGER

SUB OnTimer()
    arr(1) = arr(1) + 1  ' Potential race condition!
END SUB

SUB WorkerThread()
    arr(1) = arr(1) + 2  ' Potential race condition!
END SUB
```

---

## 11. Debugging and Diagnostics

- Provide a runtime function (e.g., `fb_timer_dump_active()`) that prints all active timers, their scheduled fire times, and handler addresses.
- In debug builds, enable lock order checking and deadlock detection.
- Add logging for timer registration, firing, and cancellation events.

---

## 12. Advanced Topics

### Timer Handler Return Values

- Optionally, allow timer handlers to return a value (e.g., `0` to cancel, `1` to continue for repeating timers).
- This can be implemented by checking the return value in the timer thread and updating the timer’s active status accordingly.

### Reentrancy and Nested Timer Operations

- Document that timer handlers may safely register or cancel other timers.
- Internally, ensure the timer manager uses appropriate locking and defers modifications if necessary to avoid iterator invalidation or deadlocks.

---

## 13. Future Work

- Investigate providing a BASIC-level critical section or mutex API for advanced users.
- Define and implement a BASIC API for creating, joining, and managing threads (e.g., `THREAD START`, `THREAD JOIN`).
- Explore integration with OS-level timer facilities for improved precision or power efficiency.
- Consider supporting timer priorities or deadlines for real-time applications.
- Provide higher-level concurrent data structures (e.g., message queues, atomic counters) for safe inter-thread communication in BASIC.
- Develop comprehensive documentation and examples for multi-threaded BASIC programming.

---

## 14. BASIC Threading Feature Design

### 14.1 Syntax Overview

**Starting a Thread**
```basic
THREAD START MySubroutine
```
or with arguments:
```basic
THREAD START MySubroutine, arg1, arg2
```

**Joining a Thread**
```basic
THREAD JOIN threadHandle
```

**Checking if a Thread is Running**
```basic
IF THREAD ALIVE(threadHandle) THEN PRINT "Still running"
```

**Example: Launch and Wait**
```basic
DIM t AS INTEGER
t = THREAD START Worker, 42

PRINT "Main thread continues..."

THREAD JOIN t
PRINT "Worker finished!"
```

### 14.2 Semantics

- `THREAD START SubName [, arg1, arg2, ...]`  
  Starts a new thread that runs the specified subroutine with optional arguments. Returns a thread handle (integer).
- `THREAD JOIN handle`  
  Waits for the thread with the given handle to finish.
- `THREAD ALIVE(handle)`  
  Returns 1 if the thread is still running, 0 otherwise.
- All threads share global variables, arrays, and resources—so synchronization is required for shared state.

### 14.3 Subroutine Requirements

- The subroutine must be declared as `SUB` (not `FUNCTION`).
- Arguments are passed by value.
- Example:
    ```basic
    SUB Worker(n)
        FOR i = 1 TO n
            PRINT "Worker: "; i
            SLEEP 100
        NEXT
    END SUB
    ```

### 14.4 Runtime API (for codegen)

- `int fb_thread_start(void (*entry)(void*), void* arg)`: returns thread handle.
- `void fb_thread_join(int handle)`: blocks until thread finishes.
- `int fb_thread_alive(int handle)`: returns 1 if running, 0 if finished.
- The compiler generates a thunk to marshal BASIC arguments into a struct and pass to the thread entry.

### 14.5 Synchronization Primitives

- Provide a simple `CRITICAL SECTION` block for mutual exclusion:
    ```basic
    CRITICAL SECTION
        ' code here is protected by a global mutex
    END CRITICAL
    ```
- Optionally, expose `LOCK`/`UNLOCK` statements for advanced users.

### 14.6 Example Usage

```basic
DIM t1 AS INTEGER, t2 AS INTEGER

t1 = THREAD START PrintNumbers, 10
t2 = THREAD START PrintNumbers, 5

' Main thread does other work
FOR i = 1 TO 3
    PRINT "Main: "; i
    SLEEP 200
NEXT

THREAD JOIN t1
THREAD JOIN t2

PRINT "All threads finished!"

SUB PrintNumbers(n)
    FOR i = 1 TO n
        CRITICAL SECTION
            PRINT "Thread "; THREAD ID(); ": "; i
        END CRITICAL
        SLEEP 100
    NEXT
END SUB
```

### 14.7 Error Handling

- If a thread handle is invalid, `THREAD JOIN` or `THREAD ALIVE` returns an error code or prints a runtime error.
- If too many threads are started, return -1 from `THREAD START` and print an error.

### 14.8 Implementation Notes

- Each thread gets its own stack and BASIC execution context, but shares global variables and arrays.
- The runtime manages a thread table, mapping handles to OS threads.
- The code generator emits thunks to marshal arguments and call the user subroutine.
- All runtime APIs (strings, arrays, files, etc.) must be thread-safe.

### 14.9 Summary Table

| Statement                | Description                                 |
|--------------------------|---------------------------------------------|
| THREAD START Sub[, args] | Start a new thread, returns handle          |
| THREAD JOIN handle       | Wait for thread to finish                   |
| THREAD ALIVE(handle)     | Check if thread is still running            |
| CRITICAL SECTION ... END | Mutual exclusion for shared code blocks     |


