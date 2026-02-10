' Test program: examine what value a FUNCTION returns when it exits via EXIT FUNCTION
' without an explicit RETURN.
'
' Usage:
'   ./fbc test_exit_function.bas -o test_exit_function
'   ./test_exit_function
'
' This program prints representations of the returned values so you can observe
' whether the implementation returns 0, an empty string, NOTHING, or something else.

PRINT "=== EXIT FUNCTION return-value tests ==="
PRINT

' Integer-typed function with no RETURN (ends with EXIT FUNCTION)
FUNCTION int_no_return() AS INTEGER
  ' do some work (none) then exit the function
  EXIT FUNCTION
END FUNCTION

' String-typed function with no RETURN (ends with EXIT FUNCTION)
FUNCTION str_no_return() AS STRING
  EXIT FUNCTION
END FUNCTION

' Double/float-typed function with no RETURN (ends with EXIT FUNCTION)
FUNCTION dbl_no_return() AS DOUBLE
  EXIT FUNCTION
END FUNCTION

' Function with no explicit return type (implementation-defined)
FUNCTION implicit_no_return()
  EXIT FUNCTION
END FUNCTION

' Helper SUB to print a visible marker around values so emptiness is obvious
SUB show_marker(label$, v$)
  PRINT label$; ": ["; v$; "]"
END SUB

' Main test prints
PRINT "1) Calling integer function (declared AS INTEGER) that uses EXIT FUNCTION:"
PRINT "   Raw print:"
PRINT "   int_no_return() -> ["; int_no_return(); "]"
PRINT "   As numeric comparison (equal to 0?):";
IF int_no_return() = 0 THEN
  PRINT "  YES (== 0)"
ELSE
  PRINT "  NO (<> 0) -> value: "; int_no_return()
END IF
PRINT

PRINT "2) Calling string function (declared AS STRING) that uses EXIT FUNCTION:"
PRINT "   Raw print with markers:"
CALL show_marker("   str_no_return()", str_no_return())
PRINT "   Length of returned string (LEN):"; LEN(str_no_return())
PRINT

PRINT "3) Calling double function (declared AS DOUBLE) that uses EXIT FUNCTION:"
PRINT "   Raw print:"
PRINT "   dbl_no_return() -> ["; dbl_no_return(); "]"
PRINT

PRINT "4) Calling function with no declared return type that uses EXIT FUNCTION:"
PRINT "   Raw print:"
PRINT "   implicit_no_return() -> ["; implicit_no_return(); "]"
PRINT

PRINT "5) Combined diagnostics (string conversions):"
DIM s$ AS STRING
s$ = STR$(int_no_return())
CALL show_marker("   STR$(int_no_return())", s$)
s$ = str_no_return()
CALL show_marker("   str_no_return()", s$)
s$ = STR$(dbl_no_return())
CALL show_marker("   STR$(dbl_no_return())", s$)
s$ = STR$(implicit_no_return())
CALL show_marker("   STR$(implicit_no_return())", s$)
PRINT

PRINT "END OF TEST"
END
