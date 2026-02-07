# FasterBASIC Language Grammar (BNF)

## Overview

This document provides a comprehensive Backus-Naur Form (BNF) description of the FasterBASIC language as implemented in the compiler. The grammar is based on analysis of the lexer, parser, AST, and test files in the codebase.

## Notation

- `::=` means "is defined as"
- `|` means "or" (alternative)
- `[ ]` means optional (zero or one occurrence)
- `{ }` means repetition (zero or more occurrences)
- `( )` means grouping
- `<name>` represents a non-terminal symbol
- `NAME` represents a terminal symbol (token)
- `'text'` represents literal text

## Lexical Elements

### Tokens

```bnf
<program> ::= { <program-line> }

<program-line> ::= [ <line-number> ] <statement-list> <EOL>
                 | <EOL>

<line-number> ::= INTEGER

<statement-list> ::= <statement> { ':' <statement> }

<EOL> ::= END_OF_LINE | END_OF_FILE
```

## Literals

```bnf
<number> ::= INTEGER | FLOAT | DOUBLE | HEX_NUMBER

<integer> ::= DIGIT { DIGIT }

<float> ::= DIGIT { DIGIT } '.' { DIGIT } [ <exponent> ]
          | DIGIT { DIGIT } <exponent>

<exponent> ::= ( 'E' | 'e' ) [ '+' | '-' ] DIGIT { DIGIT }

<hex-number> ::= '&H' HEX_DIGIT { HEX_DIGIT }
               | '0x' HEX_DIGIT { HEX_DIGIT }

<string> ::= '"' { <string-char> } '"'

<string-char> ::= <any-char-except-quote-or-backslash>
                | '\"'
                | '\n'
                | '\t'
                | '\r'
                | '\\'
```

## Identifiers and Type Suffixes

```bnf
<identifier> ::= LETTER { LETTER | DIGIT | '_' } [ <type-suffix> ]

<type-suffix> ::= '%'    -- INTEGER
                | '&'    -- LONG
                | '!'    -- SINGLE/FLOAT
                | '#'    -- DOUBLE
                | '$'    -- STRING
                | '@'    -- BYTE
                | '^'    -- SHORT

<type-keyword> ::= 'AS' <type-name>

<type-name> ::= 'INTEGER' | 'INT'
              | 'LONG'
              | 'SINGLE' | 'FLOAT'
              | 'DOUBLE'
              | 'STRING'
              | 'BYTE'
              | 'SHORT'
              | 'UBYTE'
              | 'USHORT'
              | 'UINTEGER' | 'UINT'
              | 'ULONG'
              | <user-defined-type-name>
```

## Statements

```bnf
<statement> ::= <print-statement>
              | <console-statement>
              | <input-statement>
              | <let-statement>
              | <assignment-statement>
              | <dim-statement>
              | <redim-statement>
              | <erase-statement>
              | <goto-statement>
              | <gosub-statement>
              | <return-statement>
              | <on-statement>
              | <if-statement>
              | <select-case-statement>
              | <for-statement>
              | <for-in-statement>
              | <next-statement>
              | <while-statement>
              | <wend-statement>
              | <repeat-statement>
              | <until-statement>
              | <do-statement>
              | <loop-statement>
              | <exit-statement>
              | <try-catch-statement>
              | <throw-statement>
              | <sub-statement>
              | <function-statement>
              | <class-declaration>
              | <match-type-statement>
              | <call-statement>
              | <def-statement>
              | <swap-statement>
              | <inc-statement>
              | <dec-statement>
              | <type-declaration-statement>
              | <local-statement>
              | <global-statement>
              | <shared-statement>
              | <data-statement>
              | <read-statement>
              | <restore-statement>
              | <constant-statement>
              | <open-statement>
              | <close-statement>
              | <option-statement>
              | <graphics-statement>
              | <timer-statement>
              | <rem-statement>
              | <end-statement>
```

### Class and Object System

