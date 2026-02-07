OPTION SAMM ON

PRINT "=== Minimal LIST OF INTEGER test ==="

DIM nums AS LIST OF INTEGER
nums.APPEND(10)
nums.APPEND(20)
nums.APPEND(30)
PRINT "Length: "; nums.LENGTH()
PRINT "Head: "; nums.HEAD()

PRINT "=== Done ==="
END
