REM Test SCREENWIDTH and SCREENHEIGHT terminal size detection
REM Verifies that the runtime can detect the terminal dimensions

PRINT "Terminal Size Detection Test"
PRINT "============================"
PRINT

DIM w AS INTEGER
DIM h AS INTEGER

w = SCREENWIDTH
h = SCREENHEIGHT

PRINT "Detected terminal size:"
PRINT "  Width  (columns): "; w
PRINT "  Height (rows):    "; h
PRINT

REM Sanity checks
DIM pass_count AS INTEGER
DIM fail_count AS INTEGER
pass_count = 0
fail_count = 0

REM Width should be reasonable (at least 40, at most 500)
IF w >= 40 AND w <= 500 THEN
    PRINT "  ✓ Width is in reasonable range (40-500)"
    pass_count = pass_count + 1
ELSE
    PRINT "  ✗ Width "; w; " is outside reasonable range (40-500)"
    fail_count = fail_count + 1
END IF

REM Height should be reasonable (at least 10, at most 200)
IF h >= 10 AND h <= 200 THEN
    PRINT "  ✓ Height is in reasonable range (10-200)"
    pass_count = pass_count + 1
ELSE
    PRINT "  ✗ Height "; h; " is outside reasonable range (10-200)"
    fail_count = fail_count + 1
END IF

REM Common terminal sizes: 80x24, 80x25, 120x30, etc.
REM Width should not be the fallback 0
IF w > 0 THEN
    PRINT "  ✓ Width is non-zero (detection succeeded)"
    pass_count = pass_count + 1
ELSE
    PRINT "  ✗ Width is zero (detection may have failed)"
    fail_count = fail_count + 1
END IF

IF h > 0 THEN
    PRINT "  ✓ Height is non-zero (detection succeeded)"
    pass_count = pass_count + 1
ELSE
    PRINT "  ✗ Height is zero (detection may have failed)"
    fail_count = fail_count + 1
END IF

PRINT
PRINT "Results: "; pass_count; " passed, "; fail_count; " failed"

IF fail_count = 0 THEN
    PRINT "✓ All terminal size tests passed!"
ELSE
    PRINT "✗ Some tests failed - check terminal environment"
END IF
