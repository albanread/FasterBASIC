' Minimal test for EXIT FUNCTION when function is declared AS INTEGER
'
' Usage:
'   ./fbc test_exit_min_int.bas -o test_exit_min_int
'   ./test_exit_min_int
'
' Expectation: observe what integer value is returned when the function
' exits via EXIT FUNCTION without an explicit RETURN statement.

FUNCTION no_return_int() AS INTEGER
  ' Immediately exit the function without returning a value
  EXIT FUNCTION
END FUNCTION

PRINT "Returned value (raw):"; no_return_int()

' Also test comparison to 0 to make emptiness obvious
IF no_return_int() = 0 THEN
  PRINT "Comparison: returned value == 0"
ELSE
  PRINT "Comparison: returned value <> 0"
END IF

END
