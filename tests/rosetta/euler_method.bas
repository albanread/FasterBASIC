' Euler's Method - Rosetta Code Challenge
' https://rosettacode.org/wiki/Euler_method
'
' Numerical approximation of first-order ODEs using Euler's method
' Example: Newton's Cooling Law
'
' dT/dt = -k * (T - T_room)
' Analytical solution: T(t) = T_room + (T0 - T_room) * exp(-k*t)

PRINT "=== Euler's Method: Newton's Cooling Law ==="
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

    ' Print results at specific time points
    IF t = 0.0 OR t = 10.0 OR t = 20.0 OR t = 30.0 OR t = 40.0 OR t = 50.0 OR t = 60.0 OR t = 70.0 OR t = 80.0 OR t = 90.0 OR t = 100.0 THEN
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

    ' Print at specific times
    IF t = 0.0 OR t = 10.0 OR t = 20.0 OR t = 30.0 OR t = 40.0 OR t = 50.0 OR t = 60.0 OR t = 70.0 OR t = 80.0 OR t = 90.0 OR t = 100.0 THEN
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

    ' Print at specific times
    IF t = 0.0 OR t = 10.0 OR t = 20.0 OR t = 30.0 OR t = 40.0 OR t = 50.0 OR t = 60.0 OR t = 70.0 OR t = 80.0 OR t = 90.0 OR t = 100.0 THEN
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
PRINT "The analytical solution T(t) = T_room + (T0 - T_room) * exp(-k*t)"
PRINT "provides the exact values for comparison."
PRINT ""

END
