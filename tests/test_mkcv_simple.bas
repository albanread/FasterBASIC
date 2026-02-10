REM Simple test for MK$ and CV$ binary conversion functions
REM Tests: MKI$, MKD$, CVI, CVD (avoiding SINGLE type)

PRINT "=== Simple MK$/CV$ Function Test ==="
PRINT ""

REM Test 1: MKI$ and CVI (16-bit integer)
PRINT "Test 1: MKI$ and CVI (Integer)"
DIM test_int AS INTEGER
DIM int_str AS STRING

test_int = 12345
int_str = MKI(test_int)
PRINT "  Original: "; test_int
PRINT "  String length: "; LEN(int_str); " bytes"

DIM back_int AS INTEGER
back_int = CVI(int_str)
PRINT "  Recovered: "; back_int

IF back_int = test_int THEN
    PRINT "  PASS: Integer roundtrip"
ELSE
    PRINT "  FAIL: Integer roundtrip"
END IF
PRINT ""

REM Test 2: Negative integer
PRINT "Test 2: Negative integer"
test_int = -1000
int_str = MKI(test_int)
back_int = CVI(int_str)
PRINT "  Original: "; test_int
PRINT "  Recovered: "; back_int
IF back_int = test_int THEN
    PRINT "  PASS: Negative integer"
ELSE
    PRINT "  FAIL: Negative integer"
END IF
PRINT ""

REM Test 3: MKD$ and CVD (Double precision)
PRINT "Test 3: MKD$ and CVD (Double)"
DIM test_dbl AS DOUBLE
DIM dbl_str AS STRING

test_dbl = 3.141592653589793
dbl_str = MKD(test_dbl)
PRINT "  Original: "; test_dbl
PRINT "  String length: "; LEN(dbl_str); " bytes"

DIM back_dbl AS DOUBLE
back_dbl = CVD(dbl_str)
PRINT "  Recovered: "; back_dbl

DIM diff AS DOUBLE
diff = ABS(back_dbl - test_dbl)
IF diff < 0.0000001 THEN
    PRINT "  PASS: Double roundtrip"
ELSE
    PRINT "  FAIL: Double roundtrip (diff="; diff; ")"
END IF
PRINT ""

REM Test 4: Zero values
PRINT "Test 4: Zero values"
int_str = MKI(0)
back_int = CVI(int_str)
PRINT "  Integer 0 -> "; back_int
IF back_int = 0 THEN PRINT "  PASS: Zero integer"

dbl_str = MKD(0.0)
back_dbl = CVD(dbl_str)
PRINT "  Double 0.0 -> "; back_dbl
IF back_dbl = 0.0 THEN PRINT "  PASS: Zero double"
PRINT ""

REM Test 5: Maximum 16-bit value
PRINT "Test 5: Max 16-bit signed integer"
test_int = 32767
int_str = MKI(test_int)
back_int = CVI(int_str)
PRINT "  32767 -> "; back_int
IF back_int = 32767 THEN PRINT "  PASS: Max int"
PRINT ""

REM Test 6: Combined storage
PRINT "Test 6: Combined storage (int + double + int)"
DIM combo AS STRING
DIM v1 AS INTEGER
DIM v2 AS DOUBLE
DIM v3 AS INTEGER

v1 = 100
v2 = 99.5
v3 = 200

combo = MKI(v1) + MKD(v2) + MKI(v3)
PRINT "  Combined length: "; LEN(combo); " bytes"

DIM r1 AS INTEGER
DIM r2 AS DOUBLE
DIM r3 AS INTEGER

r1 = CVI(LEFT(combo, 2))
r2 = CVD(MID(combo, 3, 8))
r3 = CVI(RIGHT(combo, 2))

PRINT "  Extracted: "; r1; ", "; r2; ", "; r3
IF r1 = v1 AND r3 = v3 THEN
    PRINT "  PASS: Combined storage"
ELSE
    PRINT "  FAIL: Combined storage"
END IF
PRINT ""

PRINT "=== Test Complete ==="