```bnf
<class-declaration> ::= 'CLASS' <identifier> [ 'EXTENDS' <identifier> ] <EOL>
                        { <class-member> }
                        'END' 'CLASS' <EOL>

<class-member> ::= <field-declaration>
                 | <method-declaration>
                 | <constructor-declaration>
                 | <destructor-declaration>
                 | <rem-statement>
                 | <statement-list>

<field-declaration> ::= <identifier> 'AS' <type-name> <EOL>

<constructor-declaration> ::= 'CONSTRUCTOR' [ '(' <parameter-list> ')' ] <EOL>
                              { <statement> }
                              'END' 'CONSTRUCTOR' <EOL>

<destructor-declaration> ::= 'DESTRUCTOR' <EOL>
                             { <statement> }
                             'END' 'DESTRUCTOR' <EOL>

<method-declaration> ::= 'METHOD' <identifier> [ '(' <parameter-list> ')' ] [ 'AS' <type-name> ] <EOL>
                         { <statement> }
                         'END' 'METHOD' <EOL>
```

### Pattern Matching

```bnf
<match-type-statement> ::= 'MATCH' 'TYPE' <expression> <EOL>
                           { <case-type-block> }
                           [ 'CASE' 'ELSE' <EOL> { <statement> } ]
                           ( 'END' 'MATCH' | 'ENDMATCH' )

<case-type-block> ::= 'CASE' <type-name> <identifier> <EOL>
                      { <statement> }
```

### Print and Console Statements

```bnf
<print-statement> ::= ( 'PRINT' | '?' ) [ <print-list> ]
                    | 'PRINT' '#' <file-number> ',' [ <print-list> ]
                    | 'PRINT' 'USING' <format-string> ';' <expression-list>

<console-statement> ::= 'CONSOLE' [ <print-list> ]

<print-list> ::= <print-item> { <print-separator> <print-item> } [ <print-separator> ]

<print-item> ::= <expression>

<print-separator> ::= ';' | ','
             | <identifier> [ <type-keyword> ] '=' <expression>

<dimension-list> ::= <expression> { ',' <expression> }

<type-keyword> ::= 'AS' <type-name>
                 | 'AS' 'LIST' [ 'OF' <type-name> ]
                 | 'AS' 'HASHMAP'expression> [ ',' <expression> ',' <expression> ] ',' <print-list>
```

### Input Statements

```bnf
<input-statement> ::= 'INPUT' [ <prompt-string> ';' ] <variable-list>
                    | 'INPUT' '#' <file-number> ',' <variable-list>
                    | 'LINE' 'INPUT' [ <prompt-string> ';' ] <variable>

<input-at-statement> ::= 'INPUT_AT' <expression> ',' <expression> [ ',' <expression> ',' <expression> ] ',' [ <prompt-string> ';' ] <variable>

<prompt-string> ::= <string>

<variable-list> ::= <variable> { ',' <variable> }
```

### Assignment Statements

```bnf
<let-statement> ::= [ 'LET' ] <variable> '=' <expression>
                  | [ 'LET' ] <array-access> '=' <expression>
                  | [ 'LET' ] <member-access> '=' <expression>

<assignment-statement> ::= <variable> '=' <expression>

<mid-assign-statement> ::= 'MID' '$' '(' <variable> ',' <expression> [ ',' <expression> ] ')' '=' <expression>

<slice-assign-statement> ::= <variable> '[' <expression> ':' <expression> ']' '=' <expression>
```

### Variable Declaration Statements

```bnf
<dim-statement> ::= 'DIM' <dim-list>

<dim-list> ::= <dim-item> { ',' <dim-item> }

<dim-item> ::= <identifier> '(' <dimension-list> ')' [ <type-keyword> ]
             | <identifier> [ <type-keyword> ]

<dimension-list> ::= <expression> { ',' <expression> }

<redim-statement> ::= 'REDIM' [ 'PRESERVE' ] <dim-list>

<erase-statement> ::= 'ERASE' <identifier> { ',' <identifier> }

<local-statement> ::= 'LOCAL' <local-list>

<local-list> ::= <local-item> { ',' <local-item> }

<local-item> ::= <identifier> [ <type-keyword> ] [ '=' <expression> ]

<global-statement> ::= 'GLOBAL' <global-list>

<global-list> ::= <global-item> { ',' <global-item> }

<global-item> ::= <identifier> [ <type-keyword> ] [ '=' <expression> ]

<shared-statement> ::= 'SHARED' <variable-list>

<constant-statement> ::= 'CONSTANT' <identifier> '=' <expression>
```

