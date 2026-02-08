//
// fasterbasic_token.h
// FasterBASIC - Token Definitions
//
// Defines all token types for lexical analysis of BASIC programs.
// Each token has a type, value, and source location for error reporting.
//

#ifndef FASTERBASIC_TOKEN_H
#define FASTERBASIC_TOKEN_H

#include <string>
#include <ostream>
#include <sstream>

namespace FasterBASIC {

// =============================================================================
// Token Types
// =============================================================================

enum class TokenType {
    // End of input
    END_OF_FILE,
    END_OF_LINE,
    
    // Literals
    NUMBER,          // 123, 3.14, 1.5e10
    STRING,          // "Hello World"
    
    // Identifiers and Keywords
    IDENTIFIER,      // Variable names: A, X1, MyVar, etc.
    
    // Keywords - Control Flow
    PRINT,           // PRINT
    CONSOLE,         // CONSOLE (print to console)
    INPUT,           // INPUT
    LET,             // LET (optional in assignments)
    GOTO,            // GOTO
    GOSUB,           // GOSUB
    RETURN,          // RETURN
    IF,              // IF
    THEN,            // THEN
    ELSE,            // ELSE
    ELSEIF,          // ELSEIF
    ENDIF,           // ENDIF (if we support it)
    FOR,             // FOR
    EACH,            // EACH (for FOR EACH...IN loops)
    TO,              // TO
    STEP,            // STEP
    IN,              // IN (for FOR...IN loops)
    NEXT,            // NEXT
    WHILE,           // WHILE
    WEND,            // WEND
    REPEAT,          // REPEAT
    UNTIL,           // UNTIL
    DO,              // DO
    LOOP,            // LOOP
    DONE,            // DONE (for inline timer handlers)
    END,             // END
    EXIT,            // EXIT (EXIT FOR, EXIT FUNCTION, EXIT SUB)
    CASE,            // CASE
    SELECT,          // SELECT
    OF,              // OF
    WHEN,            // WHEN
    IS,              // IS
    OTHERWISE,       // OTHERWISE
    ENDCASE,         // ENDCASE
    MATCH,           // MATCH (for MATCH TYPE statement)
    ENDMATCH,        // END MATCH
    
    // Keywords - Exception Handling
    TRY,             // TRY (begin exception handling block)
    CATCH,           // CATCH (catch exceptions by error code)
    FINALLY,         // FINALLY (always executed cleanup block)
    THROW,           // THROW (throw exception with error code)
    ERR,             // ERR (get current error code)
    ERL,             // ERL (get error line number)
    
    // Keywords - Compiler Directives
    OPTION,          // OPTION
    BITWISE,         // BITWISE (for OPTION BITWISE)
    LOGICAL,         // LOGICAL (for OPTION LOGICAL)
    BASE,            // BASE (for OPTION BASE)
    EXPLICIT,        // EXPLICIT (for OPTION EXPLICIT)
    UNICODE,         // UNICODE (for OPTION UNICODE)
    ASCII,           // ASCII (for OPTION ASCII)
    DETECTSTRING,    // DETECTSTRING (for OPTION DETECTSTRING)
    ERROR,           // ERROR (for OPTION ERROR - line tracking)
    INCLUDE,         // INCLUDE (file inclusion)
    ONCE,            // ONCE (for OPTION ONCE)
    CANCELLABLE,     // CANCELLABLE (for OPTION CANCELLABLE - loop cancellation)
    BOUNDS_CHECK,    // BOUNDS_CHECK (for OPTION BOUNDS_CHECK - array bounds checking)
    FORCE_YIELD,     // FORCE_YIELD (for OPTION FORCE_YIELD - quasi-preemptive handlers)
    SAMM,            // SAMM (for OPTION SAMM ON/OFF - scope-aware memory management)
    NEON,            // NEON (for OPTION NEON ON/OFF - NEON SIMD acceleration)
    
