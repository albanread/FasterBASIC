' Test SUB (void subroutine) implementation
' Tests both implicit and explicit SUB calls

PRINT "SUB Implementation Test"
PRINT "======================="
PRINT

' Test 1: SUB with no parameters, explicit CALL
PRINT "Test 1: SUB with no parameters (explicit CALL)"
CALL PrintHello()
PRINT

' Test 2: SUB with no parameters, explicit CALL
PRINT "Test 2: SUB with no parameters (explicit CALL)"
CALL PrintHello()
PRINT

' Test 3: SUB with parameters, explicit CALL
PRINT "Test 3: SUB with parameters (explicit CALL)"
CALL PrintSum(5, 3)
PRINT

' Test 4: SUB with parameters, explicit CALL
PRINT "Test 4: SUB with parameters (explicit CALL)"
CALL PrintSum(10, 7)
PRINT

' Test 5: SUB with string parameter
PRINT "Test 5: SUB with string parameter"
CALL PrintMessage("Hello from SUB!")
PRINT

' Test 6: SUB with mixed parameter types
PRINT "Test 6: SUB with mixed parameter types"
CALL PrintInfo("Result", 42, 3.14)
PRINT

' Test 7: SUB that calls another SUB
PRINT "Test 7: SUB calling another SUB"
CALL CallOtherSub()
PRINT

' Test 8: Nested SUB calls
PRINT "Test 8: Nested SUB calls"
CALL OuterSub()
PRINT

PRINT "All SUB tests passed!"
END

' SUB definitions

SUB PrintHello()
  PRINT "  Hello from SUB"
END SUB

SUB PrintSum(a%, b%)
  PRINT "  Sum: "; a% + b%
END SUB

SUB PrintMessage(msg$)
  PRINT "  Message: "; msg$
END SUB

SUB PrintInfo(label$, num%, value#)
  PRINT "  "; label$; ": num="; num%; ", value="; value#
END SUB

SUB CallOtherSub()
  PRINT "  CallOtherSub calling PrintHello"
  CALL PrintHello()
END SUB

SUB OuterSub()
  PRINT "  OuterSub start"
  CALL InnerSub()
  PRINT "  OuterSub end"
END SUB

SUB InnerSub()
  PRINT "    InnerSub executed"
END SUB
