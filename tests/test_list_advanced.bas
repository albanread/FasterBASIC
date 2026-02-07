OPTION SAMM ON

' === Test 1: Nested LIST OF ANY containing sub-lists ===
PRINT "=== Test 1: Nested lists ==="
DIM inner1 AS LIST OF INTEGER = LIST(1, 2, 3)
DIM inner2 AS LIST OF INTEGER = LIST(4, 5, 6)
PRINT "inner1 length: "; inner1.LENGTH()
PRINT "inner2 length: "; inner2.LENGTH()
PRINT "inner1 head: "; inner1.HEAD()
PRINT "inner2 head: "; inner2.HEAD()

' === Test 2: LIST operations chaining ===
PRINT ""
PRINT "=== Test 2: Operations chaining ==="
DIM chain AS LIST OF INTEGER
chain.APPEND(10)
chain.APPEND(20)
chain.APPEND(30)
chain.PREPEND(5)
PRINT "After append+prepend, length: "; chain.LENGTH()
PRINT "Head after prepend: "; chain.HEAD()
PRINT "Get(1): "; chain.GET(1)
PRINT "Get(2): "; chain.GET(2)
PRINT "Get(3): "; chain.GET(3)
PRINT "Get(4): "; chain.GET(4)

' === Test 3: SHIFT and POP exhaustively ===
PRINT ""
PRINT "=== Test 3: SHIFT and POP ==="
DIM sp AS LIST OF INTEGER = LIST(100, 200, 300, 400, 500)
PRINT "Initial length: "; sp.LENGTH()

DIM v1 AS INTEGER
LET v1 = sp.SHIFT()
PRINT "Shifted: "; v1; " length: "; sp.LENGTH()

DIM v2 AS INTEGER
LET v2 = sp.POP()
PRINT "Popped: "; v2; " length: "; sp.LENGTH()

DIM v3 AS INTEGER
LET v3 = sp.SHIFT()
PRINT "Shifted: "; v3; " length: "; sp.LENGTH()

DIM v4 AS INTEGER
LET v4 = sp.POP()
PRINT "Popped: "; v4; " length: "; sp.LENGTH()

PRINT "Remaining head: "; sp.HEAD()

' === Test 4: LIST COPY independence ===
PRINT ""
PRINT "=== Test 4: COPY independence ==="
DIM original AS LIST OF INTEGER = LIST(10, 20, 30)
DIM copied AS LIST OF INTEGER
LET copied = original.COPY()
PRINT "Original length: "; original.LENGTH()
PRINT "Copied length: "; copied.LENGTH()
PRINT "Original head: "; original.HEAD()
PRINT "Copied head: "; copied.HEAD()

' Modify original — copy should be unaffected
original.APPEND(40)
PRINT "After append to original:"
PRINT "Original length: "; original.LENGTH()
PRINT "Copied length: "; copied.LENGTH()

' === Test 5: LIST REVERSE ===
PRINT ""
PRINT "=== Test 5: REVERSE ==="
DIM fwd AS LIST OF INTEGER = LIST(1, 2, 3, 4, 5)
DIM rev AS LIST OF INTEGER
LET rev = fwd.REVERSE()
PRINT "Forward head: "; fwd.HEAD()
PRINT "Reverse head: "; rev.HEAD()
PRINT "Reverse length: "; rev.LENGTH()

' Print reversed list
PRINT "Reversed: ";
FOR EACH r IN rev
    PRINT r; " ";
NEXT r
PRINT ""

' === Test 6: LIST CONTAINS and INDEXOF ===
PRINT ""
PRINT "=== Test 6: CONTAINS and INDEXOF ==="
DIM search AS LIST OF INTEGER = LIST(11, 22, 33, 44, 55)
PRINT "Contains 33: "; search.CONTAINS(33)
PRINT "Contains 99: "; search.CONTAINS(99)
PRINT "IndexOf 44: "; search.INDEXOF(44)
PRINT "IndexOf 11: "; search.INDEXOF(11)
PRINT "IndexOf 99: "; search.INDEXOF(99)

' === Test 7: LIST OF STRING with JOIN ===
PRINT ""
PRINT "=== Test 7: String list JOIN ==="
DIM fruits AS LIST OF STRING = LIST("apple", "banana", "cherry", "date")
DIM joined AS STRING
LET joined = fruits.JOIN(", ")
PRINT "Joined: "; joined

