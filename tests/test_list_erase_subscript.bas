OPTION SAMM ON

' === Test 1: LIST subscript sugar (myList(n) -> .GET(n)) ===
PRINT "=== Test 1: Subscript sugar ==="
DIM nums AS LIST OF INTEGER = LIST(10, 20, 30, 40, 50)
PRINT "nums(1): "; nums(1)
PRINT "nums(2): "; nums(2)
PRINT "nums(3): "; nums(3)
PRINT "nums(4): "; nums(4)
PRINT "nums(5): "; nums(5)
PRINT "Length: "; nums.LENGTH()

' === Test 2: Subscript sugar with string list ===
PRINT ""
PRINT "=== Test 2: String list subscript ==="
DIM words AS LIST OF STRING = LIST("alpha", "beta", "gamma")
PRINT "words(1): "; words(1)
PRINT "words(2): "; words(2)
PRINT "words(3): "; words(3)

' === Test 3: Subscript sugar with expression index ===
PRINT ""
PRINT "=== Test 3: Expression index ==="
DIM vals AS LIST OF INTEGER = LIST(100, 200, 300)
DIM idx AS INTEGER
LET idx = 2
PRINT "vals(idx): "; vals(idx)
PRINT "vals(1+1): "; vals(1 + 1)

' === Test 4: ERASE on LIST ===
PRINT ""
PRINT "=== Test 4: ERASE LIST ==="
DIM myList AS LIST OF INTEGER = LIST(5, 10, 15, 20)
PRINT "Before ERASE length: "; myList.LENGTH()
ERASE myList
PRINT "After ERASE completed"

' === Test 5: ERASE on LIST OF STRING ===
PRINT ""
PRINT "=== Test 5: ERASE string LIST ==="
DIM strList AS LIST OF STRING = LIST("hello", "world", "foo")
PRINT "Before ERASE length: "; strList.LENGTH()
ERASE strList
PRINT "After ERASE completed"

' === Test 6: Create new list after ERASE ===
PRINT ""
PRINT "=== Test 6: Reuse after ERASE ==="
DIM reuse AS LIST OF INTEGER = LIST(1, 2, 3)
PRINT "Before ERASE: "; reuse.LENGTH()
ERASE reuse
PRINT "After ERASE"
' Allocate a fresh list to the same variable
DIM reuse AS LIST OF INTEGER
reuse.APPEND(77)
reuse.APPEND(88)
PRINT "After re-create length: "; reuse.LENGTH()
PRINT "reuse(1): "; reuse(1)
PRINT "reuse(2): "; reuse(2)

' === Test 7: Subscript in expressions ===
PRINT ""
PRINT "=== Test 7: Subscript in expressions ==="
DIM a AS LIST OF INTEGER = LIST(3, 7, 11)
DIM sum AS INTEGER
LET sum = a(1) + a(2) + a(3)
PRINT "Sum of elements: "; sum

' === Test 8: Subscript with FOR loop index ===
PRINT ""
PRINT "=== Test 8: Subscript with loop ==="
DIM items AS LIST OF INTEGER = LIST(2, 4, 6, 8, 10)
DIM i AS INTEGER
FOR i = 1 TO items.LENGTH()
    PRINT "items("; i; "): "; items(i)
NEXT i

PRINT ""
PRINT "=== All ERASE and subscript tests complete ==="

END