    // Keywords - Functions and Procedures
    SUB,             // SUB
    FUNCTION,        // FUNCTION
    ENDSUB,          // END SUB
    ENDFUNCTION,     // END FUNCTION
    CALL,            // CALL
    LOCAL,           // LOCAL
    GLOBAL,          // GLOBAL (for global variables accessible via SHARED)
    SHARED,          // SHARED (for shared variables in SUBs)
    BYREF,           // BYREF (pass by reference)
    BYVAL,           // BYVAL (pass by value)
    AS,              // AS (type declarations)
    DEF,             // DEF
    FN,              // FN
    IIF,             // IIF (Immediate IF - inline conditional expression)
    MID,             // MID (substring function)
    LEFT,            // LEFT (left substring)
    RIGHT,           // RIGHT (right substring)
    ON,              // ON (for ON GOTO/GOSUB/CALL)
    ONEVENT,         // ONEVENT (for ONEVENT eventname GOTO/GOSUB/CALL)
    OFF,             // OFF (for OPTION CANCELLABLE OFF)
    
    // Type names (for AS declarations)
    KEYWORD_INTEGER,    // INTEGER (for AS declarations)
    KEYWORD_DOUBLE,     // DOUBLE (for AS declarations)
    KEYWORD_SINGLE,     // SINGLE (for AS declarations)
    KEYWORD_STRING,     // STRING (for AS declarations)
    KEYWORD_LONG,       // LONG (for AS declarations)
    KEYWORD_BYTE,       // BYTE (for AS declarations)
    KEYWORD_SHORT,      // SHORT (for AS declarations)
    KEYWORD_UBYTE,      // UBYTE (for AS declarations)
    KEYWORD_USHORT,     // USHORT (for AS declarations)
    KEYWORD_UINTEGER,   // UINTEGER (for AS declarations)
    KEYWORD_ULONG,      // ULONG (for AS declarations)
    KEYWORD_HASHMAP,    // HASHMAP (for AS declarations - dictionary/map type)
    KEYWORD_LIST,       // LIST (for AS declarations - linked list type)
    
    // Keywords - Data
    DIM,             // DIM
    REDIM,           // REDIM (resize array)
    ERASE,           // ERASE (clear/deallocate array)
    PRESERVE,        // PRESERVE (for REDIM PRESERVE)
    SWAP,            // SWAP (swap two variables)
    INC,             // INC (increment variable)
    DEC,             // DEC (decrement variable)
    DATA,            // DATA
    READ,            // READ
    RESTORE,         // RESTORE
    CONSTANT,        // CONSTANT (for constant definitions)
    TYPE,            // TYPE (user-defined type declaration)
    ENDTYPE,         // END TYPE (end user-defined type)
    
    // Keywords - CLASS & Object System
    CLASS,           // CLASS (class declaration)
    EXTENDS,         // EXTENDS (single inheritance)
    CONSTRUCTOR,     // CONSTRUCTOR (class constructor)
    DESTRUCTOR,      // DESTRUCTOR (class destructor)
    METHOD,          // METHOD (class method)
    ME,              // ME (current object reference inside METHOD/CONSTRUCTOR)
    SUPER,           // SUPER (parent class reference)
    NEW,             // NEW (object instantiation - heap allocated CLASS)
    CREATE,          // CREATE (UDT value-type initialization - stack allocated TYPE)
    DELETE,          // DELETE (object destruction)
    NOTHING,         // NOTHING (null object reference)
    
    // Keywords - File I/O
    OPEN,            // OPEN (open file)
    CLOSE,           // CLOSE (close file)
    PRINT_STREAM,    // PRINT# (file output)
    INPUT_STREAM,    // INPUT# (file input)
    LINE_INPUT_STREAM, // LINE INPUT# (file line input)
    WRITE_STREAM,    // WRITE# (write to file with quoting)
    
    // Keywords - Other
    REM,             // REM (comment)
    CLS,             // CLS (clear screen)
    COLOR,           // COLOR
    WAIT,            // WAIT
    WAIT_MS,         // WAIT_MS (wait milliseconds with cancellation support)
    
