' Test: MARSHALL / UNMARSHALL with CLASS objects (constructor + return)
' Worker receives a class object, computes stats, returns result as marshalled class
' Expected output:
' Min: 5
' Max: 30
' Total: 60

CLASS Stats
  MinVal AS DOUBLE
  MaxVal AS DOUBLE
  Total AS DOUBLE
END CLASS

CLASS DataPoint
  A AS DOUBLE
  B AS DOUBLE
  C AS DOUBLE
  D AS DOUBLE
END CLASS

WORKER Analyze(blob AS MARSHALLED) AS MARSHALLED
    DIM dp AS DataPoint = NEW DataPoint()
    UNMARSHALL dp, blob

    DIM s AS Stats = NEW Stats()
    s.MinVal = dp.A
    s.MaxVal = dp.A
    s.Total = 0

    IF dp.A < s.MinVal THEN s.MinVal = dp.A
    IF dp.A > s.MaxVal THEN s.MaxVal = dp.A
    s.Total = s.Total + dp.A

    IF dp.B < s.MinVal THEN s.MinVal = dp.B
    IF dp.B > s.MaxVal THEN s.MaxVal = dp.B
    s.Total = s.Total + dp.B

    IF dp.C < s.MinVal THEN s.MinVal = dp.C
    IF dp.C > s.MaxVal THEN s.MaxVal = dp.C
    s.Total = s.Total + dp.C

    IF dp.D < s.MinVal THEN s.MinVal = dp.D
    IF dp.D > s.MaxVal THEN s.MaxVal = dp.D
    s.Total = s.Total + dp.D

    RETURN MARSHALL(s)
END WORKER

DIM d AS DataPoint = NEW DataPoint()
d.A = 10
d.B = 5
d.C = 15
d.D = 30

DIM f AS MARSHALLED
f = SPAWN Analyze(MARSHALL(d))
DIM answer AS MARSHALLED
answer = AWAIT f

DIM result AS Stats = NEW Stats()
UNMARSHALL result, answer
PRINT "Min: "; result.MinVal
PRINT "Max: "; result.MaxVal
PRINT "Total: "; result.Total
