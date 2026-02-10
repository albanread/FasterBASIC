' Test: Marshall/Unmarshall preserves empty strings
' Expected output:
' Name length: 0
' Value: 42
' Name is empty: yes

CLASS OptionalName
    Name AS STRING
    Value AS DOUBLE
END CLASS

DIM obj AS OptionalName = NEW OptionalName()
obj.Value = 42

DIM blob AS MARSHALLED
blob = MARSHALL(obj)

DIM obj2 AS OptionalName = NEW OptionalName()
UNMARSHALL obj2, blob

DIM slen AS DOUBLE
slen = LEN(obj2.Name)
PRINT "Name length: "; slen
PRINT "Value: "; obj2.Value
IF slen = 0 THEN
    PRINT "Name is empty: yes"
ELSE
    PRINT "Name is empty: no"
END IF
