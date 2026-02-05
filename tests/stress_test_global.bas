' Stress test: 32 global variables with register pressure
' This tests how globals handle memory access under register pressure

GLOBAL a%, b%, c%, d%, e%, f%, g%, h%
GLOBAL i%, j%, k%, l%, m%, n%, o%, p%
GLOBAL q%, r%, s%, t%, u%, v%, w%, x%
GLOBAL y%, z%, a1%, b1%, c1%, d1%, e1%, f1%

' Initialize all variables
a% = 1: b% = 2: c% = 3: d% = 4
e% = 5: f% = 6: g% = 7: h% = 8
i% = 9: j% = 10: k% = 11: l% = 12
m% = 13: n% = 14: o% = 15: p% = 16
q% = 17: r% = 18: s% = 19: t% = 20
u% = 21: v% = 22: w% = 23: x% = 24
y% = 25: z% = 26: a1% = 27: b1% = 28
c1% = 29: d1% = 30: e1% = 31: f1% = 32

' Perform calculations that use all variables
' This creates high register pressure
a% = a% + b% + c%
b% = b% * 2 + d%
c% = c% + e% - f%
d% = d% + g% + h%
e% = e% * i% + j%
f% = f% + k% - l%
g% = g% + m% + n%
h% = h% + o% * p%

i% = i% + q% + r%
j% = j% + s% - t%
k% = k% * u% + v%
l% = l% + w% + x%
m% = m% + y% - z%
n% = n% + a1% + b1%
o% = o% + c1% * d1%
p% = p% + e1% + f1%

q% = q% + a% + b%
r% = r% * c% + d%
s% = s% + e% - f%
t% = t% + g% + h%
u% = u% + i% * j%
v% = v% + k% + l%
w% = w% - m% + n%
x% = x% + o% + p%

y% = y% + q% + r%
z% = z% * s% + t%
a1% = a1% + u% - v%
b1% = b1% + w% + x%
c1% = c1% + y% * z%
d1% = d1% + a1% + b1%
e1% = e1% - c1% + d1%
f1% = f1% + e1%

' Print some results to prevent dead code elimination
PRINT a%; b%; c%; d%
PRINT e%; f%; g%; h%
PRINT i%; j%; k%; l%
PRINT y%; z%; e1%; f1%

END
