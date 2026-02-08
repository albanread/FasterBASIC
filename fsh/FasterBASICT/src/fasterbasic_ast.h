//
// fasterbasic_ast.h
// FasterBASIC - Abstract Syntax Tree Definitions
//
// Defines all AST node types for representing parsed BASIC programs.
// The AST is the intermediate representation between tokens and execution.
//

#ifndef FASTERBASIC_AST_H
#define FASTERBASIC_AST_H

#include "fasterbasic_token.h"
#include <string>
#include <vector>
#include <memory>
#include <sstream>



// Forward declarations for ModularCommands
namespace FasterBASIC {
namespace ModularCommands {
    enum class ReturnType;
}
}

namespace FasterBASIC {

// Forward declarations
class ASTNode;
class Statement;
class Expression;
class Program;

// Smart pointer types for AST nodes
using ASTNodePtr = std::unique_ptr<ASTNode>;
using StatementPtr = std::unique_ptr<Statement>;
using ExpressionPtr = std::unique_ptr<Expression>;

// =============================================================================
// AST Node Types (for visitor pattern / type identification)
// =============================================================================

enum class ASTNodeType {
    // Program structure
    PROGRAM,
    PROGRAM_LINE,

    // Statements
    STMT_PRINT,
    STMT_CONSOLE,
    STMT_INPUT,
    STMT_OPEN,
    STMT_CLOSE,
    STMT_LET,
    STMT_MID_ASSIGN,
    STMT_SLICE_ASSIGN,
    STMT_GOTO,
    STMT_GOSUB,
    STMT_ON_GOTO,
    STMT_ON_GOSUB,
    STMT_ON_CALL,
    STMT_ON_EVENT,
    STMT_RETURN,
    STMT_CONSTANT,
    STMT_LABEL,
    STMT_PLAY,
    STMT_PLAY_SOUND,
    STMT_EXIT,
    STMT_IF,
    STMT_CASE,
    STMT_WHEN,
    STMT_FOR,
    STMT_FOR_IN,
    STMT_NEXT,
    STMT_WHILE,
    STMT_WEND,
    STMT_REPEAT,
    STMT_UNTIL,
    STMT_DO,
    STMT_LOOP,
    STMT_END,
    STMT_TRY_CATCH,
    STMT_THROW,
    STMT_DIM,
    STMT_REDIM,
    STMT_ERASE,
    STMT_SWAP,
    STMT_INC,
    STMT_DEC,
    STMT_LOCAL,
    STMT_GLOBAL,
    STMT_SHARED,
    STMT_TYPE,
    STMT_DATA,
    STMT_READ,
    STMT_RESTORE,
    STMT_REM,
    STMT_OPTION,
    STMT_CLS,
    STMT_COLOR,
    STMT_LOCATE,
    STMT_WIDTH,
    STMT_WAIT,
    STMT_WAIT_MS,
    STMT_PSET,
    STMT_LINE,
    STMT_RECT,
    STMT_CIRCLE,
    STMT_CIRCLEF,
    STMT_GCLS,
    STMT_HLINE,
    STMT_VLINE,

    // SuperTerminal API - Text Layer
    STMT_AT,
    STMT_TEXTPUT,
    STMT_PRINT_AT,
    STMT_INPUT_AT,
    STMT_TCHAR,
    STMT_TGRID,
    STMT_TSCROLL,
    STMT_TCLEAR,

    // SuperTerminal API - Sprites
    STMT_SPRLOAD,
    STMT_SPRFREE,
    STMT_SPRSHOW,
    STMT_SPRHIDE,
    STMT_SPRMOVE,
    STMT_SPRPOS,
    STMT_SPRTINT,
    STMT_SPRSCALE,
    STMT_SPRROT,
    STMT_SPREXPLODE,

    // SuperTerminal API - Audio
    // (Audio commands now handled via modular registry)

    // SuperTerminal API - Timing
    STMT_VSYNC,
    STMT_AFTER,
    STMT_EVERY,
    STMT_AFTERFRAMES,
    STMT_EVERYFRAME,
    STMT_TIMER_STOP,
    STMT_TIMER_INTERVAL,
    STMT_RUN,

    STMT_SUB,
    STMT_FUNCTION,
    STMT_CALL,
    STMT_DEF,

    // CLASS & Object System
    STMT_CLASS,             // CLASS ... END CLASS
    STMT_METHOD,            // METHOD ... END METHOD (inside CLASS)
    STMT_CONSTRUCTOR,       // CONSTRUCTOR ... END CONSTRUCTOR
    STMT_DESTRUCTOR,        // DESTRUCTOR ... END DESTRUCTOR
    STMT_DELETE,            // DELETE obj
    STMT_MATCH_TYPE,        // MATCH TYPE ... END MATCH (safe type dispatch)

    // Expressions
    EXPR_BINARY,
    EXPR_UNARY,
    EXPR_NUMBER,
    EXPR_STRING,
    EXPR_VARIABLE,
    EXPR_ARRAY_ACCESS,
    EXPR_ARRAY_BINOP,
    EXPR_FUNCTION_CALL,
    EXPR_IIF,
    EXPR_MEMBER_ACCESS,
    EXPR_METHOD_CALL,

    // CLASS & Object System Expressions
    EXPR_NEW,               // NEW ClassName(args) - heap allocated CLASS
    EXPR_CREATE,            // CREATE TypeName(args) - stack allocated UDT value init
    EXPR_ME,                // ME (current object reference)
    EXPR_SUPER_CALL,        // SUPER.Method() or SUPER() in constructor
    EXPR_IS_TYPE,           // obj IS ClassName / obj IS NOTHING
    EXPR_NOTHING,           // NOTHING (null object reference)
    
    // LIST expressions
    EXPR_LIST_CONSTRUCTOR,  // LIST(expr, expr, ...) literal constructor
};

// =============================================================================
// Base AST Node
// =============================================================================

class ASTNode {
public:
    virtual ~ASTNode() = default;

    virtual ASTNodeType getType() const = 0;
    virtual std::string toString(int indent = 0) const = 0;

    SourceLocation location;

protected:
    std::string makeIndent(int indent) const {
        return std::string(indent * 2, ' ');
    }
};

// =============================================================================
// Expression Nodes
// =============================================================================

class Expression : public ASTNode {
public:
    virtual ~Expression() = default;
};

// Binary operation: left op right
class BinaryExpression : public Expression {
public:
    ExpressionPtr left;
    TokenType op;
    ExpressionPtr right;

    BinaryExpression(ExpressionPtr l, TokenType o, ExpressionPtr r)
        : left(std::move(l)), op(o), right(std::move(r)) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_BINARY; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "BinaryExpr(" << tokenTypeToString(op) << ")\n";
        oss << left->toString(indent + 1);
        oss << right->toString(indent + 1);
        return oss.str();
    }
};

// Unary operation: op expr
class UnaryExpression : public Expression {
public:
    TokenType op;
    ExpressionPtr expr;

    UnaryExpression(TokenType o, ExpressionPtr e)
        : op(o), expr(std::move(e)) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_UNARY; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "UnaryExpr(" << tokenTypeToString(op) << ")\n";
        oss << expr->toString(indent + 1);
        return oss.str();
    }
};

// Number literal
class NumberExpression : public Expression {
public:
    double value;

    explicit NumberExpression(double v) : value(v) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_NUMBER; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "Number(" << value << ")\n";
        return oss.str();
    }
};

// String literal
class StringExpression : public Expression {
public:
    std::string value;
    bool hasNonASCII;  // Track if string contains non-ASCII characters

    explicit StringExpression(const std::string& v, bool nonASCII = false) 
        : value(v), hasNonASCII(nonASCII) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_STRING; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "String(\"" << value << "\"";
        if (hasNonASCII) oss << " [Unicode]";
        oss << ")\n";
        return oss.str();
    }
};

// Variable reference
class VariableExpression : public Expression {
public:
    std::string name;
    TokenType typeSuffix;  // TYPE_INT, TYPE_STRING, etc., or UNKNOWN if none

    explicit VariableExpression(const std::string& n, TokenType suffix = TokenType::UNKNOWN)
        : name(n), typeSuffix(suffix) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_VARIABLE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "Variable(" << name;
        if (typeSuffix != TokenType::UNKNOWN) {
            oss << tokenTypeToString(typeSuffix);
        }
        oss << ")\n";
        return oss.str();
    }
};

// Array access: name(index1, index2, ...)
class ArrayAccessExpression : public Expression {
public:
    std::string name;
    TokenType typeSuffix;
    std::vector<ExpressionPtr> indices;

    ArrayAccessExpression(const std::string& n, TokenType suffix = TokenType::UNKNOWN)
        : name(n), typeSuffix(suffix) {}

    void addIndex(ExpressionPtr idx) {
        indices.push_back(std::move(idx));
    }

    ASTNodeType getType() const override { return ASTNodeType::EXPR_ARRAY_ACCESS; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ArrayAccess(" << name;
        if (typeSuffix != TokenType::UNKNOWN) {
            oss << tokenTypeToString(typeSuffix);
        }
        oss << ")\n";
        for (const auto& idx : indices) {
            oss << idx->toString(indent + 1);
        }
        return oss.str();
    }
};

// Whole-array binary operation: A() + B(), A() * scalar, etc.
// This represents operations on entire arrays (empty indices means whole array)
class ArrayBinaryOpExpression : public Expression {
public:
    enum class OpType {
        ADD,           // A() + B()
        SUBTRACT,      // A() - B()
        MULTIPLY,      // A() * B() (component-wise)
        ADD_SCALAR,    // A() + scalar
        SUB_SCALAR,    // A() - scalar
        MUL_SCALAR     // A() * scalar
    };
    
    OpType operation;
    ExpressionPtr leftArray;   // Array expression (should be ArrayAccessExpression with empty indices)
    ExpressionPtr rightExpr;   // Either another array or a scalar
    bool isScalarOp;           // true if right side is scalar, false if array
    
    ArrayBinaryOpExpression(OpType op, ExpressionPtr left, ExpressionPtr right, bool scalar)
        : operation(op), leftArray(std::move(left)), rightExpr(std::move(right)), isScalarOp(scalar) {}
    
    ASTNodeType getType() const override { return ASTNodeType::EXPR_ARRAY_BINOP; }
    
    const char* opToString() const {
        switch (operation) {
            case OpType::ADD: return "+";
            case OpType::SUBTRACT: return "-";
            case OpType::MULTIPLY: return "*";
            case OpType::ADD_SCALAR: return "+ (scalar)";
            case OpType::SUB_SCALAR: return "- (scalar)";
            case OpType::MUL_SCALAR: return "* (scalar)";
            default: return "?";
        }
    }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ArrayBinaryOp(" << opToString() << ")\n";
        oss << makeIndent(indent + 1) << "Left:\n";
        oss << leftArray->toString(indent + 2);
        oss << makeIndent(indent + 1) << "Right:\n";
        oss << rightExpr->toString(indent + 2);
        return oss.str();
    }
};

// Function call: FN name(args) or name(args)
class FunctionCallExpression : public Expression {
public:
    std::string name;
    std::vector<ExpressionPtr> arguments;
    bool isFN;  // true for FN xxx, false for built-in functions

    explicit FunctionCallExpression(const std::string& n, bool fn = false)
        : name(n), isFN(fn) {}

    void addArgument(ExpressionPtr arg) {
        arguments.push_back(std::move(arg));
    }

