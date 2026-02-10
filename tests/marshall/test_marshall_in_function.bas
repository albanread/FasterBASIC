' Test: Marshall/Unmarshall inside a SUB (not just main scope)
' Expected output:
' Cloned: Original Data
' Score: 99

TYPE Record
    Info AS STRING
    Score AS DOUBLE
END TYPE

DIM result AS Record

SUB CloneRecord(r AS Record)
    DIM blob AS MARSHALLED
    blob = MARSHALL(r)
    UNMARSHALL result, blob
END SUB

DIM r AS Record
r.Info = "Original Data"
r.Score = 99

CloneRecord(r)

PRINT "Cloned: "; result.Info
PRINT "Score: "; result.Score
