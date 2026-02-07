' === test_samm_string_tracking.bas ===
' Tests that SAMM tracks string descriptors per-scope and cleans them up
' automatically when scopes exit.  Run with SAMM_STATS=1 to verify that
' "Strings tracked" and "Strings cleaned" counters are non-zero and balanced.
'
' Coverage:
'   Test A — String literals and concatenation in a FOR loop (per-iteration cleanup)
'   Test B — String function results (MID$, UCASE$, CHR$, STR$) in a loop
'   Test C — String returned from a FUNCTION (RETAIN to parent scope)
'   Test D — String returned from a METHOD  (RETAIN to parent scope)
'   Test E — Nested scopes with strings (inner scope cleans before outer)
'   Test F — WHILE loop with string assignment
'   Test G — PRINT with string concat in loop

' =========================================================================
' Helper FUNCTION — returns a newly created string (tests SAMM RETAIN)
' =========================================================================
FUNCTION MakeGreeting$(who$)
  DIM prefix AS STRING
  prefix = "Hello, "
  DIM suffix AS STRING
  suffix = "!"
  MakeGreeting$ = prefix + who$ + suffix
END FUNCTION

' =========================================================================
' Helper CLASS — METHOD returns a string (tests METHOD string RETAIN)
' =========================================================================
CLASS Formatter
  Label AS STRING

  CONSTRUCTOR(lbl AS STRING)
    ME.Label = lbl
  END CONSTRUCTOR

  METHOD Format(value AS INTEGER) AS STRING
    DIM result AS STRING
    result = ME.Label + "=" + STR$(value)
    Format = result
  END METHOD

  METHOD Describe() AS STRING
    Describe = "[" + ME.Label + "]"
  END METHOD
END CLASS

' =========================================================================
' Main test program
' =========================================================================
PRINT "=== SAMM String Tracking Tests ==="

' --- Test A: String literals + concatenation in FOR loop ----------------
' Each iteration creates temporaries from the literal, STR$, and concat.
' SAMM loop scope should clean them up per-iteration.
PRINT ""
PRINT "Test A: String concat in FOR loop"
DIM lastA AS STRING
lastA = ""
FOR i% = 1 TO 5
  DIM tmp AS STRING
  tmp = "item_" + STR$(i%)
  lastA = tmp
NEXT i%
PRINT "  Last: "; lastA

' --- Test B: String function results in a loop -------------------------
PRINT ""
PRINT "Test B: String functions in FOR loop"
DIM lastB AS STRING
lastB = ""
FOR j% = 1 TO 3
  DIM s1 AS STRING
  s1 = CHR$(64 + j%)
  DIM s2 AS STRING
  s2 = UCASE$(s1)
  DIM s3 AS STRING
  s3 = MID$("ABCDEF", j%, 2)
  lastB = s2 + "-" + s3
NEXT j%
PRINT "  Last: "; lastB

' --- Test C: String returned from FUNCTION ------------------------------
' MakeGreeting$ creates internal temporaries; the RETURN value must be
' RETAINed to the parent scope so it survives the FUNCTION scope exit.
PRINT ""
PRINT "Test C: String from FUNCTION"
DIM greeting AS STRING
greeting = MakeGreeting$("World")
PRINT "  Result: "; greeting

' --- Test D: String returned from METHOD --------------------------------
PRINT ""
PRINT "Test D: String from METHOD"
DIM fmt AS Formatter = NEW Formatter("count")
DIM fmtResult AS STRING
fmtResult = fmt.Format(42)
PRINT "  Formatted: "; fmtResult
DIM descResult AS STRING
descResult = fmt.Describe()
PRINT "  Described: "; descResult

' --- Test E: Nested scopes with strings ---------------------------------
' Inner FOR creates strings; outer FOR also creates strings.
' Inner strings should be cleaned before outer ones.
PRINT ""
PRINT "Test E: Nested loop string scopes"
DIM outer AS STRING
outer = ""
FOR a% = 1 TO 3
  DIM outerStr AS STRING
  outerStr = "O" + STR$(a%)
  FOR b% = 1 TO 2
    DIM innerStr AS STRING
    innerStr = outerStr + ".I" + STR$(b%)
  NEXT b%
  outer = outerStr
NEXT a%
PRINT "  Last outer: "; outer

' --- Test F: WHILE loop with string assignment --------------------------
' String cleanup happens when the enclosing function/sub scope exits.
PRINT ""
PRINT "Test F: WHILE loop with string"
DIM wStr AS STRING
wStr = ""
DIM wc AS INTEGER
wc = 1
WHILE wc <= 4
  wStr = "w" + STR$(wc)
  wc = wc + 1
WEND
PRINT "  Last: "; wStr

' --- Test G: PRINT with string concat in loop ---------------------------
' String temporaries are cleaned up when the enclosing scope exits.
PRINT ""
PRINT "Test G: PRINT in loop"
FOR p% = 1 TO 3
  PRINT "  p="; p%
NEXT p%

' =========================================================================
PRINT ""
PRINT "All string tracking tests passed!"
END

' EXPECTED OUTPUT:
' === SAMM String Tracking Tests ===
'
' Test A: String concat in FOR loop
'   Last: item_ 5
'
' Test B: String functions in FOR loop
'   Last: C-CD
'
' Test C: String from FUNCTION
'   Result: Hello, World!
'
' Test D: String from METHOD
'   Formatted: count= 42
'   Described: [count]
'
' Test E: Nested loop string scopes
'   Last outer: O 3
'
' Test F: WHILE loop with string
'   Last: w 4
'
' Test G: PRINT in loop
'   p= 1
'   p= 2
'   p= 3
'
' All string tracking tests passed!