    ASTNodeType getType() const override { return ASTNodeType::EXPR_FUNCTION_CALL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "FunctionCall(" << (isFN ? "FN " : "") << name << ")\n";
        for (const auto& arg : arguments) {
            oss << arg->toString(indent + 1);
        }
        return oss.str();
    }
};

// Registry function call expression
class RegistryFunctionExpression : public Expression {
public:
    std::string name;
    std::vector<ExpressionPtr> arguments;
    FasterBASIC::ModularCommands::ReturnType returnType;

    explicit RegistryFunctionExpression(const std::string& n, FasterBASIC::ModularCommands::ReturnType retType)
        : name(n), returnType(retType) {}

    void addArgument(ExpressionPtr arg) {
        arguments.push_back(std::move(arg));
    }

    ASTNodeType getType() const override { return ASTNodeType::EXPR_FUNCTION_CALL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "RegistryFunction(" << name << ")\n";
        for (const auto& arg : arguments) {
            oss << arg->toString(indent + 1);
        }
        return oss.str();
    }
};

// Member access expression: object.member or object.member.submember
class MemberAccessExpression : public Expression {
public:
    ExpressionPtr object;          // Base object (can be VariableExpression or another MemberAccessExpression)
    std::string memberName;        // Name of the member being accessed
    
    MemberAccessExpression(ExpressionPtr obj, const std::string& member)
        : object(std::move(obj)), memberName(member) {}
    
    ASTNodeType getType() const override { return ASTNodeType::EXPR_MEMBER_ACCESS; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "MemberAccess(." << memberName << ")\n";
        oss << object->toString(indent + 1);
        return oss.str();
    }
};

// Method call expression: object.method(args)
class MethodCallExpression : public Expression {
public:
    ExpressionPtr object;          // Base object (typically VariableExpression)
    std::string methodName;        // Name of the method being called
    std::vector<ExpressionPtr> arguments;  // Method arguments
    
    MethodCallExpression(ExpressionPtr obj, const std::string& method)
        : object(std::move(obj)), methodName(method) {}
    
    void addArgument(ExpressionPtr arg) {
        arguments.push_back(std::move(arg));
    }
    
    ASTNodeType getType() const override { return ASTNodeType::EXPR_METHOD_CALL; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "MethodCall(." << methodName << ")\n";
        oss << makeIndent(indent + 1) << "object:\n";
        oss << object->toString(indent + 2);
        if (!arguments.empty()) {
            oss << makeIndent(indent + 1) << "arguments:\n";
            for (const auto& arg : arguments) {
                oss << arg->toString(indent + 2);
            }
        }
        return oss.str();
    }
};

// IIF (Immediate IF) expression - inline conditional
class IIFExpression : public Expression {
public:
    ExpressionPtr condition;
    ExpressionPtr trueValue;
    ExpressionPtr falseValue;

    IIFExpression(ExpressionPtr cond, ExpressionPtr trueVal, ExpressionPtr falseVal)
        : condition(std::move(cond)), trueValue(std::move(trueVal)), falseValue(std::move(falseVal)) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_IIF; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "IIF(\n";
        oss << makeIndent(indent + 1) << "condition:\n";
        oss << condition->toString(indent + 2);
        oss << makeIndent(indent + 1) << "trueValue:\n";
        oss << trueValue->toString(indent + 2);
        oss << makeIndent(indent + 1) << "falseValue:\n";
        oss << falseValue->toString(indent + 2);
        oss << makeIndent(indent) << ")\n";
        return oss.str();
    }
};

// =============================================================================
// LIST Constructor Expression: LIST(expr1, expr2, ...)
// =============================================================================

class ListConstructorExpression : public Expression {
public:
    std::vector<ExpressionPtr> elements;   // Elements in the LIST(...) literal
    
    ListConstructorExpression() {}
    
    void addElement(ExpressionPtr elem) {
        elements.push_back(std::move(elem));
    }
    
    ASTNodeType getType() const override { return ASTNodeType::EXPR_LIST_CONSTRUCTOR; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "LIST(";
        for (size_t i = 0; i < elements.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << elements[i]->toString(0);
        }
        oss << ")";
        return oss.str();
    }
};

// =============================================================================
// Statements
// =============================================================================

class Statement : public ASTNode {
public:
    virtual ~Statement() = default;
};

// PRINT statement
class PrintStatement : public Statement {
public:
    struct PrintItem {
        ExpressionPtr expr;
        bool semicolon;  // true if followed by semicolon, false if comma or end
        bool comma;      // true if followed by comma

        PrintItem(ExpressionPtr e, bool semi, bool com)
            : expr(std::move(e)), semicolon(semi), comma(com) {}
    };

    int fileNumber;  // 0 for console, >0 for file

    std::vector<PrintItem> items;
    bool trailingNewline;  // false if ends with ; or ,

    // PRINT USING support
    bool hasUsing;                          // true if this is PRINT USING
    ExpressionPtr formatExpr;               // Format string expression
    std::vector<ExpressionPtr> usingValues; // Values to format

    PrintStatement() : fileNumber(0), trailingNewline(true), hasUsing(false) {}

    void addItem(ExpressionPtr expr, bool semicolon, bool comma) {
        items.emplace_back(std::move(expr), semicolon, comma);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_PRINT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "PRINT";
        if (hasUsing) {
            oss << " USING\n";
            oss << makeIndent(indent + 1) << "Format:\n";
            oss << formatExpr->toString(indent + 2);
            oss << makeIndent(indent + 1) << "Values:\n";
            for (const auto& val : usingValues) {
                oss << val->toString(indent + 2);
            }
        } else {
            if (!trailingNewline) oss << " [no newline]";
            oss << "\n";
            for (const auto& item : items) {
                oss << item.expr->toString(indent + 1);
                if (item.semicolon) oss << makeIndent(indent + 1) << "[;]\n";
                if (item.comma) oss << makeIndent(indent + 1) << "[,]\n";
            }
        }
        return oss.str();
    }
};

// CONSOLE statement - output to console (debug/logging)
class ConsoleStatement : public Statement {
public:
    struct PrintItem {
        ExpressionPtr expr;
        bool semicolon;  // true if followed by semicolon, false if comma or end
        bool comma;      // true if followed by comma

        PrintItem(ExpressionPtr e, bool semi, bool com)
            : expr(std::move(e)), semicolon(semi), comma(com) {}
    };

    std::vector<PrintItem> items;
    bool trailingNewline;  // false if ends with ; or ,

    ConsoleStatement() : trailingNewline(true) {}

    void addItem(ExpressionPtr expr, bool semicolon, bool comma) {
        items.emplace_back(std::move(expr), semicolon, comma);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_CONSOLE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CONSOLE";
        if (!trailingNewline) oss << " [no newline]";
        oss << "\n";
        for (const auto& item : items) {
            oss << item.expr->toString(indent + 1);
            if (item.semicolon) oss << makeIndent(indent + 1) << "[;]\n";
            if (item.comma) oss << makeIndent(indent + 1) << "[,]\n";
        }
        return oss.str();
    }
};

// PRINT_AT statement - positioned text output with PRINT-style syntax
class PrintAtStatement : public Statement {
public:
    struct PrintItem {
        ExpressionPtr expr;
        bool semicolon;  // true if followed by semicolon
        bool comma;      // true if followed by comma

        PrintItem(ExpressionPtr e, bool semi, bool com)
            : expr(std::move(e)), semicolon(semi), comma(com) {}
    };

    // Position coordinates
    ExpressionPtr x;
    ExpressionPtr y;

    // Print items (for normal mode)
    std::vector<PrintItem> items;

    // Optional colors
    ExpressionPtr fg;  // Foreground color (default: white)
    ExpressionPtr bg;  // Background color (default: black)
    bool hasExplicitColors;

    // PRINT_AT USING support
    bool hasUsing;                          // true if this is PRINT_AT USING
    ExpressionPtr formatExpr;               // Format string expression
    std::vector<ExpressionPtr> usingValues; // Values to format

    PrintAtStatement() : hasExplicitColors(false), hasUsing(false) {}

    void addItem(ExpressionPtr expr, bool semicolon, bool comma) {
        items.emplace_back(std::move(expr), semicolon, comma);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_PRINT_AT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "PRINT_AT\n";
        oss << makeIndent(indent + 1) << "X: " << x->toString(indent + 2);
        oss << makeIndent(indent + 1) << "Y: " << y->toString(indent + 2);
        
        if (hasUsing) {
            oss << makeIndent(indent + 1) << "USING\n";
            oss << makeIndent(indent + 2) << "Format:\n";
            oss << formatExpr->toString(indent + 3);
            oss << makeIndent(indent + 2) << "Values:\n";
            for (const auto& val : usingValues) {
                oss << val->toString(indent + 3);
            }
        } else {
            oss << makeIndent(indent + 1) << "Text items:\n";
            for (const auto& item : items) {
                oss << item.expr->toString(indent + 2);
                if (item.semicolon) oss << makeIndent(indent + 2) << "[;]\n";
                if (item.comma) oss << makeIndent(indent + 2) << "[,]\n";
            }
        }
        
        if (hasExplicitColors) {
            if (fg) oss << makeIndent(indent + 1) << "FG: " << fg->toString(indent + 2);
            if (bg) oss << makeIndent(indent + 1) << "BG: " << bg->toString(indent + 2);
        }
        
        return oss.str();
    }
};

// INPUT statement
class InputStatement : public Statement {
public:
    std::string prompt;
    std::vector<std::string> variables;
    int fileNumber;  // 0 for console, >0 for file
    bool isLineInput;  // true for LINE INPUT

    InputStatement() : fileNumber(0), isLineInput(false) {}

    void addVariable(const std::string& var) {
        variables.push_back(var);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_INPUT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "INPUT";
        if (!prompt.empty()) {
            oss << " \"" << prompt << "\"";
        }
        oss << "\n";
        for (const auto& var : variables) {
            oss << makeIndent(indent + 1) << "Variable(" << var << ")\n";
        }
        return oss.str();
    }
};

// INPUT_AT statement - positioned text input with INPUT-style syntax
class InputAtStatement : public Statement {
public:
    // Position coordinates
    ExpressionPtr x;
    ExpressionPtr y;
    
    // Optional prompt string
    std::string prompt;
    
    // Variable to store the result
    std::string variable;
    
    // Optional colors
    ExpressionPtr fgColor;
    ExpressionPtr bgColor;
    
    InputAtStatement() {}
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_INPUT_AT; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "INPUT_AT\n";
        oss << makeIndent(indent + 1) << "X: " << x->toString(indent + 2);
        oss << makeIndent(indent + 1) << "Y: " << y->toString(indent + 2);
        if (!prompt.empty()) {
            oss << makeIndent(indent + 1) << "Prompt: \"" << prompt << "\"\n";
        }
        oss << makeIndent(indent + 1) << "Variable: " << variable << "\n";
        if (fgColor) {
            oss << makeIndent(indent + 1) << "FG Color: " << fgColor->toString(indent + 2);
        }
        if (bgColor) {
            oss << makeIndent(indent + 1) << "BG Color: " << bgColor->toString(indent + 2);
        }
        return oss.str();
    }
};

// OPEN statement (file I/O)
class OpenStatement : public Statement {
public:
    std::string filename;
    std::string mode;  // "INPUT", "OUTPUT", "APPEND", "RANDOM"
    int fileNumber;
    int recordLength;  // For RANDOM mode

