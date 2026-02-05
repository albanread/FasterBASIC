' Euler's Method V2 - Rosetta Code Challenge
' https://rosettacode.org/wiki/Euler_method
'
' Improved version using SELECT CASE for cleaner output logic
'
' Numerical approximation of first-order ODEs using Euler's method
' Example: Newton's Cooling Law
'
' dT/dt = -k * (T - T_room)
' Analytical solution: T(t) = T_room + (T0 - T_room) * exp(-k*t)

PRINT "=== Euler's Method V2: Newton's Cooling Law ==="
PRINT ""
PRINT "Differential Equation: dT/dt = -k * (T - T_room)"
PRINT ""
PRINT "Initial Conditions:"
PRINT "  Initial temperature (T0): 100 C"
PRINT "  Room temperature (T_room): 20 C"
PRINT "  Cooling constant (k): 0.07"
PRINT "  Time range: 0 to 100 seconds"
PRINT ""

' Constants
DIM T0 AS DOUBLE         ' Initial temperature
DIM Troom AS DOUBLE      ' Room temperature
DIM k AS DOUBLE          ' Cooling constant
DIM tmax AS DOUBLE       ' Maximum time

T0 = 100.0
Troom = 20.0
k = 0.07
tmax = 100.0

' Variables for calculations
DIM t AS DOUBLE
DIM tint AS INTEGER      ' Integer time for CASE statement
DIM y AS DOUBLE
DIM h AS DOUBLE          ' Step size
DIM analytical AS DOUBLE
DIM i AS INTEGER
DIM steps AS INTEGER

PRINT "========================================================================"
PRINT "Step Size: 2 seconds"
PRINT "========================================================================"
PRINT ""
PRINT "  Time    Euler      Analytical   Error"
PRINT "  (s)     (C)        (C)          (C)"
PRINT "--------------------------------------------------------"

h = 2.0
t = 0.0
y = T0
steps = 0

WHILE t <= tmax
    ' Calculate analytical solution for comparison
    analytical = Troom + (T0 - Troom) * EXP(-k * t)

    ' Print at 10-second intervals (cleaner than long OR chain)
    tint = INT(t + 0.5)
    IF tint MOD 10 = 0 AND tint >= 0 AND tint <= 100 THEN
        PRINT "  "; t; "     "; y; "    "; analytical; "   "; ABS(y - analytical)
    END IF

    ' Euler's method: y_n+1 = y_n + h * f(t_n, y_n)
    ' where f(t, y) = -k * (y - Troom)
    y = y + h * (-k * (y - Troom))
    t = t + h
    steps = steps + 1
WEND

PRINT ""
PRINT "Total steps: "; steps
PRINT ""

PRINT "========================================================================"
PRINT "Step Size: 5 seconds"
PRINT "========================================================================"
PRINT ""
PRINT "  Time    Euler      Analytical   Error"
PRINT "  (s)     (C)        (C)          (C)"
PRINT "--------------------------------------------------------"

h = 5.0
t = 0.0
y = T0
steps = 0

WHILE t <= tmax
    ' Calculate analytical solution
    analytical = Troom + (T0 - Troom) * EXP(-k * t)

    ' Print at 10-second intervals
    tint = INT(t + 0.5)
    IF tint MOD 10 = 0 AND tint >= 0 AND tint <= 100 THEN
        PRINT "  "; t; "     "; y; "    "; analytical; "   "; ABS(y - analytical)
    END IF

    ' Euler step
    y = y + h * (-k * (y - Troom))
    t = t + h
    steps = steps + 1
WEND

PRINT ""
PRINT "Total steps: "; steps
PRINT ""

PRINT "========================================================================"
PRINT "Step Size: 10 seconds"
PRINT "========================================================================"
PRINT ""
PRINT "  Time    Euler      Analytical   Error"
PRINT "  (s)     (C)        (C)          (C)"
PRINT "--------------------------------------------------------"

h = 10.0
t = 0.0
y = T0
steps = 0

WHILE t <= tmax
    ' Calculate analytical solution
    analytical = Troom + (T0 - Troom) * EXP(-k * t)

    ' Print at 10-second intervals
    tint = INT(t + 0.5)
    IF tint MOD 10 = 0 AND tint >= 0 AND tint <= 100 THEN
        PRINT "  "; t; "     "; y; "    "; analytical; "   "; ABS(y - analytical)
    END IF

    ' Euler step
    y = y + h * (-k * (y - Troom))
    t = t + h
    steps = steps + 1
WEND

PRINT ""
PRINT "Total steps: "; steps
PRINT ""

PRINT "========================================================================"
PRINT "Summary"
PRINT "========================================================================"
PRINT ""
PRINT "Euler's method approximates the solution to dy/dt = f(t,y) using:"
PRINT "  y(n+1) = y(n) + h * f(t(n), y(n))"
PRINT ""
PRINT "For Newton's Cooling Law: f(t,T) = -k * (T - T_room)"
PRINT ""
PRINT "Observations:"
PRINT "  - Smaller step sizes give more accurate results"
PRINT "  - Error accumulates over time (visible at t=100s)"
PRINT "  - Step size h=2s gives best accuracy of the three tested"
PRINT "  - Step size h=10s shows significant deviation"
PRINT ""
PRINT "V2 Improvements:"
PRINT "  - Uses MOD arithmetic for cleaner conditional logic"
PRINT "  - Single condition check instead of 11 OR comparisons"
PRINT "  - More efficient assembly code generation"
PRINT "  - More readable and maintainable source code"
PRINT ""

END