### Control Flow Statements

```bnf
<goto-statement> ::= 'GOTO' ( <line-number> | <label> )

<gosub-statement> ::= 'GOSUB' ( <line-number> | <label> )

<return-statement> ::= 'RETURN' [ <expression> ]

<on-statement> ::= 'ON' <expression> ( 'GOTO' | 'GOSUB' | 'CALL' ) <target-list>

<on-event-statement> ::= 'ONEVENT' <event-name> ( 'GOTO' | 'GOSUB' | 'CALL' ) <target>

<target-list> ::= <target> { ',' <target> }

<target> ::= <line-number> | <label> | <identifier>

<label> ::= <identifier> ':'
```

### Conditional Statements

```bnf
<if-statement> ::= <single-line-if>
                 | <multi-line-if>

<single-line-if> ::= 'IF' <expression> 'THEN' <statement> [ 'ELSE' <statement> ]
                   | 'IF' <expression> 'GOTO' <line-number>

<multi-line-if> ::= 'IF' <expression> 'THEN' <EOL>
                    { <statement> }
                    { <elseif-clause> }
                    [ <else-clause> ]
                    'ENDIF' | 'END' 'IF'

<elseif-clause> ::= 'ELSEIF' <expression> 'THEN' <EOL>
                    { <statement> }

<else-clause> ::= 'ELSE' <EOL>
                  { <statement> }

<select-case-statement> ::= 'SELECT' 'CASE' <expression> <EOL>
                            { <case-clause> }
                            [ <case-otherwise-clause> ]
                            'ENDCASE' | 'END' 'CASE'

<case-clause> ::= 'CASE' <case-condition-list> <EOL>
                  { <statement> }

<case-condition-list> ::= <case-condition> { ',' <case-condition> }

<case-condition> ::= <expression>
                   | 'IS' <comparison-op> <expression>
                   | <expression> 'TO' <expression>

<case-otherwise-clause> ::= 'OTHERWISE' <EOL>
                            { <statement> }
```

### Loop Statements

```bnf
<for-statement> ::= 'FOR' <identifier> '=' <expression> 'TO' <expression> [ 'STEP' <expression> ] <EOL>
                    { <statement> }
                    'NEXT' [ <identifier> ]

<for-in-statement> ::= 'FOR' 'EACH' <identifier> 'IN' <expression> <EOL>
                       { <statement> }
                       'NEXT' [ <identifier> ]

<next-statement> ::= 'NEXT' [ <identifier> ]

<while-statement> ::= 'WHILE' <expression> <EOL>
                      { <statement> }
                      ( 'WEND' | 'ENDWHILE' )

<wend-statement> ::= 'WEND' | 'ENDWHILE'

<repeat-statement> ::= 'REPEAT' <EOL>
                       { <statement> }
                       'UNTIL' <expression>

<until-statement> ::= 'UNTIL' <expression>

<do-statement> ::= 'DO' [ 'WHILE' <expression> | 'UNTIL' <expression> ] <EOL>
                   { <statement> }
                   'LOOP' [ 'WHILE' <expression> | 'UNTIL' <expression> ]

<loop-statement> ::= 'LOOP' [ 'WHILE' <expression> | 'UNTIL' <expression> ]

<exit-statement> ::= 'EXIT' ( 'FOR' | 'DO' | 'WHILE' | 'REPEAT' | 'FUNCTION' | 'SUB' )
```

### Exception Handling Statements