    OpenStatement() : fileNumber(0), recordLength(128) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_OPEN; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "OPEN \"" << filename << "\" FOR " << mode
            << " AS #" << fileNumber << "\n";
        return oss.str();
    }
};

// CLOSE statement (file I/O)
class CloseStatement : public Statement {
public:
    int fileNumber;  // 0 means close all
    bool closeAll;

    CloseStatement() : fileNumber(0), closeAll(true) {}
    explicit CloseStatement(int num) : fileNumber(num), closeAll(false) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_CLOSE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CLOSE";
        if (!closeAll) {
            oss << " #" << fileNumber;
        }
        oss << "\n";
        return oss.str();
    }
};

// LET statement (assignment)
class LetStatement : public Statement {
public:
    std::string variable;
    TokenType typeSuffix;
    std::vector<ExpressionPtr> indices;  // For array assignment
    std::vector<std::string> memberChain;  // For member access (e.g., P.X.Y)
    ExpressionPtr value;

    LetStatement(const std::string& var, TokenType suffix = TokenType::UNKNOWN)
        : variable(var), typeSuffix(suffix) {}

    void addIndex(ExpressionPtr idx) {
        indices.push_back(std::move(idx));
    }
    
    void addMember(const std::string& member) {
        memberChain.push_back(member);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_LET; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "LET " << variable;
        if (typeSuffix != TokenType::UNKNOWN) {
            oss << tokenTypeToString(typeSuffix);
        }
        if (!indices.empty()) {
            oss << "[array]";
        }
        for (const auto& member : memberChain) {
            oss << "." << member;
        }
        oss << "\n";
        for (const auto& idx : indices) {
            oss << idx->toString(indent + 1);
        }
        oss << makeIndent(indent + 1) << "=\n";
        oss << value->toString(indent + 1);
        return oss.str();
    }
};

// MID$ assignment statement
// Simulates: MID$(variable$, pos, len) = replacement$
class MidAssignStatement : public Statement {
public:
    std::string variable;      // The variable being modified
    ExpressionPtr position;    // Starting position (1-based)
    ExpressionPtr length;      // Length of substring to replace
    ExpressionPtr replacement; // The replacement string expression

    MidAssignStatement(const std::string& var)
        : variable(var) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_MID_ASSIGN; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "MID$(" << variable << ", pos, len) = value\n";
        if (position) {
            oss << makeIndent(indent + 1) << "Position:\n";
            oss << position->toString(indent + 2);
        }
        if (length) {
            oss << makeIndent(indent + 1) << "Length:\n";
            oss << length->toString(indent + 2);
        }
        if (replacement) {
            oss << makeIndent(indent + 1) << "Replacement:\n";
            oss << replacement->toString(indent + 2);
        }
        return oss.str();
    }
};

// String slice assignment: var$(start TO end) = value
class SliceAssignStatement : public Statement {
public:
    std::string variable;      // The variable being modified
    ExpressionPtr start;       // Starting position (1-based, defaults to 1)
    ExpressionPtr end;         // Ending position (1-based, defaults to length)
    ExpressionPtr replacement; // The replacement string expression

    SliceAssignStatement(const std::string& var)
        : variable(var) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_SLICE_ASSIGN; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << variable << "$(start TO end) = value\n";
        if (start) {
            oss << makeIndent(indent + 1) << "Start:\n";
            oss << start->toString(indent + 2);
        }
        if (end) {
            oss << makeIndent(indent + 1) << "End:\n";
            oss << end->toString(indent + 2);
        }
        if (replacement) {
            oss << makeIndent(indent + 1) << "Replacement:\n";
            oss << replacement->toString(indent + 2);
        }
        return oss.str();
    }
};

// GOTO statement
class GotoStatement : public Statement {
public:
    int lineNumber;          // For GOTO 10000 (line number)
    std::string label;       // For GOTO label1 (symbolic label)
    bool isLabel;            // true if using symbolic label, false if line number

    // Constructor for line number
    explicit GotoStatement(int line)
        : lineNumber(line), isLabel(false) {}

    // Constructor for symbolic label
    explicit GotoStatement(const std::string& lbl)
        : lineNumber(0), label(lbl), isLabel(true) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_GOTO; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        if (isLabel) {
            oss << makeIndent(indent) << "GOTO " << label << "\n";
        } else {
            oss << makeIndent(indent) << "GOTO " << lineNumber << "\n";
        }
        return oss.str();
    }
};

// GOSUB statement
class GosubStatement : public Statement {
public:
    int lineNumber;          // For GOSUB 10000 (line number)
    std::string label;       // For GOSUB label1 (symbolic label)
    bool isLabel;            // true if using symbolic label, false if line number

    // Constructor for line number
    explicit GosubStatement(int line)
        : lineNumber(line), isLabel(false) {}

    // Constructor for symbolic label
    explicit GosubStatement(const std::string& lbl)
        : lineNumber(0), label(lbl), isLabel(true) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_GOSUB; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        if (isLabel) {
            oss << makeIndent(indent) << "GOSUB " << label << "\n";
        } else {
            oss << makeIndent(indent) << "GOSUB " << lineNumber << "\n";
        }
        return oss.str();
    }
};

// ON GOTO statement - computed GOTO based on expression value
class OnGotoStatement : public Statement {
public:
    ExpressionPtr selector;  // Expression to evaluate (1-based index)
    std::vector<std::string> labels;  // List of labels to jump to
    std::vector<int> lineNumbers;     // List of line numbers to jump to
    std::vector<bool> isLabelList;    // true for label, false for line number

    OnGotoStatement() = default;

    void addTarget(const std::string& label) {
        labels.push_back(label);
        lineNumbers.push_back(0);
        isLabelList.push_back(true);
    }

    void addTarget(int lineNum) {
        labels.push_back("");
        lineNumbers.push_back(lineNum);
        isLabelList.push_back(false);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_ON_GOTO; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ON ";
        oss << selector->toString(0) << " GOTO ";
        for (size_t i = 0; i < isLabelList.size(); i++) {
            if (i > 0) oss << ", ";
            if (isLabelList[i]) {
                oss << labels[i];
            } else {
                oss << lineNumbers[i];
            }
        }
        oss << "\n";
        return oss.str();
    }
};

// ON GOSUB statement - computed GOSUB based on expression value
class OnGosubStatement : public Statement {
public:
    ExpressionPtr selector;  // Expression to evaluate (1-based index)
    std::vector<std::string> labels;  // List of labels to call
    std::vector<int> lineNumbers;     // List of line numbers to call
    std::vector<bool> isLabelList;    // true for label, false for line number

    OnGosubStatement() = default;

    void addTarget(const std::string& label) {
        labels.push_back(label);
        lineNumbers.push_back(0);
        isLabelList.push_back(true);
    }

    void addTarget(int lineNum) {
        labels.push_back("");
        lineNumbers.push_back(lineNum);
        isLabelList.push_back(false);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_ON_GOSUB; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ON ";
        oss << selector->toString(0) << " GOSUB ";
        for (size_t i = 0; i < isLabelList.size(); i++) {
            if (i > 0) oss << ", ";
            if (isLabelList[i]) {
                oss << labels[i];
            } else {
                oss << lineNumbers[i];
            }
        }
        oss << "\n";
        return oss.str();
    }
};

// ON CALL statement - computed function/sub call based on expression value
class OnCallStatement : public Statement {
public:
    ExpressionPtr selector;  // Expression to evaluate (1-based index)
    std::vector<std::string> functionNames;  // List of functions/subs to call

    OnCallStatement() = default;

    void addTarget(const std::string& name) {
        functionNames.push_back(name);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_ON_CALL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ON ";
        oss << selector->toString(0) << " CALL ";
        for (size_t i = 0; i < functionNames.size(); i++) {
            if (i > 0) oss << ", ";
            oss << functionNames[i];
        }
        oss << "\n";
        return oss.str();
    }
};

// RETURN statement
class ReturnStatement : public Statement {
public:
    ExpressionPtr returnValue;  // nullptr for SUB/GOSUB return, set for FUNCTION return

    ReturnStatement() = default;
    explicit ReturnStatement(ExpressionPtr value) : returnValue(std::move(value)) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_RETURN; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "RETURN";
        if (returnValue) {
            oss << " " << returnValue->toString();
        }
        return oss.str();
    }
};

// =============================================================================
// Event-Driven Statements
// =============================================================================

/// Event handler types for ON <event> statements
enum class EventHandlerType {
    CALL,      // ON EVENT CALL function
    GOTO,      // ON EVENT GOTO line
    GOSUB      // ON EVENT GOSUB line
};

class OnEventStatement : public Statement {
public:
    std::string eventName;           // Event name (e.g., "KEYPRESSED", "LEFT_MOUSE")
    EventHandlerType handlerType;    // CALL, GOTO, or GOSUB
    std::string target;              // Function name, label, or line number
    bool isLineNumber;               // true if target is a line number, false if label/function

    OnEventStatement()
        : handlerType(EventHandlerType::CALL)
        , isLineNumber(false)
    {}

    OnEventStatement(const std::string& event, EventHandlerType type, const std::string& tgt, bool isLine = false)
        : eventName(event)
        , handlerType(type)
        , target(tgt)
        , isLineNumber(isLine)
    {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_ON_EVENT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ON " << eventName << " ";
        
        switch (handlerType) {
            case EventHandlerType::CALL:  oss << "CALL "; break;
            case EventHandlerType::GOTO:  oss << "GOTO "; break;
            case EventHandlerType::GOSUB: oss << "GOSUB "; break;
        }
        
        oss << target;
        return oss.str();
    }
};

// =============================================================================
// Constants
// =============================================================================
// CONSTANT statement - defines a compile-time constant
class ConstantStatement : public Statement {
public:
    std::string name;        // Constant name
    ExpressionPtr value;     // Constant value (must be evaluable at compile time)

    ConstantStatement() = default;
    ConstantStatement(const std::string& n, ExpressionPtr v)
        : name(n), value(std::move(v)) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_CONSTANT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CONSTANT " << name << " = ";
        if (value) {
            oss << value->toString(0);
        }
        oss << "\n";
        return oss.str();
    }
};

// LABEL statement (defines a symbolic label for GOTO/GOSUB)
class LabelStatement : public Statement {
public:
    std::string labelName;

    explicit LabelStatement(const std::string& name) : labelName(name) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_LABEL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << ":" << labelName << "\n";
        return oss.str();
    }
};

// Time unit enum for AFTER/EVERY statements
enum class TimeUnit {
    MILLISECONDS,  // MS
    SECONDS,       // SECS
    FRAMES         // FRAMES
};

// AFTER statement (AFTER duration [MS|SECS|FRAMES] CALL handler | DO...DONE)
class AfterStatement : public Statement {
public:
    ExpressionPtr duration;      // Duration value
    TimeUnit unit;               // Time unit (MS, SECS, or FRAMES)
    std::string handlerName;     // Handler function/sub name
    std::vector<StatementPtr> inlineBody;  // Optional inline body for DO...DONE
    bool isInlineHandler;        // True if using DO...DONE syntax, false if using CALL

