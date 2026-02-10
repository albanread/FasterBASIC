# Workers: Safe Concurrency in FasterBASIC

FasterBASIC's WORKER feature brings modern concurrency to BASIC — without the pain. Inspired by Web Workers and the actor model, workers are **isolated functions that run on background threads**. They enforce a strict no-shared-state design: data goes in by copy, a single result comes out, and nothing in between can corrupt your program. No locks, no races, no surprises.

## The Core Idea

Traditional threading is notoriously error-prone. Shared mutable state, locks, deadlocks, and data races have ruined countless programs. FasterBASIC takes a different approach: **isolation by design**.

A worker is a pure computation. It receives its inputs as copied values, does its work using only local variables, and returns a result. It cannot touch global variables, perform I/O, draw graphics, or interact with any shared state. The compiler enforces all of this at compile time — not as a convention, but as a hard rule.

```basic
WORKER Multiply(a AS DOUBLE, b AS DOUBLE) AS DOUBLE
    RETURN a * b
END WORKER

DIM future AS DOUBLE
future = SPAWN Multiply(6, 7)
DIM result AS DOUBLE
result = AWAIT future
PRINT result   ' 42
```

That's it. `SPAWN` launches the worker on a new OS thread and immediately returns a **future handle**. `AWAIT` blocks until the worker finishes and retrieves the result. The handle is then consumed and freed — you cannot await it twice.

## Syntax Reference

### Defining a Worker

```basic
WORKER Name(param1 AS Type, param2 AS Type, ...) AS ReturnType
    ' computation using only local variables
    RETURN expression
END WORKER
```

Workers look like functions, but with the `WORKER` keyword. `END WORKER` (or `ENDWORKER`) closes the block.

### Spawning

```basic
DIM f AS DOUBLE
f = SPAWN WorkerName(arg1, arg2, ...)
```

`SPAWN` copies all arguments, creates a new thread, and returns a future handle stored as a `DOUBLE`.

### Awaiting

```basic
DIM result AS DOUBLE
result = AWAIT f
```

`AWAIT` blocks until the worker completes, returns the result, and destroys the future handle. After `AWAIT`, the handle is invalid.

### Polling with READY

```basic
IF READY(f) THEN
    result = AWAIT f
ELSE
    PRINT "Still working..."
END IF
```

`READY(future)` is a non-blocking check: it returns 1 if the worker has finished, 0 if it's still running. This lets you build responsive main loops that don't freeze while waiting for background computation.

### Marshalling Complex Data

Scalar values (doubles, integers) are passed directly as arguments. But what about arrays and user-defined types? They need to be **marshalled** — serialized into a portable blob that can safely cross the thread boundary.

```basic
' Passing an array into a worker
DIM blob AS MARSHALLED
blob = MARSHALL(myArray)
future = SPAWN ProcessData(blob)

' Inside the worker
WORKER ProcessData(data AS MARSHALLED) AS DOUBLE
    DIM numbers(10) AS DOUBLE
    UNMARSHALL numbers, data
    ' now work with the local copy
    DIM total AS DOUBLE
    FOR i = 1 TO 10
        total = total + numbers(i)
    NEXT i
    RETURN total
END WORKER
```

`MARSHALL(variable)` creates a deep copy of an array or UDT as a self-contained blob. `UNMARSHALL target, source` reconstructs the data on the other side. The blob is automatically freed after unmarshalling.

This also works with user-defined types:

```basic
TYPE Vec3
    x AS DOUBLE
    y AS DOUBLE
    z AS DOUBLE
END TYPE

DIM v AS Vec3
v.x = 10 : v.y = 20 : v.z = 30

DIM blob AS MARSHALLED
blob = MARSHALL(v)
future = SPAWN SumVector(blob)
result = AWAIT future
PRINT result   ' 60

WORKER SumVector(data AS MARSHALLED) AS DOUBLE
    DIM vec AS Vec3
    UNMARSHALL vec, data
    RETURN vec.x + vec.y + vec.z
END WORKER
```

## What Workers Can Do

Workers have full access to:

- **Local variables** — `DIM`, assignments, `SWAP`, `INC`/`DEC`
- **Control flow** — `IF`, `FOR`, `WHILE`, `REPEAT`, `DO`, `SELECT CASE`, `EXIT`
- **Arithmetic and logic** — all expressions, comparisons, operators
- **Function calls** — `CALL` to other functions and subs
- **Array operations** — `REDIM`, `ERASE`, `DELETE` (on local arrays)
- **Data reconstruction** — `UNMARSHALL`
- **Return values** — `RETURN expression`

## What Workers Cannot Do

The compiler rejects workers that attempt any of the following:

| Forbidden | Reason |
|---|---|
| `PRINT`, `CONSOLE`, `INPUT` | No I/O in isolated threads |
| `GLOBAL`, `SHARED` variables | Workers are isolated |
| `OPEN`, `CLOSE` (file I/O) | File I/O not allowed |
| `CLS`, `PSET`, `LINE`, `CIRCLE` | Graphics commands not allowed |
| `SPRLOAD`, sprite commands | Sprite commands not allowed |
| `PLAY`, audio commands | Audio commands not allowed |
| `TIMER` | Timer commands not allowed |
| Accessing global variables | Isolation violation |
| `SPAWN` inside a worker | No nested workers |
| Nested `WORKER` definitions | Cannot nest WORKER inside WORKER |

