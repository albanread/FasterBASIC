' === test_class_p1_minimal.bas ===
' Phase 1 Test: Minimal CLASS with fields, no constructor
' Validates: CLASS declaration, field declaration, NEW, field read/write

CLASS Point
  X AS INTEGER
  Y AS INTEGER
END CLASS

DIM p AS Point = NEW Point()
p.X = 10
p.Y = 20
PRINT p.X; ","; p.Y

' Test default field values (calloc zeroes everything)
DIM q AS Point = NEW Point()
PRINT q.X; ","; q.Y

END

' EXPECTED OUTPUT:
' 10,20
' 0,0