    AfterStatement() : unit(TimeUnit::MILLISECONDS), isInlineHandler(false) {}
    AfterStatement(ExpressionPtr dur, TimeUnit u, const std::string& handler)
        : duration(std::move(dur)), unit(u), handlerName(handler), isInlineHandler(false) {}
    AfterStatement(ExpressionPtr dur, TimeUnit u, const std::string& handler, std::vector<StatementPtr> body)
        : duration(std::move(dur)), unit(u), handlerName(handler), inlineBody(std::move(body)), isInlineHandler(true) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_AFTER; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "AFTER " << duration->toString();
        switch (unit) {
            case TimeUnit::MILLISECONDS: oss << " MS"; break;
            case TimeUnit::SECONDS: oss << " SECS"; break;
            case TimeUnit::FRAMES: oss << " FRAMES"; break;
        }
        if (inlineBody.empty()) {
            oss << " CALL " << handlerName << "\n";
        } else {
            oss << " DO\n";
            for (const auto& stmt : inlineBody) {
                oss << stmt->toString(indent + 1);
            }
            oss << makeIndent(indent) << "DONE\n";
        }
        return oss.str();
    }
};

// EVERY statement (EVERY duration [MS|SECS|FRAMES] CALL handler | DO...DONE)
class EveryStatement : public Statement {
public:
    ExpressionPtr duration;      // Duration value
    TimeUnit unit;               // Time unit (MS, SECS, or FRAMES)
    std::string handlerName;     // Handler function/sub name
    std::vector<StatementPtr> inlineBody;  // Optional inline body for DO...DONE
    bool isInlineHandler;        // True if using DO...DONE syntax, false if using CALL

    EveryStatement() : unit(TimeUnit::MILLISECONDS), isInlineHandler(false) {}
    EveryStatement(ExpressionPtr dur, TimeUnit u, const std::string& handler)
        : duration(std::move(dur)), unit(u), handlerName(handler), isInlineHandler(false) {}
    EveryStatement(ExpressionPtr dur, TimeUnit u, const std::string& handler, std::vector<StatementPtr> body)
        : duration(std::move(dur)), unit(u), handlerName(handler), inlineBody(std::move(body)), isInlineHandler(true) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_EVERY; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "EVERY " << duration->toString();
        switch (unit) {
            case TimeUnit::MILLISECONDS: oss << " MS"; break;
            case TimeUnit::SECONDS: oss << " SECS"; break;
            case TimeUnit::FRAMES: oss << " FRAMES"; break;
        }
        if (inlineBody.empty()) {
            oss << " CALL " << handlerName << "\n";
        } else {
            oss << " DO\n";
            for (const auto& stmt : inlineBody) {
                oss << stmt->toString(indent + 1);
            }
            oss << makeIndent(indent) << "DONE\n";
        }
        return oss.str();
    }
};

// AFTERFRAMES statement (AFTERFRAMES count CALL handler)
class AfterFramesStatement : public Statement {
public:
    ExpressionPtr frameCount;    // Number of frames to wait
    std::string handlerName;     // Handler function/sub name

    AfterFramesStatement() = default;
    AfterFramesStatement(ExpressionPtr count, const std::string& handler)
        : frameCount(std::move(count)), handlerName(handler) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_AFTERFRAMES; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "AFTERFRAMES " << frameCount->toString() 
            << " CALL " << handlerName << "\n";
        return oss.str();
    }
};

// EVERYFRAME statement (EVERYFRAME count CALL handler)
class EveryFrameStatement : public Statement {
public:
    ExpressionPtr frameCount;    // Number of frames between fires
    std::string handlerName;     // Handler function/sub name

    EveryFrameStatement() = default;
    EveryFrameStatement(ExpressionPtr count, const std::string& handler)
        : frameCount(std::move(count)), handlerName(handler) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_EVERYFRAME; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "EVERYFRAME " << frameCount->toString() 
            << " CALL " << handlerName << "\n";
        return oss.str();
    }
};

// RUN statement - main event loop that runs until quit
class RunStatement : public Statement {
public:
    ExpressionPtr untilCondition;  // Optional UNTIL condition
    
    RunStatement() = default;
    explicit RunStatement(ExpressionPtr condition) 
        : untilCondition(std::move(condition)) {}
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_RUN; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "RUN";
        if (untilCondition) {
            oss << " UNTIL " << untilCondition->toString();
        }
        oss << "\n";
        return oss.str();
    }
};

// TIMER STOP statement (TIMER STOP handler|timer_id|ALL)
class TimerStopStatement : public Statement {
public:
    enum class StopTarget {
        HANDLER,     // Stop by handler name
        TIMER_ID,    // Stop by timer ID
        ALL          // Stop all timers
    };

    StopTarget targetType;
    std::string handlerName;     // For HANDLER type
    ExpressionPtr timerId;       // For TIMER_ID type

    TimerStopStatement() : targetType(StopTarget::ALL) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_TIMER_STOP; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "TIMER STOP ";
        if (targetType == StopTarget::ALL) {
            oss << "ALL";
        } else if (targetType == StopTarget::HANDLER) {
            oss << handlerName;
        } else {
            oss << timerId->toString();
        }
        oss << "\n";
        return oss.str();
    }
};

// TIMER INTERVAL statement (TIMER INTERVAL value)
class TimerIntervalStatement : public Statement {
public:
    ExpressionPtr interval;      // Interval value (instruction count)

    TimerIntervalStatement() = default;
    TimerIntervalStatement(ExpressionPtr val)
        : interval(std::move(val)) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_TIMER_INTERVAL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "TIMER INTERVAL ";
        if (interval) {
            oss << interval->toString();
        }
        oss << "\n";
        return oss.str();
    }
};

// PLAY statement (PLAY "filename" [AS format])
class PlayStatement : public Statement {
public:
    ExpressionPtr filename;      // The filename/path to play
    std::string format;          // Optional format override ("abc", "sid", "wav", "voicescript")
    bool hasFormat;              // true if AS format clause was specified
    ExpressionPtr wavOutput;     // Optional WAV output filename for INTO_WAV clause
    bool hasWavOutput;           // true if INTO_WAV clause was specified
    ExpressionPtr slotNumber;    // Optional slot number for INTO_SLOT clause
    bool hasSlot;                // true if INTO_SLOT clause was specified
    bool fastRender;             // true if FAST render mode requested

    PlayStatement() : hasFormat(false), hasWavOutput(false), hasSlot(false), fastRender(false) {}
    explicit PlayStatement(ExpressionPtr file) 
        : filename(std::move(file)), hasFormat(false), hasWavOutput(false), hasSlot(false), fastRender(false) {}
    PlayStatement(ExpressionPtr file, const std::string& fmt)
        : filename(std::move(file)), format(fmt), hasFormat(true), hasWavOutput(false), hasSlot(false), fastRender(false) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_PLAY; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "PLAY ";
        if (filename) {
            oss << filename->toString(0);
        }
        if (hasFormat) {
            oss << " AS " << format;
        }
        if (hasWavOutput && wavOutput) {
            oss << " INTO_WAV " << wavOutput->toString(0);
        }
        if (hasSlot && slotNumber) {
            oss << " INTO_SLOT " << slotNumber->toString(0);
        }
        if (fastRender) {
            oss << " FAST";
        }
        oss << "\n";
        return oss.str();
    }
};

// PLAY_SOUND statement
class PlaySoundStatement : public Statement {
public:
    ExpressionPtr soundId;        // Sound slot ID
    ExpressionPtr volume;         // Volume (0.0 to 1.0)
    ExpressionPtr capDuration;    // Optional: cap duration with fade-out
    bool hasCapDuration;          // true if cap duration specified

    PlaySoundStatement() : hasCapDuration(false) {}
    explicit PlaySoundStatement(ExpressionPtr id, ExpressionPtr vol)
        : soundId(std::move(id)), volume(std::move(vol)), hasCapDuration(false) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_PLAY_SOUND; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "PLAY_SOUND ";
        if (soundId) {
            oss << soundId->toString(0);
        }
        if (volume) {
            oss << ", " << volume->toString(0);
        }
        if (hasCapDuration && capDuration) {
            oss << ", " << capDuration->toString(0);
        }
        oss << "\n";
        return oss.str();
    }
};

// EXIT statement (EXIT FOR, EXIT FUNCTION, EXIT SUB)
class ExitStatement : public Statement {
public:
    enum class ExitType {
        FOR_LOOP,
        DO_LOOP,
        WHILE_LOOP,
        REPEAT_LOOP,
        FUNCTION,
        SUB
    };

    ExitType exitType;

    explicit ExitStatement(ExitType type) : exitType(type) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_EXIT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "EXIT ";
        switch (exitType) {
            case ExitType::FOR_LOOP: oss << "FOR"; break;
            case ExitType::DO_LOOP: oss << "DO"; break;
            case ExitType::WHILE_LOOP: oss << "WHILE"; break;
            case ExitType::REPEAT_LOOP: oss << "REPEAT"; break;
            case ExitType::FUNCTION: oss << "FUNCTION"; break;
            case ExitType::SUB: oss << "SUB"; break;
        }
        oss << "\n";
        return oss.str();
    }
};

// IF statement
class IfStatement : public Statement {
public:
    struct ElseIfClause {
        ExpressionPtr condition;
        std::vector<StatementPtr> statements;

        ElseIfClause() = default;
    };

    ExpressionPtr condition;
    std::vector<StatementPtr> thenStatements;
    std::vector<ElseIfClause> elseIfClauses;
    std::vector<StatementPtr> elseStatements;
    int gotoLine;       // For IF...THEN lineNumber
    bool hasGoto;
    bool isMultiLine;   // True for IF...ENDIF blocks

    IfStatement() : gotoLine(0), hasGoto(false), isMultiLine(false) {}

    void addThenStatement(StatementPtr stmt) {
        thenStatements.push_back(std::move(stmt));
    }

    void addElseStatement(StatementPtr stmt) {
        elseStatements.push_back(std::move(stmt));
    }

    void addElseIfClause(ExpressionPtr cond) {
        ElseIfClause clause;
        clause.condition = std::move(cond);
        elseIfClauses.push_back(std::move(clause));
    }

    void addElseIfStatement(StatementPtr stmt) {
        if (!elseIfClauses.empty()) {
            elseIfClauses.back().statements.push_back(std::move(stmt));
        }
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_IF; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "IF\n";
        oss << makeIndent(indent + 1) << "Condition:\n";
        oss << condition->toString(indent + 2);

        if (hasGoto) {
            oss << makeIndent(indent + 1) << "THEN GOTO " << gotoLine << "\n";
        } else if (!thenStatements.empty()) {
            oss << makeIndent(indent + 1) << "THEN:\n";
            for (const auto& stmt : thenStatements) {
                oss << stmt->toString(indent + 2);
            }
        }

        if (!elseIfClauses.empty()) {
            for (const auto& elseif : elseIfClauses) {
                oss << makeIndent(indent + 1) << "ELSEIF\n";
                oss << makeIndent(indent + 2) << "Condition:\n";
                oss << elseif.condition->toString(indent + 3);
                oss << makeIndent(indent + 2) << "THEN:\n";
                for (const auto& stmt : elseif.statements) {
                    oss << stmt->toString(indent + 3);
                }
            }
        }

        if (!elseStatements.empty()) {
            oss << makeIndent(indent + 1) << "ELSE:\n";
            for (const auto& stmt : elseStatements) {
                oss << stmt->toString(indent + 2);
            }
        }

        return oss.str();
    }
};

