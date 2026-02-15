' Test: MATCH RECEIVE with specific UDT types
' Worker sends two different UDT-typed messages, main dispatches via MATCH RECEIVE
' Expected output:
' Got Point: 10 20
' Got Box: 1 2 100 200
' Done

TYPE Point
    x AS DOUBLE
    y AS DOUBLE
END TYPE

TYPE Box
    lx AS DOUBLE
    ty AS DOUBLE
    w AS DOUBLE
    h AS DOUBLE
END TYPE

WORKER ShapeSender() AS DOUBLE
    DIM p AS Point
    p.x = 10
    p.y = 20
    SEND PARENT, p

    DIM r AS Box
    r.lx = 1
    r.ty = 2
    r.w = 100
    r.h = 200
    SEND PARENT, r

    DIM ret AS DOUBLE = 0.0
    RETURN ret
END WORKER

DIM f AS DOUBLE
f = SPAWN ShapeSender()

DIM count AS INTEGER = 0

WHILE count < 2
    MATCH RECEIVE(f)
        CASE Point pt
            PRINT "Got Point: "; pt.x; " "; pt.y
            count = count + 1
        CASE Box rc
            PRINT "Got Box: "; rc.lx; " "; rc.ty; " "; rc.w; " "; rc.h
            count = count + 1
        CASE ELSE
            PRINT "Unknown message"
            count = count + 1
    END MATCH
WEND

DIM result AS DOUBLE
result = AWAIT f
PRINT "Done"
