REM Test SHELL command
REM Tests process execution from FasterBASIC

PRINT "Testing SHELL command..."
PRINT

REM Test 1: Simple echo
PRINT "Test 1: Echo command"
SHELL "echo Hello from SHELL!"
PRINT

REM Test 2: List files
PRINT "Test 2: List current directory"
SHELL "ls -la | head -10"
PRINT

REM Test 3: Date command
PRINT "Test 3: Show date"
SHELL "date"
PRINT

PRINT "SHELL tests complete!"
