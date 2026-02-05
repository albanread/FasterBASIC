' Simple comparison: 4 global variables
' Purpose: Compare assembly output for local vs global variables

GLOBAL a%, b%, c%, d%

a% = 10
b% = 20
c% = 30
d% = 40

' Perform some calculations
a% = a% + b%
c% = c% * 2
d% = d% + c%

' Use result to prevent optimization
PRINT a%; c%; d%

END
