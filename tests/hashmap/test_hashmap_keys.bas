REM Test: Hashmap with Special Keys
REM Tests: Various key types including special characters

DIM dict AS HASHMAP

REM Test simple keys
dict("a") = "value_a"
dict("z") = "value_z"

REM Test keys with numbers
dict("key1") = "first"
dict("key2") = "second"

REM Test keys with spaces
dict("hello world") = "space_key"
dict("first name") = "John"

REM Test keys with special characters
dict("user@domain") = "email"
dict("file.txt") = "filename"
dict("path/to/file") = "filepath"
dict("key-dash") = "dashed"
dict("key_under") = "underscored"

REM Test numeric string keys
dict("0") = "zero"
dict("1") = "one"
dict("42") = "answer"

REM Verify simple keys
IF dict("a") <> "value_a" THEN
    PRINT "ERROR: simple key 'a' failed"
    END
ENDIF

IF dict("z") <> "value_z" THEN
    PRINT "ERROR: simple key 'z' failed"
    END
ENDIF

REM Verify numeric keys
IF dict("key1") <> "first" THEN
    PRINT "ERROR: numeric suffix key failed"
    END
ENDIF

REM Verify space keys
IF dict("hello world") <> "space_key" THEN
    PRINT "ERROR: space key failed"
    END
ENDIF

IF dict("first name") <> "John" THEN
    PRINT "ERROR: space key 'first name' failed"
    END
ENDIF

REM Verify special character keys
IF dict("user@domain") <> "email" THEN
    PRINT "ERROR: @ key failed"
    END
ENDIF

IF dict("file.txt") <> "filename" THEN
    PRINT "ERROR: dot key failed"
    END
ENDIF

IF dict("path/to/file") <> "filepath" THEN
    PRINT "ERROR: slash key failed"
    END
ENDIF

IF dict("key-dash") <> "dashed" THEN
    PRINT "ERROR: dash key failed"
    END
ENDIF

IF dict("key_under") <> "underscored" THEN
    PRINT "ERROR: underscore key failed"
    END
ENDIF

REM Verify numeric string keys
IF dict("0") <> "zero" THEN
    PRINT "ERROR: numeric string '0' failed"
    END
ENDIF

IF dict("42") <> "answer" THEN
    PRINT "ERROR: numeric string '42' failed"
    END
ENDIF

REM Test that similar keys are distinct
dict("test") = "one"
dict("test1") = "two"
dict("test2") = "three"

IF dict("test") <> "one" THEN
    PRINT "ERROR: similar key 'test' failed"
    END
ENDIF

IF dict("test1") <> "two" THEN
    PRINT "ERROR: similar key 'test1' failed"
    END
ENDIF

IF dict("test2") <> "three" THEN
    PRINT "ERROR: similar key 'test2' failed"
    END
ENDIF

PRINT "PASS: Hashmap handles various key types correctly"

END
