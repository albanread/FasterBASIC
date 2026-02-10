REM Test command-line argument support
REM Usage: ./test_command_args arg1 arg2 arg3

PRINT "Command-line Arguments Test"
PRINT "============================"
PRINT

REM Get number of arguments (includes program name)
arg_count = COMMANDCOUNT
PRINT "Total arguments (including program name): "; arg_count
PRINT

REM Print all arguments
IF arg_count > 0 THEN
    PRINT "Arguments:"
    FOR i = 0 TO arg_count - 1
        PRINT "  ["; i; "] = "; COMMAND(i)
    NEXT i
ELSE
    PRINT "No arguments"
ENDIF
PRINT

REM Check if any arguments were provided (beyond program name)
IF arg_count > 1 THEN
    PRINT "First user argument: "; COMMAND(1)
    PRINT "Number of user arguments: "; arg_count - 1
ELSE
    PRINT "No user arguments provided"
    PRINT "Try running: ./test_command_args hello world test"
ENDIF
