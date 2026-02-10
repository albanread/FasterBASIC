REM Test SLURP and SPIT functions
REM SLURP reads entire file into string
REM SPIT writes entire string to file

PRINT "Testing SLURP and SPIT..."
PRINT

REM Test 1: Create a file with SPIT
PRINT "Test 1: Writing file with SPIT"
testfile$ = "test_slurp_output.txt"
content$ = "Hello, World!" + CHR$(10) + "This is line 2." + CHR$(10) + "Line 3 here!"
SPIT testfile$, content$
PRINT "Written to "; testfile$
PRINT

REM Test 2: Read it back with SLURP
PRINT "Test 2: Reading file with SLURP"
result$ = SLURP(testfile$)
PRINT "Read from file:"
PRINT result$
PRINT

REM Test 3: Verify content matches
PRINT "Test 3: Verify content"
IF result$ = content$ THEN
    PRINT "SUCCESS: Content matches!"
ELSE
    PRINT "ERROR: Content mismatch"
    PRINT "Expected length: "; LEN(content$)
    PRINT "Actual length: "; LEN(result$)
ENDIF
PRINT

REM Test 4: Write multiline content
PRINT "Test 4: Multiline content"
poem$ = "Roses are red," + CHR$(10) + "Violets are blue," + CHR$(10) + "FasterBASIC is great," + CHR$(10) + "And so are you!"
SPIT "test_poem.txt", poem$
poem_read$ = SLURP("test_poem.txt")
PRINT "Poem from file:"
PRINT poem_read$
PRINT

REM Test 5: Empty file
PRINT "Test 5: Empty file"
SPIT "test_empty.txt", ""
empty$ = SLURP("test_empty.txt")
IF LEN(empty$) = 0 THEN
    PRINT "SUCCESS: Empty file handled correctly"
ELSE
    PRINT "ERROR: Empty file has length "; LEN(empty$)
ENDIF
PRINT

REM Test 6: Large content (useful for real editor scenarios)
PRINT "Test 6: Larger content"
large$ = ""
FOR i = 1 TO 10
    large$ = large$ + "Line " + STR$(i) + " of test data" + CHR$(10)
NEXT i
SPIT "test_large.txt", large$
large_read$ = SLURP("test_large.txt")
IF large_read$ = large$ THEN
    PRINT "SUCCESS: Large content matches ("; LEN(large$); " bytes)"
ELSE
    PRINT "ERROR: Large content mismatch"
ENDIF
PRINT

PRINT "All SLURP/SPIT tests complete!"