    // Keywords - Graphics
    PSET,            // PSET
    LINE,            // LINE
    RECT,            // RECT

    CIRCLE,          // CIRCLE
    CIRCLEF,         // CIRCLEF
    GCLS,            // GCLS (backwards compatible)
    CLG,             // CLG (clear graphics)
    HLINE,           // HLINE (horizontal line)
    VLINE,           // VLINE (vertical line)
    
    // Keywords - Text Layer
    AT,              // AT (position cursor)
    LOCATE,          // LOCATE (position cursor, QuickBASIC style)
    TEXTPUT,         // TEXTPUT (put text with colors)
    PRINT_AT,        // PRINT_AT (user-friendly text positioning with PRINT-style syntax)
    INPUT_AT,        // INPUT_AT (input text at specific coordinates)
    TCHAR,           // TCHAR (put single character)
    TGRID,           // TGRID (set text grid size)
    TSCROLL,         // TSCROLL (scroll text)
    TCLEAR,          // TCLEAR (clear text region)
    
    // Keywords - Sprites
    SPRLOAD,         // SPRLOAD (load sprite)
    SPRFREE,         // SPRFREE (free sprite)
    SPRSHOW,         // SPRSHOW (show sprite)
    SPRHIDE,         // SPRHIDE (hide sprite)
    SPRMOVE,         // SPRMOVE (move sprite)
    SPRPOS,          // SPRPOS (position sprite with transform)
    SPRTINT,         // SPRTINT (tint sprite)
    SPRSCALE,        // SPRSCALE (scale sprite)
    SPRROT,          // SPRROT (rotate sprite)
    SPREXPLODE,      // SPREXPLODE (explode sprite)
    
    // Keywords - Audio
    PLAY,            // PLAY (play audio file with format override)
    PLAY_SOUND,      // PLAY_SOUND (play sound from slot with optional fade)
    
    // Keywords - Timing
    SLEEP,           // SLEEP (pause execution for seconds)
    VSYNC,           // VSYNC (wait for frame)
    AFTER,           // AFTER (one-shot timer event)
    EVERY,           // EVERY (repeating timer event)
    AFTERFRAMES,     // AFTERFRAMES (one-shot frame-based timer)
    EVERYFRAME,      // EVERYFRAME (repeating frame-based timer)
    TIMER,           // TIMER (timer control - TIMER STOP)
    STOP,            // STOP (for TIMER STOP)
    RUN,             // RUN (main event loop - runs until quit)
    
    // Time unit keywords (for AFTER/EVERY)
    MS,              // MS (milliseconds)
    SECS,            // SECS (seconds)
    FRAMES,          // FRAMES (frames)
    
    // Operators - Arithmetic
    PLUS,            // +
    MINUS,           // -
    MULTIPLY,        // *
    DIVIDE,          // /
    INT_DIVIDE,      // \ (integer division)
    POWER,           // ^
    MOD,             // MOD
    
    // Operators - Comparison
    EQUAL,           // =
    NOT_EQUAL,       // <> or !=
    LESS_THAN,       // <
    LESS_EQUAL,      // <=
    GREATER_THAN,    // >
    GREATER_EQUAL,   // >=
    
    // Operators - Logical
    AND,             // AND
    OR,              // OR
    NOT,             // NOT
    XOR,             // XOR (exclusive or)
    EQV,             // EQV (equivalence)
    IMP,             // IMP (implication)
    
    // Delimiters
    LPAREN,          // (
    RPAREN,          // )
    COMMA,           // ,
    SEMICOLON,       // ;
    COLON,           // :
    QUESTION,        // ? (shorthand for PRINT)
    DOT,             // . (member access)
    
    // Type Suffixes
    TYPE_INT,        // % (integer)
    TYPE_FLOAT,      // ! (single precision)
    TYPE_DOUBLE,     // # (double precision)
    TYPE_STRING,     // $ (string)
    TYPE_BYTE,       // @ (byte)
    TYPE_SHORT,      // ^ (short)
    HASH,            // # (file stream indicator for PRINT#/INPUT#)

