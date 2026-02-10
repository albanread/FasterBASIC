' Test: MARSHALL / UNMARSHALL with CLASS objects across workers
' Expected output:
' Sum: 60

CLASS Vec3
  X AS DOUBLE
  Y AS DOUBLE
  Z AS DOUBLE
END CLASS

WORKER ProcessVec(blob AS MARSHALLED) AS DOUBLE
    DIM v AS Vec3 = NEW Vec3()
    UNMARSHALL v, blob
    DIM total AS DOUBLE
    total = v.X + v.Y + v.Z
    RETURN total
END WORKER

DIM myVec AS Vec3 = NEW Vec3()
myVec.X = 10
myVec.Y = 20
myVec.Z = 30

DIM f AS DOUBLE
f = SPAWN ProcessVec(MARSHALL(myVec))
DIM result AS DOUBLE
result = AWAIT f
PRINT "Sum: "; result
