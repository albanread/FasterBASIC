' === test_option_samm_off.bas ===
' Tests that OPTION SAMM OFF disables all SAMM scope emission.
' The program should run correctly without any samm_init / samm_enter_scope /
' samm_exit_scope / samm_shutdown calls in the generated QBE IL.
'
' Verify with:  ./fbc_qbe test_option_samm_off.bas -i | grep samm
' (should produce NO output when SAMM is OFF)

OPTION SAMM OFF

' --- Simple scalar program ---
DIM x AS INTEGER
x = 42
PRINT "x = "; x

' --- Function call ---
FUNCTION Twice(n AS INTEGER) AS INTEGER
  Twice = n * 2
END FUNCTION

PRINT "Twice(21) = "; Twice(21)

' --- FOR loop with DIM ---
DIM total AS INTEGER
total = 0
FOR i% = 1 TO 5
  DIM sq AS INTEGER
  sq = i% * i%
  total = total + sq
NEXT i%
PRINT "Sum of squares: "; total

' --- WHILE loop ---
DIM count AS INTEGER
count = 3
DIM wsum AS INTEGER
wsum = 0
WHILE count > 0
  wsum = wsum + count
  count = count - 1
WEND
PRINT "While sum: "; wsum

PRINT ""
PRINT "Done!"
END

' EXPECTED OUTPUT:
' x = 42
' Twice(21) = 42
' Sum of squares: 55
' While sum: 6
'
' Done!