```bnf
<try-catch-statement> ::= 'TRY' <EOL>
                          { <statement> }
                          { <catch-clause> }
                          [ <finally-clause> ]
                          'END' 'TRY'

<catch-clause> ::= 'CATCH' <error-code-list> <EOL>
                   { <statement> }

<error-code-list> ::= <integer> { ',' <integer> }

<finally-clause> ::= 'FINALLY' <EOL>
                     { <statement> }

<throw-statement> ::= 'THROW' <expression>
```

### Subroutine and Function Statements

```bnf
<sub-statement> ::= 'SUB' <identifier> [ '(' <parameter-list> ')' ] <EOL>
                    { <statement> }
                    ( 'END' 'SUB' | 'ENDSUB' )

<function-statement> ::= 'FUNCTION' <identifier> [ '(' <parameter-list> ')' ] [ <type-keyword> ] <EOL>
                         { <statement> }
                         ( 'END' 'FUNCTION' | 'ENDFUNCTION' )

<parameter-list> ::= <parameter> { ',' <parameter> }

<parameter> ::= [ 'BYVAL' | 'BYREF' ] <identifier> [ <type-keyword> ]

<call-statement> ::= 'CALL' <identifier> [ '(' <argument-list> ')' ]
                   | <identifier> [ '(' <argument-list> ')' ]

<def-statement> ::= 'DEF' 'FN' <identifier> [ '(' <parameter-list> ')' ] '=' <expression>
```

### Data Statements

```bnf
<data-statement> ::= 'DATA' <data-list>

<data-list> ::= <data-item> { ',' <data-item> }

<data-item> ::= <literal> | <identifier>

<read-statement> ::= 'READ' <variable-list>

<restore-statement> ::= 'RESTORE' [ <line-number> | <label> ]
```

### Type Declaration Statements

```bnf
<type-declaration-statement> ::= 'TYPE' <identifier> <EOL>
                                 { <type-field> }
                                 ( 'END' 'TYPE' | 'ENDTYPE' )

<type-field> ::= <identifier> 'AS' <type-name> <EOL>
```

### Utility Statements

```bnf
<swap-statement> ::= 'SWAP' <variable> ',' <variable>

<inc-statement> ::= 'INC' <variable> [ ',' <expression> ]

<dec-statement> ::= 'DEC' <variable> [ ',' <expression> ]

<rem-statement> ::= ( 'REM' | "'" ) <comment-text>

<end-statement> ::= 'END'
```

### File I/O Statements

```bnf
<open-statement> ::= 'OPEN' <string> 'FOR' <mode> 'AS' '#' <file-number>

<mode> ::= 'INPUT' | 'OUTPUT' | 'APPEND' | 'BINARY'

<close-statement> ::= 'CLOSE' [ '#' <file-number> ]

<file-number> ::= <expression>
```

### Graphics Statements

```bnf
<graphics-statement> ::= <cls-statement>
                       | <gcls-statement>
                       | <color-statement>
                       | <pset-statement>
                       | <line-statement>
                       | <rect-statement>
                       | <circle-statement>
                       | <circlef-statement>
                       | <hline-statement>
                       | <vline-statement>

<cls-statement> ::= 'CLS' [ <expression> ]

<gcls-statement> ::= ( 'GCLS' | 'CLG' ) [ <expression> ]

<color-statement> ::= 'COLOR' <expression> [ ',' <expression> ]

<pset-statement> ::= 'PSET' '(' <expression> ',' <expression> ')' [ ',' <expression> ]

<line-statement> ::= 'LINE' '(' <expression> ',' <expression> ')' '-' '(' <expression> ',' <expression> ')' [ ',' <expression> ]

<rect-statement> ::= 'RECT' <expression> ',' <expression> ',' <expression> ',' <expression> [ ',' <expression> ]
                   | 'RECTF' <expression> ',' <expression> ',' <expression> ',' <expression> [ ',' <expression> ]

<circle-statement> ::= 'CIRCLE' <expression> ',' <expression> ',' <expression> [ ',' <expression> ]
                     | 'CIRCLEF' <expression> ',' <expression> ',' <expression> [ ',' <expression> ]

<hline-statement> ::= 'HLINE' <expression> ',' <expression> ',' <expression> [ ',' <expression> ]

<vline-statement> ::= 'VLINE' <expression> ',' <expression> ',' <expression> [ ',' <expression> ]
```

