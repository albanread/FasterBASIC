REM Demonstration of UDT (User-Defined Type) Support

TYPE Rectangle
  Width AS INTEGER
  Height AS INTEGER
  Area AS LONG
END TYPE

DIM R AS Rectangle

PRINT "=== UDT Member Access Demo ==="
PRINT ""

PRINT "Setting rectangle dimensions:"
R.Width = 25
R.Height = 40

PRINT "  Width  = "; R.Width
PRINT "  Height = "; R.Height

R.Area = R.Width * R.Height
PRINT "  Area   = "; R.Area

PRINT ""
PRINT "Testing with different values:"
R.Width = 100
R.Height = 50
PRINT "  New Width  = "; R.Width
PRINT "  New Height = "; R.Height
R.Area = R.Width * R.Height  
PRINT "  New Area   = "; R.Area

PRINT ""
PRINT "Demo complete!"
END