// CASE statement (CASE expression OF ... ENDCASE)
class CaseStatement : public Statement {
public:
    struct WhenClause {
        std::vector<ExpressionPtr> values;  // Multiple values for WHEN 1, 2, 3 or single condition for CASE IS
        bool isCaseIs;                      // true for CASE IS conditions, false for regular CASE values
        TokenType caseIsOperator;           // Operator for CASE IS (e.g., GREATER_EQUAL)
        ExpressionPtr caseIsRightExpr;      // Right operand for CASE IS
        bool isRange;                       // true for CASE x TO y range syntax
        ExpressionPtr rangeStart;           // Start value for range (CASE x TO y)
        ExpressionPtr rangeEnd;             // End value for range (CASE x TO y)
        std::vector<StatementPtr> statements;

        WhenClause() : isCaseIs(false), caseIsOperator(TokenType::UNKNOWN), isRange(false) {}
    };

    ExpressionPtr caseExpression;  // The expression after CASE (e.g., TRUE)
    std::vector<WhenClause> whenClauses;
    std::vector<StatementPtr> otherwiseStatements;

    CaseStatement() = default;

    void addWhenClause(std::vector<ExpressionPtr> values, bool caseIs = false) {
        WhenClause clause;
        clause.values = std::move(values);
        clause.isCaseIs = caseIs;
        whenClauses.push_back(std::move(clause));
    }

    void addWhenStatement(StatementPtr stmt) {
        if (!whenClauses.empty()) {
            whenClauses.back().statements.push_back(std::move(stmt));
        }
    }

    void addOtherwiseStatement(StatementPtr stmt) {
        otherwiseStatements.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_CASE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CASE\n";

        if (caseExpression) {
            oss << makeIndent(indent + 1) << "Expression:\n";
            oss << caseExpression->toString(indent + 2);
        }

        for (const auto& clause : whenClauses) {
            oss << makeIndent(indent + 1) << "WHEN:\n";
            oss << makeIndent(indent + 2) << "Values:\n";
            for (const auto& value : clause.values) {
                oss << value->toString(indent + 3);
            }
            oss << makeIndent(indent + 2) << "Statements:\n";
            for (const auto& stmt : clause.statements) {
                oss << stmt->toString(indent + 3);
            }
        }

        if (!otherwiseStatements.empty()) {
            oss << makeIndent(indent + 1) << "OTHERWISE:\n";
            for (const auto& stmt : otherwiseStatements) {
                oss << stmt->toString(indent + 2);
            }
        }

        return oss.str();
    }
};

// MATCH TYPE statement (safe type dispatch for LIST OF ANY)
class MatchTypeStatement : public Statement {
public:
    // A single CASE arm: CASE INTEGER n%, CASE STRING s$, etc.
    struct CaseArm {
        std::string typeKeyword;           // "INTEGER", "DOUBLE", "STRING", "LIST", "OBJECT", "LONG", "SINGLE", or a class/UDT name
        int atomTypeTag;                   // ATOM_INT=1, ATOM_FLOAT=2, ATOM_STRING=3, ATOM_LIST=4, ATOM_OBJECT=5
        std::string bindingVariable;       // e.g. "n%", "s$", "f#", "sub"
        TokenType bindingSuffix;           // Suffix token type for the binding variable
        std::vector<StatementPtr> body;    // Statements in this arm

        // --- Extended type matching (class / UDT / basic type) ---
        // When isClassMatch is true, matchClassName holds the specific CLASS name
        // and codegen will emit a class_is_instance() runtime check in addition
        // to the ATOM_OBJECT tag check.  This supports inheritance: CASE Dog
        // will match any Dog or subclass-of-Dog object.
        bool isClassMatch = false;         // true if CASE <ClassName> (not generic OBJECT)
        std::string matchClassName;        // Specific class name (e.g. "DOG", "CAT"); empty for generic OBJECT

        // When isUDTMatch is true, udtTypeName holds the TYPE name.
        // UDTs are value types so this is resolved via static type info the
        // compiler already knows.  Useful for future variant / tagged-union
        // support or for statically-typed MATCH TYPE on non-list expressions.
        bool isUDTMatch = false;           // true if CASE <UDTName>
        std::string udtTypeName;           // UDT type name (e.g. "VEC3"); empty if not a UDT match

        CaseArm() : atomTypeTag(0), bindingSuffix(TokenType::UNKNOWN) {}
    };

    ExpressionPtr matchExpression;         // The expression after MATCH TYPE
    std::vector<CaseArm> caseArms;         // Typed case arms
    std::vector<StatementPtr> caseElseBody; // Optional CASE ELSE body

    MatchTypeStatement() = default;

    void addCaseArm(CaseArm arm) {
        caseArms.push_back(std::move(arm));
    }

    void addCaseElseStatement(StatementPtr stmt) {
        caseElseBody.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_MATCH_TYPE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "MATCH TYPE\n";

        if (matchExpression) {
            oss << makeIndent(indent + 1) << "Expression:\n";
            oss << matchExpression->toString(indent + 2);
        }

        for (const auto& arm : caseArms) {
            oss << makeIndent(indent + 1) << "CASE " << arm.typeKeyword
                << " " << arm.bindingVariable;
            if (arm.isClassMatch) {
                oss << " [class=" << arm.matchClassName << "]";
            }
            if (arm.isUDTMatch) {
                oss << " [udt=" << arm.udtTypeName << "]";
            }
            oss << "\n";
            for (const auto& stmt : arm.body) {
                oss << stmt->toString(indent + 2);
            }
        }

        if (!caseElseBody.empty()) {
            oss << makeIndent(indent + 1) << "CASE ELSE\n";
            for (const auto& stmt : caseElseBody) {
                oss << stmt->toString(indent + 2);
            }
        }

        oss << makeIndent(indent) << "END MATCH\n";
        return oss.str();
    }
};

// FOR statement
class ForStatement : public Statement {
public:
    std::string variable;          // Loop variable name (plain, no suffix)
    ExpressionPtr start;
    ExpressionPtr end;
    ExpressionPtr step;            // nullptr if no STEP clause
    std::vector<StatementPtr> body;  // Loop body statements

    ForStatement(const std::string& var) : variable(var) {}

    void addBodyStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_FOR; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "FOR " << variable << "\n";
        oss << makeIndent(indent + 1) << "Start:\n";
        oss << start->toString(indent + 2);
        oss << makeIndent(indent + 1) << "End:\n";
        oss << end->toString(indent + 2);
        if (step) {
            oss << makeIndent(indent + 1) << "Step:\n";
            oss << step->toString(indent + 2);
        }
        if (!body.empty()) {
            oss << makeIndent(indent + 1) << "Body:\n";
            for (const auto& stmt : body) {
                oss << stmt->toString(indent + 2);
            }
        }
        return oss.str();
    }
};

// FOR...IN statement
class ForInStatement : public Statement {
public:
    std::string variable;        // Loop variable name
    std::string indexVariable;  // Optional index variable name (empty if not used)
    ExpressionPtr array;         // Array expression to iterate over
    int inferredType;            // Inferred element type from array (stored as int, cast to VariableType)
    std::vector<StatementPtr> body;  // Loop body statements

    ForInStatement(const std::string& var) : variable(var), inferredType(0) {}
    ForInStatement(const std::string& var, const std::string& indexVar) 
        : variable(var), indexVariable(indexVar), inferredType(0) {}

    void addBodyStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_FOR_IN; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "FOR " << variable;
        if (!indexVariable.empty()) {
            oss << ", " << indexVariable;
        }
        oss << " IN\n";
        oss << makeIndent(indent + 1) << "Array:\n";
        oss << array->toString(indent + 2);
        return oss.str();
    }
};

// NEXT statement
class NextStatement : public Statement {
public:
    std::string variable;  // Can be empty

    NextStatement() = default;
    explicit NextStatement(const std::string& var) : variable(var) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_NEXT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "NEXT";
        if (!variable.empty()) {
            oss << " " << variable;
        }
        oss << "\n";
        return oss.str();
    }
};

// WHILE statement
class WhileStatement : public Statement {
public:
    ExpressionPtr condition;
    std::vector<StatementPtr> body;  // Loop body statements

    WhileStatement() = default;

    void addBodyStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_WHILE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "WHILE\n";
        oss << condition->toString(indent + 1);
        if (!body.empty()) {
            oss << makeIndent(indent + 1) << "Body:\n";
            for (const auto& stmt : body) {
                oss << stmt->toString(indent + 2);
            }
        }
        return oss.str();
    }
};

// WEND statement
class WendStatement : public Statement {
public:
    WendStatement() = default;

    ASTNodeType getType() const override { return ASTNodeType::STMT_WEND; }

    std::string toString(int indent = 0) const override {
        return makeIndent(indent) + "WEND\n";
    }
};

// REPEAT statement
class RepeatStatement : public Statement {
public:
    std::vector<StatementPtr> body;  // Loop body statements
    ExpressionPtr condition;         // UNTIL condition (moved from UntilStatement)

    RepeatStatement() = default;

    void addBodyStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_REPEAT; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "REPEAT\n";
        if (!body.empty()) {
            for (const auto& stmt : body) {
                oss << stmt->toString(indent + 1);
            }
        }
        if (condition) {
            oss << makeIndent(indent) << "UNTIL\n";
            oss << condition->toString(indent + 1);
        }
        return oss.str();
    }
};

// UNTIL statement
class UntilStatement : public Statement {
public:
    ExpressionPtr condition;

    UntilStatement() = default;

    ASTNodeType getType() const override { return ASTNodeType::STMT_UNTIL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "UNTIL\n";
        oss << condition->toString(indent + 1);
        return oss.str();
    }
};

// DO statement (supports DO WHILE, DO UNTIL, or plain DO)
class DoStatement : public Statement {
public:
    enum class ConditionType {
        NONE,     // Plain DO (infinite loop until EXIT)
        WHILE,    // DO WHILE condition
        UNTIL     // DO UNTIL condition
    };

    ConditionType preConditionType;   // Condition at DO (pre-test)
    ExpressionPtr preCondition;       // Pre-test condition
    ConditionType postConditionType;  // Condition at LOOP (post-test)
    ExpressionPtr postCondition;      // Post-test condition
    std::vector<StatementPtr> body;   // Loop body statements

    DoStatement() : preConditionType(ConditionType::NONE), 
                    postConditionType(ConditionType::NONE) {}

    void addBodyStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_DO; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DO";

        if (preConditionType == ConditionType::WHILE) {
            oss << " WHILE\n";
            if (preCondition) {
                oss << preCondition->toString(indent + 1);
            }
        } else if (preConditionType == ConditionType::UNTIL) {
            oss << " UNTIL\n";
            if (preCondition) {
                oss << preCondition->toString(indent + 1);
            }
        } else {
            oss << "\n";
        }

        if (!body.empty()) {
            for (const auto& stmt : body) {
                oss << stmt->toString(indent + 1);
            }
        }

        oss << makeIndent(indent) << "LOOP";
        if (postConditionType == ConditionType::WHILE) {
            oss << " WHILE\n";
            if (postCondition) {
                oss << postCondition->toString(indent + 1);
            }
        } else if (postConditionType == ConditionType::UNTIL) {
            oss << " UNTIL\n";
            if (postCondition) {
                oss << postCondition->toString(indent + 1);
            }
        } else {
            oss << "\n";
        }

        return oss.str();
    }
};

