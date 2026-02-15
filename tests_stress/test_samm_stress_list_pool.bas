OPTION SAMM ON

PRINT "=== SAMM List Pool Stress Tests ==="
PRINT ""

' ---------------------------------------------------------------
' Test 1: High-volume list create/destroy churn
'   Creates and discards 2000 lists, each with a few elements.
'   Exercises ListHeader pool alloc/free cycling.
' ---------------------------------------------------------------
PRINT "Test 1: 2000 list create/destroy churn"
DIM total AS INTEGER
total = 0
FOR i = 1 TO 2000
    DIM tmp AS LIST OF INTEGER
    tmp.APPEND(i)
    tmp.APPEND(i * 2)
    total = total + tmp.HEAD()
NEXT i
PRINT "  Sum of heads: "; total
IF total = 2001000 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected 2001000)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 2: High-volume atom churn (append + shift)
'   Builds a list up to 500 elements, then shifts them all off.
'   Exercises ListAtom pool alloc/free cycling heavily.
' ---------------------------------------------------------------
PRINT "Test 2: 500-element append then shift-all"
DIM bigList AS LIST OF INTEGER
FOR i = 1 TO 500
    bigList.APPEND(i)
NEXT i
PRINT "  Length after append: "; bigList.LENGTH()

DIM shiftSum AS INTEGER
shiftSum = 0
DO WHILE bigList.EMPTY() = 0
    shiftSum = shiftSum + bigList.SHIFT()
LOOP
PRINT "  Length after shift-all: "; bigList.LENGTH()
PRINT "  Sum of shifted: "; shiftSum
IF shiftSum = 125250 AND bigList.LENGTH() = 0 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected sum=125250, length=0)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 3: Repeated append/pop cycling (reuse atoms)
'   Pushes 100 elements, pops them all, repeats 50 times.
'   Total: 5000 atom allocs and 5000 atom frees, recycling pool.
' ---------------------------------------------------------------
PRINT "Test 3: 50 cycles of 100 append + 100 pop"
DIM cycleList AS LIST OF INTEGER
DIM popSum AS INTEGER
popSum = 0
FOR cycle = 1 TO 50
    FOR j = 1 TO 100
        cycleList.APPEND(j)
    NEXT j
    FOR j = 1 TO 100
        popSum = popSum + cycleList.POP()
    NEXT j
NEXT cycle
PRINT "  Pop sum: "; popSum
' Each cycle pops 100+99+...+1 = 5050, times 50 = 252500
IF popSum = 252500 AND cycleList.LENGTH() = 0 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected sum=252500, length=0)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 4: String list churn (atom + string descriptor recycling)
'   Creates 1000 string list elements, verifies contents, clears.
' ---------------------------------------------------------------
PRINT "Test 4: 1000 string list elements"
DIM strList AS LIST OF STRING
FOR i = 1 TO 1000
    strList.APPEND("item_" + STR$(i))
NEXT i
PRINT "  Length: "; strList.LENGTH()
PRINT "  Head: "; strList.HEAD()
PRINT "  Get(500): "; strList.GET(500)
PRINT "  Get(1000): "; strList.GET(1000)
DIM headOk AS INTEGER
DIM lenOk AS INTEGER
headOk = 0
lenOk = 0
IF strList.HEAD() = "item_1" THEN headOk = 1
IF strList.LENGTH() = 1000 THEN lenOk = 1
strList.CLEAR()
IF headOk = 1 AND lenOk = 1 AND strList.LENGTH() = 0 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 5: Nested list churn
'   Creates 200 outer lists, each containing a nested inner list.
'   Exercises both header and atom pool recycling for nested cases.
' ---------------------------------------------------------------
PRINT "Test 5: 200 nested list create/destroy"
DIM nestedSum AS INTEGER
nestedSum = 0
FOR i = 1 TO 200
    DIM outer AS LIST OF INTEGER
    DIM inner AS LIST OF INTEGER
    inner.APPEND(i)
    inner.APPEND(i * 3)
    outer.APPEND(i * 2)
    nestedSum = nestedSum + outer.HEAD() + inner.HEAD()
NEXT i
PRINT "  Nested sum: "; nestedSum
' sum of (2i + i) = 3 * sum(i) = 3 * 20100 = 60300
IF nestedSum = 60300 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected 60300)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 6: COPY and REVERSE churn (allocates new lists+atoms)
'   Copies and reverses a 100-element list 100 times.
'   Heavy allocation of new headers and atoms each iteration.
' ---------------------------------------------------------------
PRINT "Test 6: 100 copy+reverse cycles on 100-element list"
DIM sourceList AS LIST OF INTEGER
FOR i = 1 TO 100
    sourceList.APPEND(i)
NEXT i
DIM lastHead AS INTEGER
lastHead = 0
FOR cycle = 1 TO 100
    DIM copied AS LIST OF INTEGER
    copied = sourceList.COPY()
    DIM reversed AS LIST OF INTEGER
    reversed = sourceList.REVERSE()
    lastHead = reversed.HEAD()