### Text Layer Statements

```bnf
<at-statement> ::= ( 'AT' | 'LOCATE' ) <expression> ',' <expression>

<textput-statement> ::= ( 'TEXTPUT' | 'TEXT_PUT' ) <expression> ',' <expression> ',' <string> [ ',' <expression> ',' <expression> ]

<tchar-statement> ::= ( 'TCHAR' | 'TEXT_PUTCHAR' ) <expression> ',' <expression> ',' <expression> [ ',' <expression> ',' <expression> ]

<tgrid-statement> ::= 'TGRID' <expression> ',' <expression>

<tscroll-statement> ::= ( 'TSCROLL' | 'TEXT_SCROLL' ) <expression>

<tclear-statement> ::= ( 'TCLEAR' | 'TEXT_CLEAR' ) <expression> ',' <expression> ',' <expression> ',' <expression>
```

### Sprite Statements

```bnf
<sprite-statement> ::= <sprload-statement>
                     | <sprfree-statement>
                     | <sprshow-statement>
                     | <sprhide-statement>
                     | <sprmove-statement>
                     | <sprpos-statement>
                     | <sprtint-statement>
                     | <sprscale-statement>
                     | <sprrot-statement>
                     | <sprexplode-statement>

<sprload-statement> ::= 'SPRLOAD' <expression> ',' <string>

<sprfree-statement> ::= 'SPRFREE' <expression>

<sprshow-statement> ::= 'SPRSHOW' <expression>

<sprhide-statement> ::= 'SPRHIDE' <expression>

<sprmove-statement> ::= 'SPRMOVE' <expression> ',' <expression> ',' <expression>

<sprpos-statement> ::= 'SPRPOS' <expression> ',' <expression> ',' <expression> [ ',' <expression> ',' <expression> ',' <expression> ]

<sprtint-statement> ::= 'SPRTINT' <expression> ',' <expression>

<sprscale-statement> ::= 'SPRSCALE' <expression> ',' <expression> [ ',' <expression> ]

<sprrot-statement> ::= 'SPRROT' <expression> ',' <expression>

<sprexplode-statement> ::= 'SPREXPLODE' <expression> ',' <expression> ',' <expression>
```

### Timer and Event Statements

```bnf
<timer-statement> ::= <after-statement>
                    | <every-statement>
                    | <afterframes-statement>
                    | <everyframe-statement>
                    | <timer-stop-statement>
                    | <run-statement>
                    | <vsync-statement>
                    | <wait-statement>

<after-statement> ::= 'AFTER' <expression> <time-unit> ( 'GOTO' | 'GOSUB' | 'CALL' ) <target>
                    | 'AFTER' <expression> <time-unit> 'DO' <EOL> { <statement> } 'DONE'

<every-statement> ::= 'EVERY' <expression> <time-unit> ( 'GOTO' | 'GOSUB' | 'CALL' ) <target>
                    | 'EVERY' <expression> <time-unit> 'DO' <EOL> { <statement> } 'DONE'

<time-unit> ::= 'MS' | 'SECS' | 'FRAMES'

<afterframes-statement> ::= 'AFTERFRAMES' <expression> ( 'GOTO' | 'GOSUB' | 'CALL' ) <target>

<everyframe-statement> ::= 'EVERYFRAME' <expression> ( 'GOTO' | 'GOSUB' | 'CALL' ) <target>

<timer-stop-statement> ::= 'TIMER' 'STOP' [ <target> ]

<run-statement> ::= 'RUN' [ 'UNTIL' <expression> ]

<vsync-statement> ::= 'VSYNC' [ <expression> ]

<wait-statement> ::= 'WAIT' [ <expression> ]
                   | 'WAIT_MS' <expression>
```

### Audio Statements

