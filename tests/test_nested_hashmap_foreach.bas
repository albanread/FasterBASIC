10 REM Test: Nested FOR EACH hashmap inside regular FOR loop
20 REM Minimal reproduction to isolate QBE assertion issue

100 PRINT "=== Nested hashmap in FOR loop ==="
110 DIM lookup AS HASHMAP
120 lookup("cat") = "meow"
130 lookup("dog") = "woof"
140 DIM outerCount AS INTEGER
150 DIM innerCount AS INTEGER
160 outerCount = 0
170 innerCount = 0
180 FOR i = 1 TO 3
190   outerCount = outerCount + 1
200   FOR EACH lk IN lookup
210     innerCount = innerCount + 1
220   NEXT
230 NEXT i
240 PRINT "Outer = "; outerCount; ", Inner = "; innerCount
250 IF outerCount = 3 AND innerCount = 6 THEN PRINT "PASS" ELSE PRINT "FAIL"
260 END