// LOOP statement (supports LOOP WHILE, LOOP UNTIL, or plain LOOP)
class LoopStatement : public Statement {
public:
    enum class ConditionType {
        NONE,     // Plain LOOP
        WHILE,    // LOOP WHILE condition
        UNTIL     // LOOP UNTIL condition
    };

    ConditionType conditionType;
    ExpressionPtr condition;  // nullptr if NONE

    LoopStatement() : conditionType(ConditionType::NONE) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_LOOP; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "LOOP";

        if (conditionType == ConditionType::WHILE) {
            oss << " WHILE\n";
            if (condition) {
                oss << condition->toString(indent + 1);
            }
        } else if (conditionType == ConditionType::UNTIL) {
            oss << " UNTIL\n";
            if (condition) {
                oss << condition->toString(indent + 1);
            }
        } else {
            oss << "\n";
        }

        return oss.str();
    }
};

// END statement
class EndStatement : public Statement {
public:
    EndStatement() = default;

    ASTNodeType getType() const override { return ASTNodeType::STMT_END; }

    std::string toString(int indent = 0) const override {
        return makeIndent(indent) + "END\n";
    }
};

// TRY/CATCH/FINALLY statement
class TryCatchStatement : public Statement {
public:
    std::vector<StatementPtr> tryBlock;
    
    struct CatchClause {
        std::vector<int32_t> errorCodes;  // Error codes to catch (empty = catch all)
        std::vector<StatementPtr> block;
        
        CatchClause() = default;
    };
    std::vector<CatchClause> catchClauses;
    
    std::vector<StatementPtr> finallyBlock;
    bool hasFinally;
    
    TryCatchStatement() : hasFinally(false) {}
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_TRY_CATCH; }
    
    std::string toString(int indent = 0) const override {
        std::string result = makeIndent(indent) + "TRY\n";
        for (const auto& stmt : tryBlock) {
            result += stmt->toString(indent + 2);
        }
        for (const auto& clause : catchClauses) {
            result += makeIndent(indent) + "CATCH";
            if (!clause.errorCodes.empty()) {
                result += " ";
                for (size_t i = 0; i < clause.errorCodes.size(); i++) {
                    if (i > 0) result += ", ";
                    result += std::to_string(clause.errorCodes[i]);
                }
            }
            result += "\n";
            for (const auto& stmt : clause.block) {
                result += stmt->toString(indent + 2);
            }
        }
        if (hasFinally) {
            result += makeIndent(indent) + "FINALLY\n";
            for (const auto& stmt : finallyBlock) {
                result += stmt->toString(indent + 2);
            }
        }
        result += makeIndent(indent) + "END TRY\n";
        return result;
    }
};

// THROW statement
class ThrowStatement : public Statement {
public:
    ExpressionPtr errorCode;
    
    ThrowStatement() = default;
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_THROW; }
    
    std::string toString(int indent = 0) const override {
        std::string result = makeIndent(indent) + "THROW ";
        if (errorCode) {
            result += errorCode->toString(0);
        }
        result += "\n";
        return result;
    }
};

// DIM statement
class DimStatement : public Statement {
public:
    struct ArrayDim {
        std::string name;
        TokenType typeSuffix;
        std::vector<ExpressionPtr> dimensions;
        std::string asTypeName;        // For AS TypeName declarations (user-defined types)
        TokenType asTypeKeyword;       // For AS built-in type keywords (preserves UBYTE vs BYTE, etc.)
        bool hasAsType;                // true if AS TypeName was specified
        ExpressionPtr initializer;     // For DIM x AS Foo = NEW Foo() (class instance init)

        ArrayDim(const std::string& n, TokenType suffix = TokenType::UNKNOWN)
            : name(n), typeSuffix(suffix), asTypeKeyword(TokenType::UNKNOWN), hasAsType(false) {}
    };

    std::vector<ArrayDim> arrays;

    DimStatement() = default;

    void addArray(const std::string& name, TokenType suffix = TokenType::UNKNOWN) {
        arrays.emplace_back(name, suffix);
    }

    void addDimension(ExpressionPtr dim) {
        if (!arrays.empty()) {
            arrays.back().dimensions.push_back(std::move(dim));
        }
    }
    
    void setAsType(const std::string& typeName) {
        if (!arrays.empty()) {
            arrays.back().asTypeName = typeName;
            arrays.back().hasAsType = true;
        }
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_DIM; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DIM\n";
        for (const auto& arr : arrays) {
            oss << makeIndent(indent + 1) << arr.name;
            if (arr.typeSuffix != TokenType::UNKNOWN) {
                oss << tokenTypeToString(arr.typeSuffix);
            }
            if (!arr.dimensions.empty()) {
                oss << "(";
                for (size_t i = 0; i < arr.dimensions.size(); ++i) {
                    if (i > 0) oss << ", ";
                    oss << "dim" << i;
                }
                oss << ")";
            }
            if (arr.hasAsType) {
                oss << " AS " << arr.asTypeName;
            }
            oss << "\n";
            for (const auto& dim : arr.dimensions) {
                oss << dim->toString(indent + 2);
            }
        }
        return oss.str();
    }
};

// REDIM statement (resize array dynamically)
class RedimStatement : public Statement {
public:
    struct ArrayRedim {
        std::string name;
        std::vector<ExpressionPtr> dimensions;
        
        ArrayRedim(const std::string& n) : name(n) {}
    };
    
    std::vector<ArrayRedim> arrays;
    bool preserve;  // true for REDIM PRESERVE
    
    RedimStatement() : preserve(false) {}
    
    void addArray(const std::string& name) {
        arrays.emplace_back(name);
    }
    
    void addDimension(ExpressionPtr dim) {
        if (!arrays.empty()) {
            arrays.back().dimensions.push_back(std::move(dim));
        }
    }
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_REDIM; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "REDIM";
        if (preserve) oss << " PRESERVE";
        oss << "\n";
        for (const auto& arr : arrays) {
            oss << makeIndent(indent + 1) << arr.name;
            if (!arr.dimensions.empty()) {
                oss << "(";
                for (size_t i = 0; i < arr.dimensions.size(); ++i) {
                    if (i > 0) oss << ", ";
                    oss << "dim" << i;
                }
                oss << ")";
            }
            oss << "\n";
            for (const auto& dim : arr.dimensions) {
                oss << dim->toString(indent + 2);
            }
        }
        return oss.str();
    }
};

// ERASE statement (clear/deallocate array)
class EraseStatement : public Statement {
public:
    std::vector<std::string> arrayNames;
    
    EraseStatement() = default;
    
    void addArray(const std::string& name) {
        arrayNames.push_back(name);
    }
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_ERASE; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "ERASE ";
        for (size_t i = 0; i < arrayNames.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << arrayNames[i];
        }
        oss << "\n";
        return oss.str();
    }
};

// SWAP statement (swap two variables)
class SwapStatement : public Statement {
public:
    std::string var1;
    std::string var2;
    
    SwapStatement(const std::string& v1, const std::string& v2) 
        : var1(v1), var2(v2) {}
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_SWAP; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "SWAP " << var1 << ", " << var2 << "\n";
        return oss.str();
    }
};

// INC statement (increment variable)
class IncStatement : public Statement {
public:
    std::string varName;
    std::vector<ExpressionPtr> indices;  // For array elements
    std::vector<std::string> memberChain;  // For member access (e.g., P.X.Y)
    ExpressionPtr incrementExpr;  // Optional increment amount (defaults to 1)
    
    IncStatement(const std::string& var, ExpressionPtr incr = nullptr) 
        : varName(var), incrementExpr(std::move(incr)) {}
    
    void addIndex(ExpressionPtr idx) {
        indices.push_back(std::move(idx));
    }
    
    void addMember(const std::string& member) {
        memberChain.push_back(member);
    }
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_INC; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "INC " << varName;
        if (!indices.empty()) {
            oss << "[array]";
        }
        for (const auto& member : memberChain) {
            oss << "." << member;
        }
        if (incrementExpr) {
            oss << ", " << incrementExpr->toString();
        }
        oss << "\n";
        return oss.str();
    }
};

// DEC statement (decrement variable)
class DecStatement : public Statement {
public:
    std::string varName;
    std::vector<ExpressionPtr> indices;  // For array elements
    std::vector<std::string> memberChain;  // For member access (e.g., P.X.Y)
    ExpressionPtr decrementExpr;  // Optional decrement amount (defaults to 1)
    
    DecStatement(const std::string& var, ExpressionPtr decr = nullptr) 
        : varName(var), decrementExpr(std::move(decr)) {}
    
    void addIndex(ExpressionPtr idx) {
        indices.push_back(std::move(idx));
    }
    
    void addMember(const std::string& member) {
        memberChain.push_back(member);
    }
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_DEC; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DEC " << varName;
        if (!indices.empty()) {
            oss << "[array]";
        }
        for (const auto& member : memberChain) {
            oss << "." << member;
        }
        if (decrementExpr) {
            oss << ", " << decrementExpr->toString();
        }
        oss << "\n";
        return oss.str();
    }
};

// TYPE declaration statement
class TypeDeclarationStatement : public Statement {
public:
    // SIMD type classification for ARM NEON acceleration
    enum class SIMDType {
        NONE,    // Not SIMD-capable
        PAIR,    // 2 consecutive doubles (Vec2D, Position, etc.) — legacy alias for V2D
        QUAD,    // 4 consecutive floats (Color, Vec4F, etc.) — legacy alias for V4S

        // Full 128-bit Q register configurations
        V2D,     // 2 × 64-bit (DOUBLE or LONG)  — 128 bits
        V4S,     // 4 × 32-bit (INTEGER or SINGLE) — 128 bits
        V8H,     // 8 × 16-bit (SHORT)            — 128 bits
        V16B,    // 16 × 8-bit (BYTE)             — 128 bits

        // Half-register (64-bit D register) configurations
        V2S,     // 2 × 32-bit — 64 bits
        V4H,     // 4 × 16-bit — 64 bits
        V8B,     // 8 × 8-bit  — 64 bits

        // Padded configurations (3 real + 1 padding lane)
        V4S_PAD1 // 3 × 32-bit padded to 4 lanes — 128 bits
    };

    // Descriptor carrying all SIMD classification info for a UDT
    struct SIMDInfo {
        SIMDType type       = SIMDType::NONE;
        int laneCount       = 0;   // logical field count
        int physicalLanes   = 0;   // actual NEON lanes (may be > laneCount for padded)
        int laneBitWidth    = 0;   // bits per lane (8, 16, 32, 64)
        int totalBytes      = 0;   // bytes occupied in a NEON register
        bool isFullQ        = false; // true if uses full 128-bit Q register
        bool isPadded       = false; // true if padding lane exists
        bool isFloatingPoint = false;
        // Base type of each lane (INTEGER, SINGLE, DOUBLE, BYTE, etc.)
        // We use an int here to avoid circular header dependencies;
        // the value is a BaseType cast to int.
        int laneBaseType    = 0;   // BaseType::UNKNOWN == 0

        // Helper: NEON arrangement suffix string (e.g. "4s", "2d")
        const char* arrangement() const {
            switch (type) {
                case SIMDType::V4S: case SIMDType::V4S_PAD1: return "4s";
                case SIMDType::V2D:  return "2d";
                case SIMDType::V2S:  return "2s";
                case SIMDType::V8H:  return "8h";
                case SIMDType::V4H:  return "4h";
                case SIMDType::V16B: return "16b";
                case SIMDType::V8B:  return "8b";
                case SIMDType::PAIR: return "2d";
                case SIMDType::QUAD: return "4s";
                default: return "";
            }
        }

