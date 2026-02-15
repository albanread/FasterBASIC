' =============================================================
' Parallel Pi Calculator using Worker Threads
' =============================================================
'
' Computes pi via numerical integration of f(x) = 4/(1+x^2)
' over [0,1].  The exact integral equals pi.
'
' Method: midpoint rectangle rule with N steps
'
' Strategy:
'   1. Sequential — single-threaded, all N steps
'   2. Parallel   — 4 workers, each N/4 steps over 1/4 of [0,1]
'   3. Compare results, timing, and speedup
'
' This demonstrates:
'   - Real computational work distributed across workers
'   - UDT messaging for task distribution and result collection
'   - MATCH RECEIVE type dispatch
'   - TIMER for wall-clock measurement
'   - Message memory metrics (run with BASIC_MEMORY_STATS=1)

TYPE WorkRange
    lo AS DOUBLE
    hi AS DOUBLE
    steps AS DOUBLE
END TYPE

TYPE WorkResult
    partial_sum AS DOUBLE
    range_lo AS DOUBLE
    range_hi AS DOUBLE
END TYPE

' ---------------------------------------------------------
' Worker: receives a WorkRange, computes midpoint-rule
' integral of 4/(1+x^2) over [lo, hi], sends WorkResult
' ---------------------------------------------------------
WORKER Integrator() AS DOUBLE
    DIM wr AS WorkRange
    DIM res AS WorkResult
    DIM sum AS DOUBLE = 0.0
    DIM dx AS DOUBLE
    DIM i AS DOUBLE
    DIM x AS DOUBLE

    MATCH RECEIVE(PARENT)
        CASE WorkRange wr
            dx = (wr.hi - wr.lo) / wr.steps
            i = 0
            WHILE i < wr.steps
                x = wr.lo + (i + 0.5) * dx
                sum = sum + 4.0 / (1.0 + x * x) * dx
                i = i + 1
            WEND
            res.partial_sum = sum
            res.range_lo = wr.lo
            res.range_hi = wr.hi
            SEND PARENT, res
    END MATCH
    DIM ret AS DOUBLE = 0.0
    RETURN ret
END WORKER

' Total number of integration steps (shared between approaches)
DIM NUM_STEPS AS DOUBLE = 20000000
DIM PI_KNOWN AS DOUBLE = 3.14159265358979

PRINT "=============================================="
PRINT "  Parallel Pi Calculator"
PRINT "=============================================="
PRINT "  Integration steps: "; NUM_STEPS
PRINT ""

' =============================================================
' 1) Sequential computation
' =============================================================
PRINT "--- Sequential (1 thread) ---"

DIM t0 AS DOUBLE = TIMER()

DIM seq_sum AS DOUBLE = 0.0
DIM seq_dx AS DOUBLE = 1.0 / NUM_STEPS
DIM si AS DOUBLE = 0
WHILE si < NUM_STEPS
    DIM sx AS DOUBLE = (si + 0.5) * seq_dx
    seq_sum = seq_sum + 4.0 / (1.0 + sx * sx) * seq_dx
    si = si + 1
WEND

DIM t1 AS DOUBLE = TIMER()
DIM seq_time AS DOUBLE = t1 - t0
DIM seq_err AS DOUBLE = ABS(seq_sum - PI_KNOWN)

PRINT "  Pi = "; seq_sum
PRINT "  Error = "; seq_err
PRINT "  Time  = "; seq_time; " sec"
PRINT ""

' =============================================================
' 2) Parallel computation — 4 workers
' =============================================================
PRINT "--- Parallel (4 workers) ---"

DIM t2 AS DOUBLE = TIMER()

' Spawn 4 workers
DIM f1 AS DOUBLE
DIM f2 AS DOUBLE
DIM f3 AS DOUBLE
DIM f4 AS DOUBLE
f1 = SPAWN Integrator()
f2 = SPAWN Integrator()
f3 = SPAWN Integrator()
f4 = SPAWN Integrator()

' Distribute work — each worker gets 1/4 of [0, 1]
DIM steps_per AS DOUBLE = NUM_STEPS / 4
DIM rng AS WorkRange

rng.lo = 0.0
rng.hi = 0.25
rng.steps = steps_per
SEND f1, rng

rng.lo = 0.25
rng.hi = 0.50
rng.steps = steps_per
SEND f2, rng

rng.lo = 0.50
rng.hi = 0.75
rng.steps = steps_per
SEND f3, rng

rng.lo = 0.75
rng.hi = 1.0
rng.steps = steps_per
SEND f4, rng

' Collect partial results via MATCH RECEIVE
DIM par_sum AS DOUBLE = 0.0
DIM res AS WorkResult

MATCH RECEIVE(f1)
    CASE WorkResult res
        PRINT "  Worker 1 ["; res.range_lo; " .. "; res.range_hi; "]: "; res.partial_sum
        par_sum = par_sum + res.partial_sum
END MATCH

MATCH RECEIVE(f2)
    CASE WorkResult res
        PRINT "  Worker 2 ["; res.range_lo; " .. "; res.range_hi; "]: "; res.partial_sum
        par_sum = par_sum + res.partial_sum
END MATCH

MATCH RECEIVE(f3)
    CASE WorkResult res
        PRINT "  Worker 3 ["; res.range_lo; " .. "; res.range_hi; "]: "; res.partial_sum
        par_sum = par_sum + res.partial_sum
END MATCH

MATCH RECEIVE(f4)
    CASE WorkResult res
        PRINT "  Worker 4 ["; res.range_lo; " .. "; res.range_hi; "]: "; res.partial_sum
        par_sum = par_sum + res.partial_sum
END MATCH

' Reap workers
DIM dummy AS DOUBLE
dummy = AWAIT f1
dummy = AWAIT f2
dummy = AWAIT f3
dummy = AWAIT f4

DIM t3 AS DOUBLE = TIMER()
DIM par_time AS DOUBLE = t3 - t2
DIM par_err AS DOUBLE = ABS(par_sum - PI_KNOWN)

PRINT "  --------"
PRINT "  Pi = "; par_sum
PRINT "  Error = "; par_err
PRINT "  Time  = "; par_time; " sec"
PRINT ""

' =============================================================
' 3) Summary
' =============================================================
PRINT "--- Summary ---"
IF par_time > 0 THEN
    DIM speedup AS DOUBLE = seq_time / par_time
    PRINT "  Speedup: "; speedup; "x"
ELSE
    PRINT "  Speedup: (parallel too fast to measure)"
END IF

DIM agreement AS DOUBLE = ABS(seq_sum - par_sum)
IF agreement < 0.0000000001 THEN
    PRINT "  Results match: YES (diff = "; agreement; ")"
ELSE
    PRINT "  Results match: NO  (diff = "; agreement; ")"
END IF

IF seq_err < 0.000001 THEN
    PRINT "  Accuracy: GOOD (within 1e-6 of pi)"
ELSE
    PRINT "  Accuracy: LOW  (error = "; seq_err; ")"
END IF

PRINT "=============================================="
PRINT "Done"