DIM dashed AS STRING
LET dashed = fruits.JOIN("-")
PRINT "Dashed: "; dashed

' === Test 8: INSERT at position ===
PRINT ""
PRINT "=== Test 8: INSERT ==="
DIM ins AS LIST OF INTEGER = LIST(10, 30, 40)
ins.INSERT(2, 20)
PRINT "After insert 20 at pos 2:"
PRINT "Length: "; ins.LENGTH()
FOR EACH x IN ins
    PRINT x; " ";
NEXT x
PRINT ""

' === Test 9: REMOVE at position ===
PRINT ""
PRINT "=== Test 9: REMOVE ==="
DIM remList AS LIST OF INTEGER = LIST(10, 20, 30, 40, 50)
remList.REMOVE(3)
PRINT "After remove at pos 3:"
PRINT "Length: "; remList.LENGTH()
FOR EACH x IN remList
    PRINT x; " ";
NEXT x
PRINT ""

' === Test 10: CLEAR and EMPTY ===
PRINT ""
PRINT "=== Test 10: CLEAR and EMPTY ==="
DIM clr AS LIST OF INTEGER = LIST(1, 2, 3, 4, 5)
PRINT "Before clear - empty: "; clr.EMPTY(); " length: "; clr.LENGTH()
clr.CLEAR()
PRINT "After clear - empty: "; clr.EMPTY(); " length: "; clr.LENGTH()

' Add elements back after clear
clr.APPEND(99)
PRINT "After append - empty: "; clr.EMPTY(); " length: "; clr.LENGTH()
PRINT "Head: "; clr.HEAD()

' === Test 11: FOR EACH with index on typed list ===
PRINT ""
PRINT "=== Test 11: FOR EACH with index ==="
DIM indexed AS LIST OF INTEGER = LIST(100, 200, 300, 400)
FOR EACH elem, idx IN indexed
    PRINT "Index "; idx; ": "; elem
NEXT elem

' === Test 12: Large list stress test ===
PRINT ""
PRINT "=== Test 12: Large list ==="
DIM big AS LIST OF INTEGER
DIM i AS INTEGER
FOR i = 1 TO 100
    big.APPEND(i * i)
NEXT i
PRINT "Large list length: "; big.LENGTH()
PRINT "Head: "; big.HEAD()
PRINT "Get(50): "; big.GET(50)
PRINT "Get(100): "; big.GET(100)
PRINT "Contains 2500: "; big.CONTAINS(2500)
PRINT "Contains 9999: "; big.CONTAINS(9999)

' === Test 13: EXTEND two lists ===
PRINT ""
PRINT "=== Test 13: EXTEND ==="
DIM listA AS LIST OF INTEGER = LIST(1, 2, 3)
DIM listB AS LIST OF INTEGER = LIST(4, 5, 6)
listA.EXTEND(listB)
PRINT "After extend, length: "; listA.LENGTH()
PRINT "Elements: ";
FOR EACH e IN listA
    PRINT e; " ";
NEXT e
PRINT ""
PRINT "listB still intact, length: "; listB.LENGTH()

' === Test 14: LIST OF STRING CONTAINS and INDEXOF ===
PRINT ""
PRINT "=== Test 14: String CONTAINS/INDEXOF ==="
DIM names AS LIST OF STRING = LIST("Alice", "Bob", "Charlie", "Diana")
PRINT "Contains Bob: "; names.CONTAINS("Bob")
PRINT "Contains Eve: "; names.CONTAINS("Eve")
PRINT "IndexOf Charlie: "; names.INDEXOF("Charlie")
PRINT "IndexOf Eve: "; names.INDEXOF("Eve")

' === Test 15: Multiple lists coexisting ===
PRINT ""
PRINT "=== Test 15: Multiple coexisting lists ==="
DIM list1 AS LIST OF INTEGER = LIST(1, 2, 3)
DIM list2 AS LIST OF INTEGER = LIST(10, 20, 30)
DIM list3 AS LIST OF STRING = LIST("x", "y", "z")
PRINT "list1 length: "; list1.LENGTH(); " head: "; list1.HEAD()
PRINT "list2 length: "; list2.LENGTH(); " head: "; list2.HEAD()
PRINT "list3 length: "; list3.LENGTH(); " head: "; list3.HEAD()

PRINT ""
PRINT "=== All advanced list tests complete ==="

END
