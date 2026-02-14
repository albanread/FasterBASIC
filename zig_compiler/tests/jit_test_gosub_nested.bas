PRINT "start"
GOSUB sub1
PRINT "end"
END

sub1:
PRINT "in sub1"
GOSUB sub2
PRINT "back in sub1"
RETURN

sub2:
PRINT "in sub2"
RETURN
