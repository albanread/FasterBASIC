' Test: DIM inside FUNCTION bodies (issue #2)
' This tests that DIM declarations work correctly inside FUNCTION and SUB bodies
' for both built-in types and CLASS instance types.

' ============================================================
' Part A: DIM with built-in types inside FUNCTION
' ============================================================

FUNCTION AddDoubled(x AS INTEGER, y AS INTEGER) AS INTEGER
    DIM temp AS INTEGER
    temp = x * 2
    DIM temp2 AS INTEGER
    temp2 = y * 2
    AddDoubled = temp + temp2
END FUNCTION

PRINT "=== Test A1: DIM INTEGER in FUNCTION ==="
PRINT "AddDoubled(3, 5) = "; STR$(AddDoubled(3, 5))

FUNCTION ConcatWithSep(a AS STRING, b AS STRING, sep AS STRING) AS STRING
    DIM result AS STRING
    result = a + sep + b
    RETURN result
END FUNCTION

PRINT "=== Test A2: DIM STRING in FUNCTION ==="
PRINT ConcatWithSep("Hello", "World", " - ")

FUNCTION SumRange(lo AS INTEGER, hi AS INTEGER) AS INTEGER
    DIM total AS INTEGER
    DIM i AS INTEGER
    total = 0
    FOR i = lo TO hi
        total = total + i
    NEXT i
    SumRange = total
END FUNCTION

PRINT "=== Test A3: DIM with FOR loop in FUNCTION ==="
PRINT "SumRange(1,10) = "; STR$(SumRange(1, 10))

' ============================================================
' Part B: DIM with CLASS types inside FUNCTION (factory pattern)
' ============================================================

CLASS Widget
    Label AS STRING
    Value AS INTEGER

    CONSTRUCTOR()
        ME.Label = "default"
        ME.Value = 0
    END CONSTRUCTOR

    METHOD Info() AS STRING
        RETURN ME.Label + "=" + STR$(ME.Value)
    END METHOD
END CLASS

' Factory using DIM for local CLASS variable
FUNCTION MakeWidget(lbl AS STRING, v AS INTEGER) AS Widget
    DIM w AS Widget = NEW Widget()
    w.Label = lbl
    w.Value = v
    MakeWidget = w
END FUNCTION

PRINT "=== Test B1: DIM CLASS in factory FUNCTION ==="
DIM w1 AS Widget = MakeWidget("alpha", 42)
PRINT w1.Info()
PRINT w1.Label
PRINT STR$(w1.Value)

' Factory with local manipulation before return
FUNCTION MakeDoubledWidget(lbl AS STRING, v AS INTEGER) AS Widget
    DIM temp AS Widget = NEW Widget()
    temp.Label = lbl
    temp.Value = v * 2
    MakeDoubledWidget = temp
END FUNCTION

PRINT "=== Test B2: DIM CLASS with local manipulation ==="
DIM w2 AS Widget = MakeDoubledWidget("beta", 25)
PRINT w2.Info()
PRINT STR$(w2.Value)

' ============================================================
' Part C: DIM inside SUB bodies
' ============================================================

SUB PrintSum(p AS INTEGER, q AS INTEGER)
    DIM s AS INTEGER
    s = p + q
    PRINT "Sum = "; STR$(s)
END SUB

PRINT "=== Test C1: DIM in SUB ==="
CALL PrintSum(7, 8)

SUB GreetAll(name1 AS STRING, name2 AS STRING)
    DIM greeting AS STRING
    greeting = "Hello, " + name1 + " and " + name2 + "!"
    PRINT greeting
END SUB

PRINT "=== Test C2: DIM STRING in SUB ==="
CALL GreetAll("Alice", "Bob")

' ============================================================
' Part D: Multiple DIM in same FUNCTION
' ============================================================

FUNCTION MultiDim(x AS INTEGER) AS INTEGER
    DIM a AS INTEGER
    DIM b AS INTEGER
    DIM c AS INTEGER
    a = x + 1
    b = a * 2
    c = b - 3
    MultiDim = c
END FUNCTION

PRINT "=== Test D1: Multiple DIM in FUNCTION ==="
PRINT "MultiDim(10) = "; STR$(MultiDim(10))

' ============================================================
' Part E: DIM CLASS in SUB (operate on local object)
' ============================================================

SUB PrintWidgetInfo(lbl AS STRING, v AS INTEGER)
    DIM local_w AS Widget = NEW Widget()
    local_w.Label = lbl
    local_w.Value = v
    PRINT local_w.Info()
END SUB

PRINT "=== Test E1: DIM CLASS in SUB ==="
CALL PrintWidgetInfo("gamma", 99)

PRINT "=== All DIM-in-function tests passed ==="