        // Helper: register prefix for the occupied width
        const char* regPrefix() const {
            return isFullQ ? "q" : "d";
        }

        bool isValid() const { return type != SIMDType::NONE; }
    };
    
    struct TypeField {
        std::string name;
        std::string typeName;      // "INT", "FLOAT", "DOUBLE", "STRING", or user-defined type name
        TokenType builtInType;     // For built-in types: TYPE_INT, TYPE_FLOAT, etc.
        bool isBuiltIn;            // true if built-in type, false if user-defined
        
        TypeField(const std::string& n, const std::string& tname, TokenType btype, bool builtin)
            : name(n), typeName(tname), builtInType(btype), isBuiltIn(builtin) {}
    };
    
    std::string typeName;          // Name of the type being declared
    std::vector<TypeField> fields; // Fields in the type
    SIMDType simdType;             // Detected SIMD type (set during semantic analysis)
    SIMDInfo simdInfo;             // Full SIMD descriptor (set during semantic analysis)
    
    explicit TypeDeclarationStatement(const std::string& name) 
        : typeName(name), simdType(SIMDType::NONE), simdInfo() {}
    
    void addField(const std::string& fieldName, const std::string& fieldTypeName, 
                  TokenType builtInType, bool isBuiltIn) {
        fields.emplace_back(fieldName, fieldTypeName, builtInType, isBuiltIn);
    }
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_TYPE; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "TYPE " << typeName;
        if (simdInfo.isValid()) {
            oss << " [SIMD:" << simdInfo.arrangement()
                << " " << simdInfo.laneCount << "x" << simdInfo.laneBitWidth << "b"
                << (simdInfo.isPadded ? " PAD" : "") << "]";
        } else if (simdType == SIMDType::PAIR) {
            oss << " [SIMD:PAIR]";
        } else if (simdType == SIMDType::QUAD) {
            oss << " [SIMD:QUAD]";
        }
        oss << "\n";
        for (const auto& field : fields) {
            oss << makeIndent(indent + 1) << field.name << " AS " << field.typeName << "\n";
        }
        oss << makeIndent(indent) << "END TYPE\n";
        return oss.str();
    }
};

// REM statement (comment)
class RemStatement : public Statement {
public:
    std::string comment;

    explicit RemStatement(const std::string& text) : comment(text) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_REM; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "REM \"" << comment << "\"\n";
        return oss.str();
    }
};

// OPTION statement (compiler directive)
class OptionStatement : public Statement {
public:
    enum class OptionType {
        BITWISE,
        LOGICAL,
        BASE,
        EXPLICIT,
        UNICODE,
        ASCII,
        DETECTSTRING,
        ERROR,
        CANCELLABLE,
        BOUNDS_CHECK,
        SAMM
    };

    OptionType type;
    int value;  // For OPTION BASE n

    OptionStatement(OptionType t, int v = 0) : type(t), value(v) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_OPTION; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "OPTION ";
        switch (type) {
            case OptionType::BITWISE: oss << "BITWISE"; break;
            case OptionType::LOGICAL: oss << "LOGICAL"; break;
            case OptionType::BASE: oss << "BASE " << value; break;
            case OptionType::EXPLICIT: oss << "EXPLICIT"; break;
            case OptionType::UNICODE: oss << "UNICODE"; break;
            case OptionType::ASCII: oss << "ASCII"; break;
            case OptionType::DETECTSTRING: oss << "DETECTSTRING"; break;
            case OptionType::ERROR: oss << "ERROR"; break;
            case OptionType::CANCELLABLE: oss << "CANCELLABLE"; break;
            case OptionType::BOUNDS_CHECK: oss << "BOUNDS_CHECK"; break;
            case OptionType::SAMM: oss << "SAMM"; break;
        }
        oss << "\n";
        return oss.str();
    }
};

// Simple statement (CLS, GCLS, BEEP, etc. - no arguments)
class SimpleStatement : public Statement {
public:
    ASTNodeType nodeType;
    std::string name;

    SimpleStatement(ASTNodeType type, const std::string& n)
        : nodeType(type), name(n) {}

    ASTNodeType getType() const override { return nodeType; }

    std::string toString(int indent = 0) const override {
        return makeIndent(indent) + name + "\n";
    }
};

// Statement with expression arguments (COLOR, WAIT, PSET, etc.)
class ExpressionStatement : public Statement {
public:
    ASTNodeType nodeType;
    std::string name;
    std::vector<ExpressionPtr> arguments;

    ExpressionStatement(ASTNodeType type, const std::string& n)
        : nodeType(type), name(n) {}

    void addArgument(ExpressionPtr arg) {
        arguments.push_back(std::move(arg));
    }

    ASTNodeType getType() const override { return nodeType; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << name << "\n";
        for (const auto& arg : arguments) {
            oss << arg->toString(indent + 1);
        }
        return oss.str();
    }
};

// LOCAL statement (for explicit local variables in functions)
class LocalStatement : public Statement {
public:
    struct LocalVar {
        std::string name;
        TokenType typeSuffix;      // Type suffix from name ($, %, #, etc.) or AS type
        ExpressionPtr initialValue; // Optional initialization
        std::string asTypeName;    // For AS TypeName declarations (user-defined types)
        bool hasAsType;            // true if AS TypeName was specified

        LocalVar(const std::string& n, TokenType suffix = TokenType::UNKNOWN)
            : name(n), typeSuffix(suffix), hasAsType(false) {}
    };

    std::vector<LocalVar> variables;

    LocalStatement() = default;

    void addVariable(const std::string& name, TokenType suffix = TokenType::UNKNOWN) {
        variables.emplace_back(name, suffix);
    }

    void setInitialValue(ExpressionPtr value) {
        if (!variables.empty()) {
            variables.back().initialValue = std::move(value);
        }
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_LOCAL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "LOCAL\n";
        for (const auto& var : variables) {
            oss << makeIndent(indent + 1) << var.name;
            if (var.typeSuffix != TokenType::UNKNOWN) {
                oss << tokenTypeToString(var.typeSuffix);
            }
            if (var.hasAsType) {
                oss << " AS " << var.asTypeName;
            }
            if (var.initialValue) {
                oss << " = ";
                oss << var.initialValue->toString(0);
            }
            oss << "\n";
        }
        return oss.str();
    }
};

// GLOBAL statement (for declaring global variables accessible via SHARED)
class GlobalStatement : public Statement {
public:
    struct GlobalVar {
        std::string name;
        TokenType typeSuffix;      // Type suffix from name ($, %, #, etc.) or AS type
        ExpressionPtr initialValue; // Optional initialization
        std::string asTypeName;    // For AS TypeName declarations (user-defined types)
        bool hasAsType;            // true if AS TypeName was specified

        GlobalVar(const std::string& n, TokenType suffix = TokenType::UNKNOWN)
            : name(n), typeSuffix(suffix), hasAsType(false) {}
    };

    std::vector<GlobalVar> variables;

    GlobalStatement() = default;

    void addVariable(const std::string& name, TokenType suffix = TokenType::UNKNOWN) {
        variables.emplace_back(name, suffix);
    }

    void setInitialValue(ExpressionPtr value) {
        if (!variables.empty()) {
            variables.back().initialValue = std::move(value);
        }
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_GLOBAL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "GLOBAL\n";
        for (const auto& var : variables) {
            oss << makeIndent(indent + 1) << var.name;
            if (var.typeSuffix != TokenType::UNKNOWN) {
                oss << tokenTypeToString(var.typeSuffix);
            }
            if (var.hasAsType) {
                oss << " AS " << var.asTypeName;
            }
            if (var.initialValue) {
                oss << " = ";
                oss << var.initialValue->toString(0);
            }
            oss << "\n";
        }
        return oss.str();
    }
};

// SHARED statement (for accessing module-level variables in SUBs)
class SharedStatement : public Statement {
public:
    struct SharedVariable {
        std::string name;
        TokenType typeSuffix;
        std::string asTypeName;    // For AS TypeName declarations (user-defined types)
        bool hasAsType;            // true if AS TypeName was specified
        
        SharedVariable(const std::string& n, TokenType t = TokenType::UNKNOWN)
            : name(n), typeSuffix(t), hasAsType(false) {}
    };
    
    std::vector<SharedVariable> variables;
    
    SharedStatement() = default;
    
    void addVariable(const std::string& name, TokenType typeSuffix = TokenType::UNKNOWN) {
        variables.emplace_back(name, typeSuffix);
    }
    
    ASTNodeType getType() const override { return ASTNodeType::STMT_SHARED; }
    
    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "SHARED ";
        for (size_t i = 0; i < variables.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << variables[i].name;
            if (variables[i].hasAsType) {
                oss << " AS " << variables[i].asTypeName;
            }
        }
        oss << "\n";
        return oss.str();
    }
};

// Data statement
class DataStatement : public Statement {
public:
    std::vector<std::string> values;

    DataStatement() = default;

    void addValue(const std::string& val) {
        values.push_back(val);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_DATA; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DATA";
        for (size_t i = 0; i < values.size(); ++i) {
            if (i > 0) oss << ",";
            oss << " \"" << values[i] << "\"";
        }
        oss << "\n";
        return oss.str();
    }
};

// READ statement
class ReadStatement : public Statement {
public:
    std::vector<std::string> variables;

    ReadStatement() = default;

    void addVariable(const std::string& var) {
        variables.push_back(var);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_READ; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "READ";
        for (size_t i = 0; i < variables.size(); ++i) {
            if (i > 0) oss << ",";
            oss << " " << variables[i];
        }
        oss << "\n";
        return oss.str();
    }
};

// RESTORE statement
class RestoreStatement : public Statement {
public:
    int lineNumber;     // 0 if no line number specified
    std::string label;  // Empty if no label specified
    bool isLabel;       // True if using symbolic label instead of line number

    RestoreStatement() : lineNumber(0), isLabel(false) {}
    explicit RestoreStatement(int line) : lineNumber(line), isLabel(false) {}
    explicit RestoreStatement(const std::string& lbl) : lineNumber(0), label(lbl), isLabel(true) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_RESTORE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "RESTORE";
        if (isLabel) {
            oss << " :" << label;
        } else if (lineNumber > 0) {
            oss << " " << lineNumber;
        }
        oss << "\n";
        return oss.str();
    }
};

// DEF FN statement
class DefStatement : public Statement {
public:
    std::string functionName;
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterSuffixes;  // Track original type suffixes for type inference
    ExpressionPtr body;

    DefStatement(const std::string& name) : functionName(name) {}

    void addParameter(const std::string& param, TokenType suffix = TokenType::UNKNOWN) {
        parameters.push_back(param);
        parameterSuffixes.push_back(suffix);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_DEF; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DEF FN" << functionName << "(";
        for (size_t i = 0; i < parameters.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << parameters[i];
        }
        oss << ")\n";
        if (body) {
            oss << body->toString(indent + 1);
        }
        return oss.str();
    }
};

// FUNCTION statement (multi-statement function with return value)
class FunctionStatement : public Statement {
public:
    std::string functionName;
    TokenType returnTypeSuffix;
    std::string returnTypeAsName;        // For AS TypeName return types (user-defined or built-in)
    bool hasReturnAsType;                // true if AS TypeName was specified for return type
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterTypes;
    std::vector<std::string> parameterAsTypes;  // For AS TypeName parameters (parallel to parameters)
    std::vector<bool> parameterIsByRef;  // Track BYREF parameters
    std::vector<StatementPtr> body;