These aren't runtime errors — they're **compile-time errors**. The semantic analyzer catches every violation before any code is generated.

## Running Multiple Workers

Workers are most powerful when you run several in parallel:

```basic
WORKER ComputeSum(a AS DOUBLE, b AS DOUBLE) AS DOUBLE
    RETURN a + b
END WORKER

WORKER ComputeProduct(a AS DOUBLE, b AS DOUBLE) AS DOUBLE
    RETURN a * b
END WORKER

DIM f1 AS DOUBLE
DIM f2 AS DOUBLE
f1 = SPAWN ComputeSum(100, 200)
f2 = SPAWN ComputeProduct(10, 20)

DIM sum AS DOUBLE
DIM product AS DOUBLE
sum = AWAIT f1
product = AWAIT f2

PRINT "Sum: "; sum        ' 300
PRINT "Product: "; product ' 200
```

Both workers run simultaneously on separate OS threads. The main program spawns them both, then awaits each result. The total wall-clock time is the duration of the *slowest* worker, not the sum of both.

## A Practical Example: Parallel Statistics

Workers returning marshalled UDTs enable richer result types:

```basic
TYPE Stats
    min AS DOUBLE
    max AS DOUBLE
    avg AS DOUBLE
END TYPE

WORKER ComputeStats(data AS MARSHALLED) AS MARSHALLED
    DIM values(5) AS DOUBLE
    UNMARSHALL values, data

    DIM s AS Stats
    s.min = values(1)
    s.max = values(1)
    DIM total AS DOUBLE

    FOR i = 1 TO 5
        IF values(i) < s.min THEN s.min = values(i)
        IF values(i) > s.max THEN s.max = values(i)
        total = total + values(i)
    NEXT i
    s.avg = total / 5

    RETURN MARSHALL(s)
END WORKER

DIM arr(5) AS DOUBLE
arr(1) = 5 : arr(2) = 50 : arr(3) = 10 : arr(4) = 40 : arr(5) = 32.5

DIM blob AS MARSHALLED
blob = MARSHALL(arr)
DIM future AS DOUBLE
future = SPAWN ComputeStats(blob)

DIM resultBlob AS MARSHALLED
resultBlob = AWAIT future
DIM result AS Stats
UNMARSHALL result, resultBlob

PRINT "Min: "; result.min   ' 5
PRINT "Max: "; result.max   ' 50
PRINT "Avg: "; result.avg   ' 27.5
```

## Under the Hood

### Threading Model

Each `SPAWN` creates a new POSIX thread via `pthread_create`. There is no thread pool — one worker, one thread. This is simple and predictable. For compute-heavy tasks that benefit from parallelism, this is ideal. For thousands of tiny tasks, the thread creation overhead would dominate; workers are designed for coarse-grained parallelism.

### Future Handles

A future handle is a pointer to a `FutureHandle` structure containing:

- A pthread handle for joining
- A mutex and condition variable for signaling completion
- A `done` flag (0 = running, 1 = complete)
- The result value (stored as a 64-bit double)

The pointer is bit-cast into a `DOUBLE` for storage in BASIC variables. `AWAIT` casts it back, joins the thread, retrieves the result, and frees all resources.

### Argument Passing

Arguments are packed into a `WorkerArgs` block — a fixed array of 16 `double` slots. Integers and pointers are stored via type-punning into 64-bit doubles. The worker's thread entry function unpacks them and calls the compiled worker body with the correct number of arguments using C calling conventions.

### Marshalling Format

- **Arrays**: The blob contains a 64-byte `ArrayDescriptor` header followed by the raw element data. The internal data pointer is patched to reference the blob's own storage, making it fully self-contained.
- **UDTs**: A simple `memcpy` of the struct's bytes into a heap-allocated blob.

Both are freed automatically by `UNMARSHALL`.

## Design Philosophy

FasterBASIC's workers follow a clear philosophy:

1. **Safety over flexibility** — No shared state means no data races, ever. The compiler guarantees this.
2. **Simplicity over power** — The API is five keywords: `WORKER`, `SPAWN`, `AWAIT`, `READY`, `MARSHALL`/`UNMARSHALL`. No channels, no mutexes, no atomics.
3. **Compile-time over runtime** — Isolation violations are caught during compilation, not as crashes at 3 AM.
4. **Value semantics** — Everything crossing the thread boundary is copied. The worker owns its data completely.

This makes workers accessible to BASIC programmers who may not have experience with concurrent programming, while still providing genuine OS-level parallelism for compute-bound tasks.

## Limitations

- **Up to 8 arguments** per worker (up to 16 internally, but the call-site dispatch covers 0–8)
- **Single return value** — use `MARSHALL` to return complex results
- **No message passing** — workers communicate only via arguments in and return value out
- **Thread-per-worker** — no pooling; best for coarse-grained parallel work
- **`AWAIT` consumes the handle** — a future can only be awaited once
- **No nested spawning** — workers cannot spawn other workers
