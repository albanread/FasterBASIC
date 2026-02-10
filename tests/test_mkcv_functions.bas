REM Test MK$ and CV$ binary conversion functions
REM Tests: MKI$, MKS$, MKD$, CVI, CVS, CVD

PRINT "=== Testing MK$ and CV$ Functions ==="
PRINT ""

REM Test 1: MKI$ and CVI (16-bit integer)
PRINT "Test 1: MKI$ and CVI (Integer conversion)"
DIM test_int AS INTEGER
DIM int_str$ AS STRING

test_int = 12345
int_str$ = MKI$(test_int)
PRINT "  Original value: "; test_int
PRINT "  String length: "; LEN(int_str$); " bytes"

DIM recovered_int AS INTEGER
recovered_int = CVI(int_str$)
PRINT "  Recovered value: "; recovered_int

IF recovered_int = test_int THEN
    PRINT "  ✓ Integer conversion OK"
ELSE
    PRINT "  ✗ Integer conversion FAILED"
END IF
PRINT ""

REM Test 2: Negative integers
PRINT "Test 2: Negative integer"
test_int = -5000
int_str$ = MKI$(test_int)
recovered_int = CVI(int_str$)
PRINT "  Original: "; test_int
PRINT "  Recovered: "; recovered_int
IF recovered_int = test_int THEN
    PRINT "  ✓ Negative integer OK"
ELSE
    PRINT "  ✗ Negative integer FAILED"
END IF
PRINT ""

REM Test 3: MKS$ and CVS (Single precision float)
PRINT "Test 3: MKS$ and CVS (Single precision)"
DIM test_single AS SINGLE
DIM single_str$ AS STRING

test_single = 3.14159
single_str$ = MKS$(test_single)
PRINT "  Original value: "; test_single
PRINT "  String length: "; LEN(single_str$); " bytes"

DIM recovered_single AS SINGLE
recovered_single = CVS(single_str$)
PRINT "  Recovered value: "; recovered_single

REM Allow small floating point error
DIM diff_single AS SINGLE
diff_single = ABS(recovered_single - test_single)
IF diff_single < 0.00001 THEN
    PRINT "  ✓ Single precision conversion OK"
ELSE
    PRINT "  ✗ Single precision conversion FAILED (diff: "; diff_single; ")"
END IF
PRINT ""

REM Test 4: MKD$ and CVD (Double precision float)
PRINT "Test 4: MKD$ and CVD (Double precision)"
DIM test_double AS DOUBLE
DIM double_str$ AS STRING

test_double = 2.718281828459045
double_str$ = MKD$(test_double)
PRINT "  Original value: "; test_double
PRINT "  String length: "; LEN(double_str$); " bytes"

DIM recovered_double AS DOUBLE
recovered_double = CVD(double_str$)
PRINT "  Recovered value: "; recovered_double

REM Allow small floating point error
DIM diff_double AS DOUBLE
diff_double = ABS(recovered_double - test_double)
IF diff_double < 0.00000000001 THEN
    PRINT "  ✓ Double precision conversion OK"
ELSE
    PRINT "  ✗ Double precision conversion FAILED (diff: "; diff_double; ")"
END IF
PRINT ""

REM Test 5: Zero values
PRINT "Test 5: Zero values"
test_int = 0
int_str$ = MKI$(test_int)
recovered_int = CVI(int_str$)
PRINT "  Integer zero: "; recovered_int
IF recovered_int = 0 THEN PRINT "  ✓ Zero integer OK"

test_double = 0.0
double_str$ = MKD$(test_double)
recovered_double = CVD(double_str$)
PRINT "  Double zero: "; recovered_double
IF recovered_double = 0.0 THEN PRINT "  ✓ Zero double OK"
PRINT ""

REM Test 6: Maximum values
PRINT "Test 6: Large values"
test_int = 32767
int_str$ = MKI$(test_int)
recovered_int = CVI(int_str$)
PRINT "  Max 16-bit int (32767): "; recovered_int
IF recovered_int = 32767 THEN PRINT "  ✓ Max int OK"

test_double = 1234567890.123456
double_str$ = MKD$(test_double)
recovered_double = CVD(double_str$)
PRINT "  Large double: "; recovered_double
diff_double = ABS(recovered_double - test_double)
IF diff_double < 0.001 THEN PRINT "  ✓ Large double OK"
PRINT ""

REM Test 7: Combining conversions (mixed data)
PRINT "Test 7: Mixed data storage"
DIM combined$ AS STRING
DIM val1 AS INTEGER
DIM val2 AS DOUBLE
DIM val3 AS INTEGER

val1 = 100
val2 = 99.5
val3 = 200

REM Combine into single string
combined$ = MKI$(val1) + MKD$(val2) + MKI$(val3)
PRINT "  Combined string length: "; LEN(combined$); " bytes (should be 12)"

REM Extract back
DIM recovered1 AS INTEGER
DIM recovered2 AS DOUBLE
DIM recovered3 AS INTEGER

recovered1 = CVI(LEFT$(combined$, 2))
recovered2 = CVD(MID$(combined$, 3, 8))
recovered3 = CVI(RIGHT$(combined$, 2))

PRINT "  Values: "; recovered1; ", "; recovered2; ", "; recovered3
IF recovered1 = val1 AND recovered3 = val3 THEN
    PRINT "  ✓ Mixed data storage OK"
ELSE
    PRINT "  ✗ Mixed data storage FAILED"
END IF
PRINT ""

PRINT "=== All MK$/CV$ tests complete ==="