    FunctionStatement(const std::string& name, TokenType suffix = TokenType::UNKNOWN)
        : functionName(name), returnTypeSuffix(suffix), hasReturnAsType(false) {}

    void addParameter(const std::string& param, TokenType type = TokenType::UNKNOWN, bool isByRef = false, const std::string& asType = "") {
        parameters.push_back(param);
        parameterTypes.push_back(type);
        parameterAsTypes.push_back(asType);
        parameterIsByRef.push_back(isByRef);
    }

    void addStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_FUNCTION; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "FUNCTION " << functionName << "(";
        for (size_t i = 0; i < parameters.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << parameters[i];
        }
        oss << ")\n";
        for (const auto& stmt : body) {
            oss << stmt->toString(indent + 1);
        }
        oss << makeIndent(indent) << "END FUNCTION\n";
        return oss.str();
    }
};

// SUB statement (multi-statement subroutine without return value)
class SubStatement : public Statement {
public:
    std::string subName;
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterTypes;
    std::vector<std::string> parameterAsTypes;  // For AS TypeName parameters (parallel to parameters)
    std::vector<bool> parameterIsByRef;  // Track BYREF parameters
    std::vector<StatementPtr> body;

    SubStatement(const std::string& name) : subName(name) {}

    void addParameter(const std::string& param, TokenType type = TokenType::UNKNOWN, bool isByRef = false, const std::string& asType = "") {
        parameters.push_back(param);
        parameterTypes.push_back(type);
        parameterAsTypes.push_back(asType);
        parameterIsByRef.push_back(isByRef);
    }

    void addStatement(StatementPtr stmt) {
        body.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_SUB; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "SUB " << subName << "(";
        for (size_t i = 0; i < parameters.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << parameters[i];
        }
        oss << ")\n";
        for (const auto& stmt : body) {
            oss << stmt->toString(indent + 1);
        }
        oss << makeIndent(indent) << "END SUB\n";
        return oss.str();
    }
};

// CALL statement (call a SUB)
class CallStatement : public Statement {
public:
    std::string subName;
    std::vector<ExpressionPtr> arguments;
    ExpressionPtr methodCallExpr;  // For method call statements (e.g., dict.CLEAR())

    CallStatement(const std::string& name) : subName(name) {}

    void addArgument(ExpressionPtr arg) {
        arguments.push_back(std::move(arg));
    }
    
    void setMethodCallExpression(ExpressionPtr expr) {
        methodCallExpr = std::move(expr);
    }

    ASTNodeType getType() const override { return ASTNodeType::STMT_CALL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CALL " << subName << "(";
        for (size_t i = 0; i < arguments.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << arguments[i]->toString(0);
        }
        oss << ")\n";
        return oss.str();
    }
};

// =============================================================================
// Program Structure
// =============================================================================

// A single line of BASIC code (with optional line number)
class ProgramLine : public ASTNode {
public:
    int lineNumber;  // 0 if no line number
    std::vector<StatementPtr> statements;

    ProgramLine() : lineNumber(0) {}
    explicit ProgramLine(int line) : lineNumber(line) {}

    void addStatement(StatementPtr stmt) {
        statements.push_back(std::move(stmt));
    }

    ASTNodeType getType() const override { return ASTNodeType::PROGRAM_LINE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent);
        if (lineNumber > 0) {
            oss << "Line " << lineNumber << ":\n";
        } else {
            oss << "Line (unnumbered):\n";
        }
        for (const auto& stmt : statements) {
            oss << stmt->toString(indent + 1);
        }
        return oss.str();
    }
};

// =============================================================================
// CLASS & Object System AST Nodes
// =============================================================================

class MethodStatement : public Statement {
public:
    std::string methodName;
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterTypes;
    std::vector<std::string> parameterAsTypes;
    std::vector<bool> parameterIsByRef;
    TokenType returnTypeSuffix;
    std::string returnTypeAsName;
    bool hasReturnType;
    std::vector<StatementPtr> body;

    MethodStatement(const std::string& name)
        : methodName(name), returnTypeSuffix(TokenType::UNKNOWN), hasReturnType(false) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_METHOD; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "METHOD " << methodName << "(";
        for (size_t i = 0; i < parameters.size(); i++) {
            if (i > 0) oss << ", ";
            oss << parameters[i];
        }
        oss << ")";
        if (hasReturnType) oss << " AS " << returnTypeAsName;
        oss << "\n";
        for (const auto& stmt : body) {
            oss << stmt->toString(indent + 1);
        }
        return oss.str();
    }
};

class ConstructorStatement : public Statement {
public:
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterTypes;
    std::vector<std::string> parameterAsTypes;
    std::vector<bool> parameterIsByRef;
    std::vector<StatementPtr> body;
    // SUPER call info (extracted during parsing)
    bool hasSuperCall;
    std::vector<ExpressionPtr> superArgs;

    ConstructorStatement()
        : hasSuperCall(false) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_CONSTRUCTOR; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CONSTRUCTOR(";
        for (size_t i = 0; i < parameters.size(); i++) {
            if (i > 0) oss << ", ";
            oss << parameters[i];
        }
        oss << ")\n";
        if (hasSuperCall) {
            oss << makeIndent(indent + 1) << "SUPER(";
            for (size_t i = 0; i < superArgs.size(); i++) {
                if (i > 0) oss << ", ";
                oss << superArgs[i]->toString(0);
            }
            oss << ")\n";
        }
        for (const auto& stmt : body) {
            oss << stmt->toString(indent + 1);
        }
        return oss.str();
    }
};

class DestructorStatement : public Statement {
public:
    std::vector<StatementPtr> body;

    DestructorStatement() = default;

    ASTNodeType getType() const override { return ASTNodeType::STMT_DESTRUCTOR; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DESTRUCTOR()\n";
        for (const auto& stmt : body) {
            oss << stmt->toString(indent + 1);
        }
        return oss.str();
    }
};

class ClassStatement : public Statement {
public:
    std::string className;
    std::string parentClassName;                                // empty if no EXTENDS
    std::vector<TypeDeclarationStatement::TypeField> fields;
    std::unique_ptr<ConstructorStatement> constructor;          // nullable
    std::unique_ptr<DestructorStatement> destructor;             // nullable
    std::vector<std::unique_ptr<MethodStatement>> methods;

    ClassStatement(const std::string& name)
        : className(name) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_CLASS; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CLASS " << className;
        if (!parentClassName.empty()) oss << " EXTENDS " << parentClassName;
        oss << "\n";
        for (const auto& field : fields) {
            oss << makeIndent(indent + 1) << field.name << " AS " << field.typeName << "\n";
        }
        if (constructor) {
            oss << constructor->toString(indent + 1);
        }
        if (destructor) {
            oss << destructor->toString(indent + 1);
        }
        for (const auto& method : methods) {
            oss << method->toString(indent + 1);
        }
        return oss.str();
    }
};

class DeleteStatement : public Statement {
public:
    std::string variableName;

    DeleteStatement(const std::string& varName)
        : variableName(varName) {}

    ASTNodeType getType() const override { return ASTNodeType::STMT_DELETE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "DELETE " << variableName << "\n";
        return oss.str();
    }
};

class NewExpression : public Expression {
public:
    std::string className;
    std::vector<ExpressionPtr> arguments;

    NewExpression(const std::string& name)
        : className(name) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_NEW; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "NEW " << className << "(";
        for (size_t i = 0; i < arguments.size(); i++) {
            if (i > 0) oss << ", ";
            oss << arguments[i]->toString(0);
        }
        oss << ")";
        return oss.str();
    }
};

// CREATE TypeName(args...) - UDT value-type initialization
// Arguments are positionally mapped to TYPE fields in declaration order.
// Unlike NEW (which heap-allocates a CLASS instance), CREATE produces a
// stack-allocated value with all fields initialized.
class CreateExpression : public Expression {
public:
    std::string typeName;
    std::vector<ExpressionPtr> arguments;
    SourceLocation location;

    // Named-field support: when isNamed is true, fieldNames[i] holds the
    // field name corresponding to arguments[i].  The codegen maps each
    // argument to the named field's offset instead of using positional order.
    // Fields not mentioned in a named CREATE are zero-initialised.
    bool isNamed = false;
    std::vector<std::string> fieldNames;

    CreateExpression(const std::string& name)
        : typeName(name), isNamed(false) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_CREATE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "CREATE " << typeName << "(";
        for (size_t i = 0; i < arguments.size(); i++) {
            if (i > 0) oss << ", ";
            if (isNamed && i < fieldNames.size()) {
                oss << fieldNames[i] << " := ";
            }
            oss << arguments[i]->toString(0);
        }
        oss << ")";
        return oss.str();
    }
};

class MeExpression : public Expression {
public:
    MeExpression() = default;

    ASTNodeType getType() const override { return ASTNodeType::EXPR_ME; }

    std::string toString(int indent = 0) const override {
        return makeIndent(indent) + "ME";
    }
};

class NothingExpression : public Expression {
public:
    NothingExpression() = default;

    ASTNodeType getType() const override { return ASTNodeType::EXPR_NOTHING; }

    std::string toString(int indent = 0) const override {
        return makeIndent(indent) + "NOTHING";
    }
};

class SuperCallExpression : public Expression {
public:
    std::string methodName;                 // empty for SUPER() constructor call
    std::vector<ExpressionPtr> arguments;
    bool isConstructorCall;                 // true for SUPER(), false for SUPER.Method()

    SuperCallExpression(const std::string& method, bool isCtor)
        : methodName(method), isConstructorCall(isCtor) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_SUPER_CALL; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "SUPER";
        if (!isConstructorCall) oss << "." << methodName;
        oss << "(";
        for (size_t i = 0; i < arguments.size(); i++) {
            if (i > 0) oss << ", ";
            oss << arguments[i]->toString(0);
        }
        oss << ")";
        return oss.str();
    }
};

class IsTypeExpression : public Expression {
public:
    ExpressionPtr object;
    std::string className;              // class name for IS ClassName
    bool isNothingCheck;                // true for IS NOTHING

    IsTypeExpression(ExpressionPtr obj, const std::string& cls, bool nothingCheck)
        : object(std::move(obj)), className(cls), isNothingCheck(nothingCheck) {}

    ASTNodeType getType() const override { return ASTNodeType::EXPR_IS_TYPE; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << object->toString(0) << " IS ";
        if (isNothingCheck) oss << "NOTHING";
        else oss << className;
        return oss.str();
    }
};

// =============================================================================
// Program (Complete BASIC program)
// =============================================================================

// Complete BASIC program
class Program : public ASTNode {
public:
    std::vector<std::unique_ptr<ProgramLine>> lines;

    Program() = default;

    void addLine(std::unique_ptr<ProgramLine> line) {
        lines.push_back(std::move(line));
    }

    ASTNodeType getType() const override { return ASTNodeType::PROGRAM; }

    std::string toString(int indent = 0) const override {
        std::ostringstream oss;
        oss << makeIndent(indent) << "Program (" << lines.size() << " lines):\n";
        for (const auto& line : lines) {
            oss << line->toString(indent + 1);
        }
        return oss.str();
    }
};

} // namespace FasterBASIC

#endif // FASTERBASIC_AST_H
