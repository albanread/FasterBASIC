OPTION SAMM ON

PRINT "=== Minimal LIST OF STRING test ==="

DIM words AS LIST OF STRING
words.APPEND("hello")
words.APPEND("world")
PRINT "Length: "; words.LENGTH()
PRINT "Head: "; words.HEAD()

PRINT "=== Done ==="
END
