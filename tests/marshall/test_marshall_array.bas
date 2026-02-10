' Test: Marshall/Unmarshall an array of doubles
' Expected output:
' Element 0: 10
' Element 1: 20
' Element 2: 30
' Element 3: 40
' Element 4: 50

DIM arr(4) AS DOUBLE
arr(0) = 10
arr(1) = 20
arr(2) = 30
arr(3) = 40
arr(4) = 50

DIM blob AS MARSHALLED
blob = MARSHALL(arr)

DIM arr2(4) AS DOUBLE
UNMARSHALL arr2, blob

DIM i AS DOUBLE
FOR i = 0 TO 4
    PRINT "Element "; i; ": "; arr2(i)
NEXT i