    // Type Suffixes (alternative names for parser compatibility)
    PERCENT,         // % (integer suffix)
    AMPERSAND,       // & (long suffix)
    EXCLAMATION,     // ! (single suffix)
    CARET,           // ^ (short suffix)
    AT_SUFFIX,       // @ (byte suffix)

    // Hashmap methods
    HASKEY,          // HASKEY (hashmap method)
    KEYS,            // KEYS (hashmap/object method)
    SIZE,            // SIZE (hashmap/object method)
    CLEAR,           // CLEAR (hashmap/object method)
    REMOVE,          // REMOVE (hashmap/object method)
    
    // List method keywords
    APPEND,          // APPEND (list method)
    PREPEND,         // PREPEND (list method)
    HEAD,            // HEAD (list method)
    TAIL,            // TAIL (list method — alias for REST)
    REST,            // REST (list method)
    LENGTH,          // LENGTH (list method)
    EMPTY,           // EMPTY (list method)
    CONTAINS,        // CONTAINS (list method)
    INDEXOF,         // INDEXOF (list method)
    JOIN,            // JOIN (list method)
    COPY,            // COPY (list method)
    REVERSE,         // REVERSE (list method)
    SHIFT,           // SHIFT (list method)
    POP,             // POP (list method)
    EXTEND,          // EXTEND (list method)
    INSERT,          // INSERT (list method)
    GET,             // GET (list method)
    TYPEOF_KW,       // TYPEOF (type query for LIST OF ANY)

    // Special
    USING,           // USING (for PRINT USING)

    // Registry-based modular commands and functions
    REGISTRY_COMMAND, // Commands registered via ModularCommands system
    REGISTRY_FUNCTION, // Functions registered via ModularCommands system

    // Error/Unknown
    UNKNOWN
};

// =============================================================================
// Token Structure
// =============================================================================

struct SourceLocation {
    int line;
    int column;
    
    SourceLocation() : line(0), column(0) {}
    SourceLocation(int l, int c) : line(l), column(c) {}
    
    std::string toString() const {
        return std::to_string(line) + ":" + std::to_string(column);
    }
};

struct Token {
    TokenType type;
    std::string value;       // Original text value
    SourceLocation location; // Where in source code
    
    // For number tokens
    double numberValue;
    
    // For string tokens - tracks if string contains non-ASCII characters (UTF-8)
    bool hasNonASCII;
    
    Token() 
        : type(TokenType::UNKNOWN), value(""), location(), numberValue(0.0), hasNonASCII(false) {}
    
    Token(TokenType t, const std::string& v, const SourceLocation& loc)
        : type(t), value(v), location(loc), numberValue(0.0), hasNonASCII(false) {}
    
    Token(TokenType t, const std::string& v, double num, const SourceLocation& loc)
        : type(t), value(v), location(loc), numberValue(num), hasNonASCII(false) {}
    
    Token(TokenType t, const std::string& v, const SourceLocation& loc, bool nonASCII)
        : type(t), value(v), location(loc), numberValue(0.0), hasNonASCII(nonASCII) {}
    
    // Check token type
    bool is(TokenType t) const { return type == t; }
    bool isNot(TokenType t) const { return type != t; }
    
    // Check if token is a keyword
    bool isKeyword() const {
        return type >= TokenType::PRINT && type <= TokenType::FRAMES;
    }
    
    // Check if token is an operator
    bool isOperator() const {
        return (type >= TokenType::PLUS && type <= TokenType::NOT) ||
               type == TokenType::EQUAL;
    }
    
    // Check if token is a comparison operator
    bool isComparison() const {
        return type >= TokenType::EQUAL && type <= TokenType::GREATER_EQUAL;
    }
    
    // Check if token is arithmetic operator
    bool isArithmetic() const {
        return type >= TokenType::PLUS && type <= TokenType::MOD;
    }
    
