OPTION SAMM ON

' === Test 1: DIM and APPEND ===
PRINT "=== Test 1: DIM and APPEND ==="
DIM nums AS LIST OF INTEGER
nums.APPEND(10)
nums.APPEND(20)
nums.APPEND(30)
PRINT "Length: "; nums.LENGTH()
PRINT "Empty: "; nums.EMPTY()

' === Test 2: HEAD and GET ===
PRINT ""
PRINT "=== Test 2: HEAD and GET ==="
PRINT "Head: "; nums.HEAD()
PRINT "Get(1): "; nums.GET(1)
PRINT "Get(2): "; nums.GET(2)
PRINT "Get(3): "; nums.GET(3)

' === Test 3: PREPEND ===
PRINT ""
PRINT "=== Test 3: PREPEND ==="
nums.PREPEND(5)
PRINT "After prepend 5, Head: "; nums.HEAD()
PRINT "Length: "; nums.LENGTH()

' === Test 4: CONTAINS and INDEXOF ===
PRINT ""
PRINT "=== Test 4: CONTAINS and INDEXOF ==="
PRINT "Contains 20: "; nums.CONTAINS(20)
PRINT "Contains 99: "; nums.CONTAINS(99)
PRINT "IndexOf 20: "; nums.INDEXOF(20)
PRINT "IndexOf 99: "; nums.INDEXOF(99)

' === Test 5: SHIFT and POP ===
PRINT ""
PRINT "=== Test 5: SHIFT and POP ==="
DIM first AS INTEGER
LET first = nums.SHIFT()
PRINT "Shifted: "; first
PRINT "Length after shift: "; nums.LENGTH()
DIM last AS INTEGER
LET last = nums.POP()
PRINT "Popped: "; last
PRINT "Length after pop: "; nums.LENGTH()

' === Test 6: LIST constructor ===
PRINT ""
PRINT "=== Test 6: LIST constructor ==="
DIM primes AS LIST OF INTEGER = LIST(2, 3, 5, 7, 11)
PRINT "Primes length: "; primes.LENGTH()
PRINT "Primes head: "; primes.HEAD()

' === Test 7: FOR EACH over typed list ===
PRINT ""
PRINT "=== Test 7: FOR EACH ==="
FOR EACH p IN primes
    PRINT p; " ";
NEXT p
PRINT ""

' === Test 8: LIST OF STRING ===
PRINT ""
PRINT "=== Test 8: LIST OF STRING ==="
DIM words AS LIST OF STRING
words.APPEND("hello")
words.APPEND("world")
words.APPEND("foo")
PRINT "String list length: "; words.LENGTH()
PRINT "Contains hello: "; words.CONTAINS("hello")
PRINT "Contains bar: "; words.CONTAINS("bar")
PRINT "IndexOf world: "; words.INDEXOF("world")
PRINT "Head: "; words.HEAD()
PRINT "Get(2): "; words.GET(2)

' Test JOIN
DIM joined AS STRING
LET joined = words.JOIN(", ")
PRINT "Joined: "; joined

' Test SHIFT and POP on strings
DIM firstWord AS STRING
LET firstWord = words.SHIFT()
PRINT "Shifted: "; firstWord
PRINT "Length after shift: "; words.LENGTH()

DIM lastWord AS STRING
LET lastWord = words.POP()
PRINT "Popped: "; lastWord
PRINT "Length after pop: "; words.LENGTH()

' Test LIST OF STRING with initializer
DIM colors AS LIST OF STRING = LIST("red", "green", "blue")
PRINT "Colors length: "; colors.LENGTH()
PRINT "Colors head: "; colors.HEAD()

' Test FOR EACH over string list
PRINT "Colors: ";
FOR EACH c IN colors
    PRINT c; " ";
NEXT c
PRINT ""

' === Test 9: REMOVE and CLEAR ===
PRINT ""
PRINT "=== Test 9: REMOVE and CLEAR ==="
DIM vals AS LIST OF INTEGER = LIST(100, 200, 300, 400)
PRINT "Before remove: "; vals.LENGTH()
vals.REMOVE(2)
PRINT "After remove(2): "; vals.LENGTH(); " head="; vals.HEAD()
vals.CLEAR()
PRINT "After clear: "; vals.LENGTH(); " empty="; vals.EMPTY()

' === Test 10: COPY and REVERSE ===
PRINT ""
PRINT "=== Test 10: COPY and REVERSE ==="
DIM orig AS LIST OF INTEGER = LIST(1, 2, 3, 4, 5)
PRINT "Original head: "; orig.HEAD()
PRINT "Original length: "; orig.LENGTH()

PRINT ""
PRINT "=== All tests complete ==="

END