```bnf
<play-statement> ::= 'PLAY' <string> [ ',' <string> ]

<play-sound-statement> ::= 'PLAY_SOUND' <expression> [ ',' <expression> ]
```

### Compiler Directives

```bnf
<option-statement> ::= 'OPTION' <option-type>

<option-type> ::= 'BITWISE'
                | 'LOGICAL'
                | 'BASE' <integer>
                | 'EXPLICIT'
                | 'UNICODE'
                | 'ASCII'
                | 'DETECTSTRING'
                | 'ERROR' ( 'ON' | 'OFF' )
                | 'INCLUDE' <string>
                | 'ONCE'
                | 'CANCELLABLE' ( 'ON' | 'OFF' )
                | 'BOUNDS_CHECK' ( 'ON' | 'OFF' )
                | 'FORCE_YIELD' ( 'ON' | 'OFF' )
```

## Expressions

```bnf
<expression> ::= <logical-imp-expr>

<logical-imp-expr> ::= <logical-eqv-expr> { 'IMP' <logical-eqv-expr> }

<logical-eqv-expr> ::= <logical-or-expr> { 'EQV' <logical-or-expr> }

<logical-or-expr> ::= <logical-xor-expr> { 'OR' <logical-xor-expr> }

<logical-xor-expr> ::= <logical-and-expr> { 'XOR' <logical-and-expr> }

<logical-and-expr> ::= <logical-not-expr> { 'AND' <logical-not-expr> }

<logical-not-expr> ::= 'NOT' <logical-not-expr>
                     | <comparison-expr>

<comparison-expr> ::= <additive-expr> [ <comparison-op> <additive-expr> ]

<comparison-op> ::= '=' | '<>' | '!=' | '<' | '<=' | '>' | '>='

<additive-expr> ::= <multiplicative-expr> { ( '+' | '-' ) <multiplicative-expr> }

<multiplicative-expr> ::= <unary-expr> { ( '*' | '/' | '\' | 'MOD' ) <unary-expr> }

<unary-expr> ::= ( '+' | '-' ) <unary-expr>
               | <power-expr>

<power-expr> ::= <postfix-expr> { '^' <postfix-expr> }

<postfix-expr> ::= <primary-expr> { <postfix-operator> }

<postfix-operator> ::= '(' <argument-list> ')'
                     | '(' <expression-list> ')'
                     | '.' <identifier>
                     | '[' <expression> ':' <expression> ']'

<primary-expr> ::= <number>
                 | <string>
                 | <variable>
                 | <array-access>
                 | <function-call>
                 | <member-access>
                 | <iif-expression>
                 | '(' <expression> ')'
                 | <builtin-function>

<variable> ::= <identifier>

<array-access> ::= <identifier> '(' <expression-list> ')'

<member-access> ::= <primary-expr> '.' <identifier>

<function-call> ::= <identifier> '(' [ <argument-list> ] ')'
                  | 'FN' <identifier> '(' [ <argument-list> ] ')'

<iif-expression> ::= 'IIF' '(' <expression> ',' <expression> ',' <expression> ')'

<argument-list> ::= <expression> { ',' <expression> }

<expression-list> ::= <expression> { ',' <expression> }
```

## Built-in Functions

