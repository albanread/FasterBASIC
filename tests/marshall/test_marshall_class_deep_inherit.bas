' Test: Marshall/Unmarshall inherited CLASS with mixed scalar + string at each level
' Tests that field offsets are computed correctly across the hierarchy
' Expected output:
' Tag: base-tag
' Value: 100
' Label: sub-label
' Score: 200
' Note: leaf-note
' Count: 300

CLASS Base
    Tag AS STRING
    Value AS DOUBLE
END CLASS

CLASS Middle EXTENDS Base
    Label AS STRING
    Score AS DOUBLE
END CLASS

CLASS Leaf EXTENDS Middle
    Note AS STRING
    Count AS DOUBLE
END CLASS

DIM obj AS Leaf = NEW Leaf()
obj.Tag = "base-tag"
obj.Value = 100
obj.Label = "sub-label"
obj.Score = 200
obj.Note = "leaf-note"
obj.Count = 300

DIM blob AS MARSHALLED
blob = MARSHALL(obj)

DIM obj2 AS Leaf = NEW Leaf()
UNMARSHALL obj2, blob

PRINT "Tag: "; obj2.Tag
PRINT "Value: "; obj2.Value
PRINT "Label: "; obj2.Label
PRINT "Score: "; obj2.Score
PRINT "Note: "; obj2.Note
PRINT "Count: "; obj2.Count