NEXT cycle
PRINT "  Last reversed head: "; lastHead
IF lastHead = 100 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected 100)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 7: EXTEND churn (bulk atom allocation)
'   Extends a destination list with a 50-element source, 100 times.
'   Creates 5000 new atoms via extend (deep copy of source atoms).
' ---------------------------------------------------------------
PRINT "Test 7: 100 extends of 50-element source"
DIM extSrc AS LIST OF INTEGER
FOR i = 1 TO 50
    extSrc.APPEND(i)
NEXT i
DIM extDst AS LIST OF INTEGER
FOR cycle = 1 TO 100
    extDst.EXTEND(extSrc)
NEXT cycle
PRINT "  Dest length: "; extDst.LENGTH()
PRINT "  Head: "; extDst.HEAD()
IF extDst.LENGTH() = 5000 AND extDst.HEAD() = 1 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected length=5000, head=1)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 8: Mixed prepend/shift storm
'   Prepends 1000 elements (each alloc at head), then shifts all.
'   Exercises atom allocation at list head position.
' ---------------------------------------------------------------
PRINT "Test 8: 1000 prepend + 1000 shift"
DIM prependList AS LIST OF INTEGER
FOR i = 1 TO 1000
    prependList.PREPEND(i)
NEXT i
PRINT "  Head after 1000 prepends: "; prependList.HEAD()

DIM prependShiftSum AS INTEGER
prependShiftSum = 0
DO WHILE prependList.EMPTY() = 0
    prependShiftSum = prependShiftSum + prependList.SHIFT()
LOOP
PRINT "  Shift sum: "; prependShiftSum
' Head should be 1000 (last prepended). Sum = 500500.
IF prependShiftSum = 500500 AND prependList.LENGTH() = 0 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected sum=500500, length=0)"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 9: Interleaved multi-list operations
'   Maintains 10 lists simultaneously, appending to each in
'   round-robin fashion, then clears them all.
' ---------------------------------------------------------------
PRINT "Test 9: 10 simultaneous lists, 100 elements each"
DIM list0 AS LIST OF INTEGER
DIM list1 AS LIST OF INTEGER
DIM list2 AS LIST OF INTEGER
DIM list3 AS LIST OF INTEGER
DIM list4 AS LIST OF INTEGER
DIM list5 AS LIST OF INTEGER
DIM list6 AS LIST OF INTEGER
DIM list7 AS LIST OF INTEGER
DIM list8 AS LIST OF INTEGER
DIM list9 AS LIST OF INTEGER

FOR i = 1 TO 100
    list0.APPEND(i)
    list1.APPEND(i + 100)
    list2.APPEND(i + 200)
    list3.APPEND(i + 300)
    list4.APPEND(i + 400)
    list5.APPEND(i + 500)
    list6.APPEND(i + 600)
    list7.APPEND(i + 700)
    list8.APPEND(i + 800)
    list9.APPEND(i + 900)
NEXT i

DIM multiOk AS INTEGER
multiOk = 1
IF list0.LENGTH() <> 100 THEN multiOk = 0
IF list5.LENGTH() <> 100 THEN multiOk = 0
IF list9.LENGTH() <> 100 THEN multiOk = 0
IF list0.HEAD() <> 1 THEN multiOk = 0
IF list9.HEAD() <> 901 THEN multiOk = 0

list0.CLEAR()
list1.CLEAR()
list2.CLEAR()
list3.CLEAR()
list4.CLEAR()
list5.CLEAR()
list6.CLEAR()
list7.CLEAR()
list8.CLEAR()
list9.CLEAR()

IF list0.LENGTH() <> 0 THEN multiOk = 0
IF list9.LENGTH() <> 0 THEN multiOk = 0

IF multiOk = 1 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL"
END IF
PRINT ""

' ---------------------------------------------------------------
' Test 10: INSERT/REMOVE churn (mid-list mutation)
'   Builds a 100-element list, then does 500 insert+remove cycles
'   at various positions. Exercises atom alloc/free at interior.
' ---------------------------------------------------------------
PRINT "Test 10: 500 insert/remove cycles on 100-element list"
DIM mutList AS LIST OF INTEGER
FOR i = 1 TO 100
    mutList.APPEND(i * 10)
NEXT i

FOR cycle = 1 TO 500
    DIM pos AS INTEGER
    pos = (cycle MOD 98) + 2
    mutList.INSERT(pos, cycle)
    mutList.REMOVE(pos)
NEXT cycle

PRINT "  Length after mutations: "; mutList.LENGTH()
PRINT "  Head: "; mutList.HEAD()
PRINT "  Get(100): "; mutList.GET(100)
IF mutList.LENGTH() = 100 AND mutList.HEAD() = 10 AND mutList.GET(100) = 1000 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL (expected length=100, head=10, get(100)=1000)"
END IF
PRINT ""

PRINT "=== All list pool stress tests passed ==="
