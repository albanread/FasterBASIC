REM Isolated Test 4: Special Characters in Keys
REM This test reproduces the hang from the comprehensive test

PRINT "Test 4: Special Key Characters"
PRINT "==============================="

DIM special AS HASHMAP

special("user@domain.com") = "email"
special("file.txt") = "filename"
special("path/to/file") = "filepath"
special("key-with-dashes") = "dashed"
special("key_with_underscore") = "underscored"
special("key with spaces") = "spaced"
special("123") = "numeric"
special("!@#$%") = "symbols"

IF special("user@domain.com") <> "email" THEN
    PRINT "ERROR: Email-like key failed"
    END
ENDIF

IF special("key with spaces") <> "spaced" THEN
    PRINT "ERROR: Space key failed"
    END
ENDIF

IF special("123") <> "numeric" THEN
    PRINT "ERROR: Numeric string key failed"
    END
ENDIF

PRINT "✓ Special characters in keys work"

END