```bnf
<builtin-function> ::= <math-function>
                     | <string-function>
                     | <type-function>
                     | <system-function>

<math-function> ::= 'ABS' '(' <expression> ')'
                  | 'SGN' '(' <expression> ')'
                  | 'INT' '(' <expression> ')'
                  | 'FIX' '(' <expression> ')'
                  | 'SQR' '(' <expression> ')'
                  | 'SIN' '(' <expression> ')'
                  | 'COS' '(' <expression> ')'
                  | 'TAN' '(' <expression> ')'
                  | 'ATN' '(' <expression> ')'
                  | 'EXP' '(' <expression> ')'
                  | 'LOG' '(' <expression> ')'
                  | 'RND' [ '(' <expression> ')' ]

<string-function> ::= 'LEN' '(' <expression> ')'
                    | 'LEFT' '$' '(' <expression> ',' <expression> ')'
                    | 'RIGHT' '$' '(' <expression> ',' <expression> ')'
                    | 'MID' '$' '(' <expression> ',' <expression> [ ',' <expression> ] ')'
                    | 'INSTR' '(' [ <expression> ',' ] <expression> ',' <expression> ')'
                    | 'CHR' '$' '(' <expression> ')'
                    | 'ASC' '(' <expression> ')'
                    | 'STR' '$' '(' <expression> ')'
                    | 'VAL' '(' <expression> ')'
                    | 'UCASE' '$' '(' <expression> ')'
                    | 'LCASE' '$' '(' <expression> ')'
                    | 'LTRIM' '$' '(' <expression> ')'
                    | 'RTRIM' '$' '(' <expression> ')'
                    | 'TRIM' '$' '(' <expression> ')'

<type-function> ::= 'CINT' '(' <expression> ')'
                  | 'CLNG' '(' <expression> ')'
                  | 'CSNG' '(' <expression> ')'
                  | 'CDBL' '(' <expression> ')'
                  | 'CSTR' '(' <expression> ')'

<system-function> ::= 'ERR' '(' ')'
                    | 'ERL' '(' ')'
                    | 'TIMER' '(' ')'
                    | 'EOF' '(' <file-number> ')'
                    | 'LOF' '(' <file-number> ')'
```

## Operator Precedence

From highest to lowest precedence:

1. Function calls, array subscripts, member access: `()`, `[]`, `.`
2. Exponentiation: `^`
3. Unary plus and minus: `+`, `-`
4. Multiplication, division, integer division, modulo: `*`, `/`, `\`, `MOD`
5. Addition, subtraction: `+`, `-`
6. Comparison operators: `=`, `<>`, `!=`, `<`, `<=`, `>`, `>=`
7. Logical NOT: `NOT`
8. Logical AND: `AND`
9. Logical XOR: `XOR`
10. Logical OR: `OR`
11. Logical EQV: `EQV`
12. Logical IMP: `IMP`

## Type System

### Primitive Types

- `INTEGER` (`%`) - 32-bit signed integer
- `LONG` (`&`) - 64-bit signed integer
- `SINGLE` (`!`) - 32-bit floating point
- `DOUBLE` (`#`) - 64-bit floating point
- `STRING` (`$`) - String (ASCII or Unicode)
- `BYTE` (`@`) - 8-bit unsigned integer
- `SHORT` (`^`) - 16-bit signed integer
- `UBYTE` - 8-bit unsigned integer
- `USHORT` - 16-bit unsigned integer
- `UINTEGER` - 32-bit unsigned integer
- `ULONG` - 64-bit unsigned integer

### User-Defined Types

```bnf
TYPE typename
  field1 AS type1
  field2 AS type2
  ...
END TYPE
```

### Arrays

- Single-dimensional: `DIM arr%(10)`
- Multi-dimensional: `DIM arr%(10, 20, 30)`
- Dynamic arrays: `REDIM arr%(newsize)`
- Array preservation: `REDIM PRESERVE arr%(newsize)`

### Type Inference

Variables can have their type:
1. Explicitly declared with type suffix: `x%`, `name$`
2. Explicitly declared with AS keyword: `DIM x AS INTEGER`
3. Implicitly inferred from first use (if OPTION EXPLICIT is not set)

## Special Features

### Exception Handling

FasterBASIC supports structured exception handling with `TRY`/`CATCH`/`FINALLY` blocks:

```basic
TRY
  ' code that might throw
CATCH errorcode1, errorcode2
  ' handle specific errors
CATCH errorcode3
  ' handle another error
FINALLY
  ' cleanup code (always executed)
END TRY
```

### Timer Events

Supports both time-based and frame-based timer events:

- `AFTER duration MS/SECS/FRAMES` - one-shot timer
- `EVERY duration MS/SECS/FRAMES` - repeating timer
- `AFTERFRAMES count` - frame-based one-shot
- `EVERYFRAME count` - frame-based repeating

### Inline Event Handlers

