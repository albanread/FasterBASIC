REM Test arrays and hashmaps in the same program
DIM numbers(5) AS INTEGER
DIM lookup AS HASHMAP

REM Fill array
numbers(0) = 100
numbers(1) = 200
numbers(2) = 300

REM Fill hashmap
lookup("one") = "first"
lookup("two") = "second"
lookup("three") = "third"

PRINT "Array values:"
PRINT numbers(0)
PRINT numbers(1)
PRINT numbers(2)

PRINT ""
PRINT "Hashmap values:"
PRINT lookup("one")
PRINT lookup("two")
PRINT lookup("three")

REM Access them interleaved
PRINT ""
PRINT "Mixed access:"
PRINT "Array[0] = "; numbers(0)
PRINT "Lookup['one'] = "; lookup("one")
PRINT "Array[1] = "; numbers(1)
PRINT "Lookup['two'] = "; lookup("two")

END
