TYPE Inner
  Value AS INTEGER
END TYPE
TYPE Outer
  Item AS Inner
END TYPE
DIM O AS Outer
PRINT "Size test: ";
REM Just print something to see if it compiles
PRINT "Done"
END
