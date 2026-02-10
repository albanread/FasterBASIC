REM Hello World Example
REM A simple program to test BASED editor

PRINT "Hello, World!"
PRINT
PRINT "Welcome to FasterBASIC!"
PRINT "This is a simple example program."
PRINT
INPUT "What is your name"; name$
PRINT "Hello, "; name$; "!"
PRINT
PRINT "Press any key to exit..."
DIM dummy AS INTEGER
dummy = KBGET()
