DIM result AS INTEGER
result = 0
GOSUB AddTen
GOSUB AddTen
GOSUB AddTen
PRINT "result: "; result
END

AddTen:
    result = result + 10
RETURN
