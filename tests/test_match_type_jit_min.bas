OPTION SAMM ON

DIM items AS LIST OF ANY = LIST(42, "hello", 3.14)

FOR EACH E IN items
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Dbl: "; f#
    END MATCH
NEXT E

END
