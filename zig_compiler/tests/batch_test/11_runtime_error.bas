' Test: runtime error (division by zero)
' This should trigger a runtime error and basic_exit(),
' which the batch harness must catch via longjmp.
DIM x AS INTEGER
x = 0
PRINT 10 / x
PRINT "should not reach here"