    // Human-readable representation
    std::string toString() const;
    std::string toDebugString() const;
};

// =============================================================================
// Token Type Utilities
// =============================================================================

// Convert token type to string
inline const char* tokenTypeToString(TokenType type) {
    switch (type) {
        case TokenType::END_OF_FILE: return "END_OF_FILE";
        case TokenType::END_OF_LINE: return "EOL";
        case TokenType::NUMBER: return "NUMBER";
        case TokenType::STRING: return "STRING";
        case TokenType::IDENTIFIER: return "IDENTIFIER";
        
        // Keywords
        case TokenType::PRINT: return "PRINT";
        case TokenType::INPUT: return "INPUT";
        case TokenType::LET: return "LET";
        case TokenType::GOTO: return "GOTO";
        case TokenType::GOSUB: return "GOSUB";
        case TokenType::RETURN: return "RETURN";
        case TokenType::IF: return "IF";
        case TokenType::THEN: return "THEN";
        case TokenType::ELSE: return "ELSE";
        case TokenType::ELSEIF: return "ELSEIF";
        case TokenType::ENDIF: return "ENDIF";
        case TokenType::FOR: return "FOR";
        case TokenType::EACH: return "EACH";
        case TokenType::TO: return "TO";
        case TokenType::STEP: return "STEP";
        case TokenType::IN: return "IN";
        case TokenType::NEXT: return "NEXT";
        case TokenType::WHILE: return "WHILE";
        case TokenType::WEND: return "WEND";
        case TokenType::REPEAT: return "REPEAT";
        case TokenType::UNTIL: return "UNTIL";
        case TokenType::DO: return "DO";
        case TokenType::LOOP: return "LOOP";
        case TokenType::END: return "END";
        case TokenType::EXIT: return "EXIT";
        case TokenType::CASE: return "CASE";
        case TokenType::SELECT: return "SELECT";
        case TokenType::OF: return "OF";
        case TokenType::WHEN: return "WHEN";
        case TokenType::IS: return "IS";
        case TokenType::OTHERWISE: return "OTHERWISE";
        case TokenType::ENDCASE: return "ENDCASE";
        case TokenType::MATCH: return "MATCH";
        case TokenType::ENDMATCH: return "END MATCH";
        case TokenType::TRY: return "TRY";
        case TokenType::CATCH: return "CATCH";
        case TokenType::FINALLY: return "FINALLY";
        case TokenType::THROW: return "THROW";
        case TokenType::ERR: return "ERR";
        case TokenType::ERL: return "ERL";
        case TokenType::OPTION: return "OPTION";
        case TokenType::BITWISE: return "BITWISE";
        case TokenType::LOGICAL: return "LOGICAL";
        case TokenType::BASE: return "BASE";
        case TokenType::EXPLICIT: return "EXPLICIT";
        case TokenType::FORCE_YIELD: return "FORCE_YIELD";
        case TokenType::NEON: return "NEON";
        case TokenType::UNICODE: return "UNICODE";
        case TokenType::ASCII: return "ASCII";
        case TokenType::DETECTSTRING: return "DETECTSTRING";
        case TokenType::SUB: return "SUB";
        case TokenType::FUNCTION: return "FUNCTION";
        case TokenType::ENDSUB: return "ENDSUB";
        case TokenType::ENDFUNCTION: return "ENDFUNCTION";
        case TokenType::CALL: return "CALL";
        case TokenType::LOCAL: return "LOCAL";
        case TokenType::GLOBAL: return "GLOBAL";
        case TokenType::SHARED: return "SHARED";
        case TokenType::BYREF: return "BYREF";
        case TokenType::BYVAL: return "BYVAL";
        case TokenType::AS: return "AS";
        case TokenType::DEF: return "DEF";
        case TokenType::FN: return "FN";
        case TokenType::IIF: return "IIF";
        case TokenType::MID: return "MID";
        case TokenType::LEFT: return "LEFT";
        case TokenType::RIGHT: return "RIGHT";
        case TokenType::ON: return "ON";
        case TokenType::KEYWORD_INTEGER: return "INTEGER";
        case TokenType::KEYWORD_DOUBLE: return "DOUBLE";
        case TokenType::KEYWORD_SINGLE: return "SINGLE";
        case TokenType::KEYWORD_STRING: return "STRING";
        case TokenType::KEYWORD_LONG: return "LONG";
        case TokenType::KEYWORD_BYTE: return "BYTE";
        case TokenType::KEYWORD_SHORT: return "SHORT";
        case TokenType::KEYWORD_UBYTE: return "UBYTE";
        case TokenType::KEYWORD_USHORT: return "USHORT";
        case TokenType::KEYWORD_UINTEGER: return "UINTEGER";
        case TokenType::KEYWORD_ULONG: return "ULONG";
        case TokenType::KEYWORD_HASHMAP: return "HASHMAP";
        case TokenType::KEYWORD_LIST: return "LIST";
        case TokenType::HASKEY: return "HASKEY";
        case TokenType::KEYS: return "KEYS";
        case TokenType::SIZE: return "SIZE";
        case TokenType::CLEAR: return "CLEAR";
        case TokenType::REMOVE: return "REMOVE";
        case TokenType::APPEND: return "APPEND";
        case TokenType::PREPEND: return "PREPEND";
        case TokenType::HEAD: return "HEAD";
        case TokenType::TAIL: return "TAIL";
        case TokenType::REST: return "REST";
        case TokenType::LENGTH: return "LENGTH";
        case TokenType::EMPTY: return "EMPTY";
        case TokenType::CONTAINS: return "CONTAINS";
        case TokenType::INDEXOF: return "INDEXOF";
        case TokenType::JOIN: return "JOIN";
        case TokenType::COPY: return "COPY";
        case TokenType::REVERSE: return "REVERSE";
        case TokenType::SHIFT: return "SHIFT";
        case TokenType::POP: return "POP";
        case TokenType::EXTEND: return "EXTEND";
        case TokenType::INSERT: return "INSERT";
        case TokenType::GET: return "GET";
        case TokenType::TYPEOF_KW: return "TYPEOF";
        case TokenType::DIM: return "DIM";
        case TokenType::REDIM: return "REDIM";
        case TokenType::ERASE: return "ERASE";
        case TokenType::PRESERVE: return "PRESERVE";
        case TokenType::SWAP: return "SWAP";
        case TokenType::INC: return "INC";
        case TokenType::DEC: return "DEC";
        case TokenType::DATA: return "DATA";
        case TokenType::READ: return "READ";
        case TokenType::RESTORE: return "RESTORE";
        case TokenType::CONSTANT: return "CONSTANT";
        
        // CLASS & Object System
        case TokenType::CLASS: return "CLASS";
        case TokenType::EXTENDS: return "EXTENDS";
        case TokenType::CONSTRUCTOR: return "CONSTRUCTOR";
        case TokenType::DESTRUCTOR: return "DESTRUCTOR";
        case TokenType::METHOD: return "METHOD";
        case TokenType::ME: return "ME";
        case TokenType::SUPER: return "SUPER";
        case TokenType::NEW: return "NEW";
        case TokenType::CREATE: return "CREATE";
        case TokenType::DELETE: return "DELETE";
        case TokenType::NOTHING: return "NOTHING";
        
        case TokenType::OPEN: return "OPEN";
        case TokenType::CLOSE: return "CLOSE";
        case TokenType::PRINT_STREAM: return "PRINT#";
        case TokenType::INPUT_STREAM: return "INPUT#";
        case TokenType::LINE_INPUT_STREAM: return "LINE INPUT#";
        case TokenType::WRITE_STREAM: return "WRITE#";
        case TokenType::REM: return "REM";
        case TokenType::CLS: return "CLS";
        case TokenType::COLOR: return "COLOR";
        case TokenType::SLEEP: return "SLEEP";
        case TokenType::WAIT: return "WAIT";
        case TokenType::PSET: return "PSET";
        case TokenType::LINE: return "LINE";
        case TokenType::RECT: return "RECT";

        case TokenType::CIRCLE: return "CIRCLE";
        case TokenType::CIRCLEF: return "CIRCLEF";
        case TokenType::GCLS: return "GCLS";
        
        // Text Layer Commands
        case TokenType::AT: return "AT";
        case TokenType::LOCATE: return "LOCATE";
        case TokenType::TEXTPUT: return "TEXTPUT";
        // case TokenType::PRINT_AT: return "PRINT_AT";  // NOW REGISTRY-BASED
        case TokenType::INPUT_AT: return "INPUT_AT";
        case TokenType::TCHAR: return "TCHAR";
        case TokenType::TGRID: return "TGRID";
        case TokenType::REGISTRY_COMMAND: return "REGISTRY_COMMAND";
        case TokenType::REGISTRY_FUNCTION: return "REGISTRY_FUNCTION";
        case TokenType::TSCROLL: return "TSCROLL";
        case TokenType::TCLEAR: return "TCLEAR";
        
        // Operators
        case TokenType::PLUS: return "+";
        case TokenType::MINUS: return "-";
        case TokenType::MULTIPLY: return "*";
        case TokenType::DIVIDE: return "/";
        case TokenType::INT_DIVIDE: return "\\";
        case TokenType::POWER: return "^";
        case TokenType::MOD: return "MOD";
        case TokenType::EQUAL: return "=";
        case TokenType::NOT_EQUAL: return "<>";
        case TokenType::LESS_THAN: return "<";
        case TokenType::LESS_EQUAL: return "<=";
        case TokenType::GREATER_THAN: return ">";
        case TokenType::GREATER_EQUAL: return ">=";
        case TokenType::AND: return "AND";
        case TokenType::OR: return "OR";
        case TokenType::NOT: return "NOT";
        case TokenType::XOR: return "XOR";
        case TokenType::EQV: return "EQV";
        case TokenType::IMP: return "IMP";
        
        // Delimiters
        case TokenType::LPAREN: return "(";
        case TokenType::RPAREN: return ")";
        case TokenType::COMMA: return ",";
        case TokenType::SEMICOLON: return ";";
        case TokenType::COLON: return ":";
        case TokenType::QUESTION: return "?";
        
        // Type suffixes
        case TokenType::TYPE_INT: return "%";
        case TokenType::TYPE_FLOAT: return "!";
        case TokenType::TYPE_DOUBLE: return "#";
        case TokenType::TYPE_STRING: return "$";
        case TokenType::TYPE_BYTE: return "@";
        case TokenType::TYPE_SHORT: return "^";
        case TokenType::HASH: return "#";

        // Type suffix alternatives
        case TokenType::PERCENT: return "%";
        case TokenType::AMPERSAND: return "&";
        case TokenType::EXCLAMATION: return "!";
        case TokenType::CARET: return "^";
        case TokenType::AT_SUFFIX: return "@";

        case TokenType::USING: return "USING";
        case TokenType::UNKNOWN: return "UNKNOWN";
    }
    return "UNKNOWN";
}

// Token toString implementation
inline std::string Token::toString() const {
    std::ostringstream oss;
    oss << tokenTypeToString(type);
    
    if (type == TokenType::NUMBER) {
        oss << "(" << numberValue << ")";
    } else if (type == TokenType::STRING) {
        oss << "(\"" << value << "\")";
    } else if (type == TokenType::IDENTIFIER) {
        oss << "(" << value << ")";
    } else if (!value.empty() && value != tokenTypeToString(type)) {
        oss << "(" << value << ")";
    }
    
    return oss.str();
}

// Token debug string with location
inline std::string Token::toDebugString() const {
    std::ostringstream oss;
    oss << "[" << location.toString() << "] " << toString();
    return oss.str();
}

// Stream output operator for Token
inline std::ostream& operator<<(std::ostream& os, const Token& token) {
    os << token.toString();
    return os;
}

// Stream output operator for TokenType
inline std::ostream& operator<<(std::ostream& os, TokenType type) {
    os << tokenTypeToString(type);
    return os;
}

} // namespace FasterBASIC

#endif // FASTERBASIC_TOKEN_H