' Test program for AST optimization passes
' Run with --verbose to see optimization statistics

' === Optimization 1-2: Constant folding & propagation ===
CONSTANT PI = 3
CONSTANT RADIUS = 10
DIM area AS DOUBLE
area = PI * RADIUS * RADIUS
PRINT "Area: "; area

' === Optimization 3-4: String literal folding & identity ===
DIM greeting AS STRING
greeting = "Hello" + " " + "World"
PRINT greeting

' === Optimization 5: Power strength reduction ===
DIM x AS DOUBLE
x = 7
DIM sq AS DOUBLE
sq = x ^ 2
PRINT "7 squared: "; sq
DIM cb AS DOUBLE
cb = x ^ 3
PRINT "7 cubed: "; cb

' === Optimization 7: Dead branch elimination ===
IF 0 THEN
    PRINT "This should be optimized out"
END IF

IF 1 THEN
    PRINT "This branch is always taken"
END IF

' === Optimization 8: IIF simplification ===
DIM val AS DOUBLE
val = IIF(1, 42, 99)
PRINT "IIF(1,42,99) = "; val

' === Optimization 9: Algebraic identities ===
DIM y AS DOUBLE
y = 5
DIM r1 AS DOUBLE
DIM r2 AS DOUBLE
DIM r3 AS DOUBLE
r1 = y + 0
r2 = y * 1
r3 = y / 1
PRINT "5+0="; r1; " 5*1="; r2; " 5/1="; r3

' === Optimization 10: NOT constant folding ===
DIM notval AS DOUBLE
notval = NOT 0
PRINT "NOT 0 = "; notval

' === Optimization 11: Double negation ===
' --x and NOT NOT x are simplified at AST level

' === Optimization 12: String function folding ===
DIM slen AS DOUBLE
slen = LEN("hello")
PRINT "LEN(hello) = "; slen

DIM asc_val AS DOUBLE
asc_val = ASC("A")
PRINT "ASC(A) = "; asc_val

DIM left_str AS STRING
left_str = LEFT$("Hello", 3)
PRINT "LEFT$(Hello,3) = "; left_str

DIM right_str AS STRING
right_str = RIGHT$("Hello", 2)
PRINT "RIGHT$(Hello,2) = "; right_str

DIM mid_str AS STRING
mid_str = MID$("Hello World", 7, 5)
PRINT "MID$(Hello World,7,5) = "; mid_str

DIM upper_str AS STRING
upper_str = UCASE$("hello")
PRINT "UCASE$(hello) = "; upper_str

DIM lower_str AS STRING
lower_str = LCASE$("HELLO")
PRINT "LCASE$(HELLO) = "; lower_str

DIM trim_str AS STRING
trim_str = TRIM$("  hi  ")
PRINT "TRIM$(  hi  ) = "; trim_str

DIM instr_val AS DOUBLE
instr_val = INSTR("Hello World", "World")
PRINT "INSTR(Hello World, World) = "; instr_val

DIM space_str AS STRING
space_str = SPACE$(5)
PRINT "SPACE$(5) = ["; space_str; "]"

DIM val_num AS DOUBLE
val_num = VAL("42")
PRINT "VAL(42) = "; val_num

' === Optimization 13: Division by constant → multiplication ===
DIM d AS DOUBLE
d = x / 4
PRINT "7/4 = "; d

' === Optimization 14: MOD power-of-2 → AND ===
DIM m AS DOUBLE
m = 15 MOD 8
PRINT "15 MOD 8 = "; m

' === Optimization 15: Dead loop elimination ===
WHILE 0
    PRINT "This loop body should be optimized out"
WEND

' === Optimization 16: Boolean AND/OR identities ===
DIM b1 AS DOUBLE
DIM b2 AS DOUBLE
b1 = y AND 0
b2 = y OR 0
PRINT "5 AND 0 = "; b1; " 5 OR 0 = "; b2

PRINT "All optimization tests complete."
END
