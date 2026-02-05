1000 REM GOSUB/RETURN Control Flow Test - Rosetta Code
1010 REM Tests that GOSUB/RETURN works correctly within multiline IF blocks
1020 REM
1030 REM This test validates the fix for a compiler bug where RETURN
1040 REM would incorrectly jump to after END IF instead of continuing
1050 REM execution within the IF block after the GOSUB statement.
1060 REM
1070 REM Regression test for: GOSUB/RETURN in multiline IF blocks
1080
1090 PRINT "=== GOSUB/RETURN Control Flow Test ==="
1100 PRINT ""
1110
1120 REM Test 1: Simple multiline IF with GOSUB
1130 PRINT "Test 1: Multiline IF with GOSUB"
1140 LET test1% = 1
1150 IF test1% = 1 THEN
1160     PRINT "  Before GOSUB"
1170     GOSUB Sub1
1180     PRINT "  After GOSUB"
1190     PRINT "  Still in IF block"
1200 END IF
1210 PRINT "  After END IF"
1220 PRINT ""
1230
1240 REM Test 2: Nested IFs with GOSUB
1250 PRINT "Test 2: Nested IFs with GOSUB"
1260 LET outer% = 1
1270 LET inner% = 1
1280 IF outer% = 1 THEN
1290     PRINT "  In outer IF"
1300     IF inner% = 1 THEN
1310         PRINT "    In inner IF, before GOSUB"
1320         GOSUB Sub2
1330         PRINT "    After GOSUB in inner IF"
1340     END IF
1350     PRINT "  After inner END IF"
1360 END IF
1370 PRINT "  After outer END IF"
1380 PRINT ""
1390
1400 REM Test 3: WHILE loop with GOSUB in multiline IF
1410 PRINT "Test 3: WHILE with GOSUB in multiline IF"
1420 LET counter% = 1
1430 WHILE counter% <= 3
1440     PRINT "  Loop iteration "; counter%
1450     LET oddcheck% = counter% MOD 2
1460     IF oddcheck% = 1 THEN
1470         PRINT "    Before GOSUB (odd number)"
1480         LET value% = counter%
1490         GOSUB Sub3
1500         PRINT "    After GOSUB, result="; result%
1510     END IF
1520     PRINT "  After IF block"
1530     LET counter% = counter% + 1
1540 WEND
1550 PRINT "  After WHILE"
1560 PRINT ""
1570
1580 REM Test 4: Multiple GOSUBs in same IF block
1590 PRINT "Test 4: Multiple GOSUBs in same IF"
1600 LET test4% = 1
1610 IF test4% = 1 THEN
1620     PRINT "  Before first GOSUB"
1630     GOSUB Sub4a
1640     PRINT "  Between GOSUBs, val1="; val1%
1650     GOSUB Sub4b
1660     PRINT "  After second GOSUB, val2="; val2%
1670 END IF
1680 PRINT "  After END IF"
1690 PRINT ""
1700
1710 PRINT "=== All Tests Completed Successfully ==="
1720 END
1730
1740 REM Subroutines
1750 Sub1:
1760     PRINT "    In Sub1"
1770     RETURN
1780
1790 Sub2:
1800     PRINT "      In Sub2"
1810     RETURN
1820
1830 Sub3:
1840     PRINT "      In Sub3, value="; value%
1850     LET result% = value% * 100
1860     RETURN
1870
1880 Sub4a:
1890     PRINT "    In Sub4a"
1900     LET val1% = 42
1910     RETURN
1920
1930 Sub4b:
1940     PRINT "    In Sub4b"
1950     LET val2% = 99
1960     RETURN