```basic
EVERY 1000 MS DO
  PRINT "Tick"
DONE
```

### Select Case Variants

```basic
SELECT CASE expression
  CASE value1
    ' statements
  CASE IS > value2
    ' statements
  CASE value3 TO value4
    ' statements
  OTHERWISE
    ' default case
ENDCASE
```

### String Slicing

```basic
s$ = "Hello World"
sub$ = s$[0:5]        ' "Hello"
s$[6:11] = "BASIC"    ' "Hello BASIC"
```

### Array Operations

```basic
' Element-wise operations
result() = array1() + array2()
result() = array1() * scalar
```

### User-Defined Functions

```basic
' DEF FN style (single-line)
DEF FN Square(x) = x * x

' FUNCTION...END FUNCTION style (multi-line)
FUNCTION Calculate(a%, b%) AS INTEGER
  LOCAL result%
  result% = a% * b% + 10
  RETURN result%
END FUNCTION
```

## Compiler Options

- `OPTION BITWISE` - AND/OR/NOT are bitwise
- `OPTION LOGICAL` - AND/OR/NOT are logical (default)
- `OPTION BASE 0|1` - Array base index
- `OPTION EXPLICIT` - All variables must be declared
- `OPTION UNICODE` - String literals are Unicode (UTF-32)
- `OPTION ASCII` - String literals are ASCII (default)
- `OPTION DETECTSTRING` - Automatically detect string literal encoding
- `OPTION ERROR ON|OFF` - Enable/disable line number tracking
- `OPTION CANCELLABLE ON|OFF` - Enable/disable loop cancellation
- `OPTION BOUNDS_CHECK ON|OFF` - Enable/disable array bounds checking
- `OPTION FORCE_YIELD ON|OFF` - Force quasi-preemptive multitasking
- `OPTION INCLUDE "filename"` - Include another source file
- `OPTION ONCE` - Include file only once (header guard)

## Comments

```bnf
<comment> ::= 'REM' <comment-text>
            | "'" <comment-text>
```

## Line Numbers

Line numbers are optional and can be intermixed with unnumbered lines:

```basic
10 PRINT "Line 10"
PRINT "Unnumbered line"
20 PRINT "Line 20"
```

## Statement Separators

Multiple statements can be placed on one line using colon (`:`) separator:

```basic
X = 5 : Y = 10 : PRINT X + Y
```

## Notes

1. **Case Insensitivity**: Keywords are case-insensitive (PRINT = print = Print)
2. **Implicit LET**: The LET keyword is optional for assignments
3. **Line Continuation**: Not supported (statements must fit on one line unless part of multi-line structure)
4. **String Type Detection**: OPTION DETECTSTRING automatically detects if string literals contain non-ASCII characters
5. **Registry-Based Commands**: The language supports modular command registration for extensibility
6. **Graphics and Multimedia**: Built-in support for graphics primitives, sprites, text layers, and audio
7. **Event-Driven Programming**: Native support for timer events and event loops with `RUN`

## Grammar Extensions

The grammar includes several extensions beyond traditional BASIC:

- Exception handling (TRY/CATCH/FINALLY)
- User-defined types (TYPE...END TYPE)
- String slicing with `[start:end]` syntax
- IIF() immediate if expressions
- FOR EACH...IN loops
- DO...LOOP with flexible WHILE/UNTIL positioning
- CALL statement for subroutines
- BYREF/BYVAL parameter passing
- LOCAL/GLOBAL/SHARED variable scoping
- Timer and event system
- Graphics and sprite system
- Modular command registry for extensibility

## Implementation Notes

The FasterBASIC compiler uses:

1. **Lexer**: Hand-written lexer for tokenization
2. **Parser**: Recursive descent parser with operator precedence climbing
3. **AST**: Full abstract syntax tree representation
4. **CFG**: Control Flow Graph for optimization
5. **Backend**: QBE (Quick Backend) for code generation
6. **Runtime**: Hybrid C/C++ runtime with optional Lua integration
7. **Targets**: AMD64, ARM64, RISC-V (RV64) architectures