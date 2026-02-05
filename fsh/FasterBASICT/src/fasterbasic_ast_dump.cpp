//
// fasterbasic_ast_dump.cpp
// FasterBASIC - AST Dump Utility Implementation
//
// Provides functions to dump the AST structure for debugging purposes.
//

#include "fasterbasic_ast_dump.h"
#include <iomanip>

namespace FasterBASIC {

std::string indent(int level) {
    return std::string(level * 2, ' ');
}

std::string getNodeTypeName(ASTNodeType type) {
    switch (type) {
        case ASTNodeType::PROGRAM: return "PROGRAM";
        case ASTNodeType::PROGRAM_LINE: return "PROGRAM_LINE";
        case ASTNodeType::STMT_PRINT: return "STMT_PRINT";
        case ASTNodeType::STMT_CONSOLE: return "STMT_CONSOLE";
        case ASTNodeType::STMT_INPUT: return "STMT_INPUT";
        case ASTNodeType::STMT_OPEN: return "STMT_OPEN";
        case ASTNodeType::STMT_CLOSE: return "STMT_CLOSE";
        case ASTNodeType::STMT_LET: return "STMT_LET";
        case ASTNodeType::STMT_MID_ASSIGN: return "STMT_MID_ASSIGN";
        case ASTNodeType::STMT_SLICE_ASSIGN: return "STMT_SLICE_ASSIGN";
        case ASTNodeType::STMT_GOTO: return "STMT_GOTO";
        case ASTNodeType::STMT_GOSUB: return "STMT_GOSUB";
        case ASTNodeType::STMT_ON_GOTO: return "STMT_ON_GOTO";
        case ASTNodeType::STMT_ON_GOSUB: return "STMT_ON_GOSUB";
        case ASTNodeType::STMT_ON_CALL: return "STMT_ON_CALL";
        case ASTNodeType::STMT_ON_EVENT: return "STMT_ON_EVENT";
        case ASTNodeType::STMT_RETURN: return "STMT_RETURN";
        case ASTNodeType::STMT_CONSTANT: return "STMT_CONSTANT";
        case ASTNodeType::STMT_LABEL: return "STMT_LABEL";
        case ASTNodeType::STMT_PLAY: return "STMT_PLAY";
        case ASTNodeType::STMT_PLAY_SOUND: return "STMT_PLAY_SOUND";
        case ASTNodeType::STMT_EXIT: return "STMT_EXIT";
        case ASTNodeType::STMT_IF: return "STMT_IF";
        case ASTNodeType::STMT_CASE: return "STMT_CASE";
        case ASTNodeType::STMT_WHEN: return "STMT_WHEN";
        case ASTNodeType::STMT_FOR: return "STMT_FOR";
        case ASTNodeType::STMT_FOR_IN: return "STMT_FOR_IN";
        case ASTNodeType::STMT_NEXT: return "STMT_NEXT";
        case ASTNodeType::STMT_WHILE: return "STMT_WHILE";
        case ASTNodeType::STMT_WEND: return "STMT_WEND";
        case ASTNodeType::STMT_REPEAT: return "STMT_REPEAT";
        case ASTNodeType::STMT_UNTIL: return "STMT_UNTIL";
        case ASTNodeType::STMT_DO: return "STMT_DO";
        case ASTNodeType::STMT_LOOP: return "STMT_LOOP";
        case ASTNodeType::STMT_END: return "STMT_END";
        case ASTNodeType::STMT_TRY_CATCH: return "STMT_TRY_CATCH";
        case ASTNodeType::STMT_THROW: return "STMT_THROW";
        case ASTNodeType::STMT_DIM: return "STMT_DIM";
        case ASTNodeType::STMT_REDIM: return "STMT_REDIM";
        case ASTNodeType::STMT_ERASE: return "STMT_ERASE";
        case ASTNodeType::STMT_SWAP: return "STMT_SWAP";
        case ASTNodeType::STMT_INC: return "STMT_INC";
        case ASTNodeType::STMT_DEC: return "STMT_DEC";
        case ASTNodeType::STMT_LOCAL: return "STMT_LOCAL";
        case ASTNodeType::STMT_SHARED: return "STMT_SHARED";
        case ASTNodeType::STMT_TYPE: return "STMT_TYPE";
        case ASTNodeType::STMT_DATA: return "STMT_DATA";
        case ASTNodeType::STMT_READ: return "STMT_READ";
        case ASTNodeType::STMT_RESTORE: return "STMT_RESTORE";
        case ASTNodeType::STMT_REM: return "STMT_REM";
        case ASTNodeType::STMT_OPTION: return "STMT_OPTION";
        case ASTNodeType::STMT_CLS: return "STMT_CLS";
        case ASTNodeType::STMT_COLOR: return "STMT_COLOR";
        case ASTNodeType::STMT_LOCATE: return "STMT_LOCATE";
        case ASTNodeType::STMT_WIDTH: return "STMT_WIDTH";
        case ASTNodeType::STMT_WAIT: return "STMT_WAIT";
        case ASTNodeType::STMT_WAIT_MS: return "STMT_WAIT_MS";
        case ASTNodeType::STMT_PSET: return "STMT_PSET";
        case ASTNodeType::STMT_LINE: return "STMT_LINE";
        case ASTNodeType::STMT_RECT: return "STMT_RECT";
        case ASTNodeType::STMT_CIRCLE: return "STMT_CIRCLE";
        case ASTNodeType::STMT_CIRCLEF: return "STMT_CIRCLEF";
        case ASTNodeType::STMT_GCLS: return "STMT_GCLS";
        case ASTNodeType::STMT_HLINE: return "STMT_HLINE";
        case ASTNodeType::STMT_VLINE: return "STMT_VLINE";
        case ASTNodeType::STMT_SUB: return "STMT_SUB";
        case ASTNodeType::STMT_FUNCTION: return "STMT_FUNCTION";
        case ASTNodeType::STMT_CALL: return "STMT_CALL";
        case ASTNodeType::STMT_DEF: return "STMT_DEF";
        default: return "UNKNOWN_" + std::to_string(static_cast<int>(type));
    }
}

void dumpStatement(const Statement& stmt, int indentLevel, std::ostream& os) {
    ASTNodeType type = stmt.getType();
    os << indent(indentLevel) << getNodeTypeName(type);
    
    // Add specific details for different statement types
    switch (type) {
        case ASTNodeType::STMT_IF: {
            const auto& ifStmt = static_cast<const IfStatement&>(stmt);
            os << " (isMultiLine=" << ifStmt.isMultiLine
               << ", hasGoto=" << ifStmt.hasGoto 
               << ", thenStmts=" << ifStmt.thenStatements.size()
               << ", elseIfClauses=" << ifStmt.elseIfClauses.size()
               << ", elseStmts=" << ifStmt.elseStatements.size() << ")\n";
            
            // Dump THEN statements
            if (!ifStmt.thenStatements.empty()) {
                os << indent(indentLevel + 1) << "THEN branch:\n";
                for (const auto& thenStmt : ifStmt.thenStatements) {
                    dumpStatement(*thenStmt, indentLevel + 2, os);
                }
            }
            
            // Dump ELSEIF clauses
            for (size_t i = 0; i < ifStmt.elseIfClauses.size(); ++i) {
                os << indent(indentLevel + 1) << "ELSEIF clause " << i << ":\n";
                for (const auto& elseIfStmt : ifStmt.elseIfClauses[i].statements) {
                    dumpStatement(*elseIfStmt, indentLevel + 2, os);
                }
            }
            
            // Dump ELSE statements
            if (!ifStmt.elseStatements.empty()) {
                os << indent(indentLevel + 1) << "ELSE branch:\n";
                for (const auto& elseStmt : ifStmt.elseStatements) {
                    dumpStatement(*elseStmt, indentLevel + 2, os);
                }
            }
            return;
        }
        
        case ASTNodeType::STMT_WHILE: {
            os << "\n";
            return;
        }
        
        case ASTNodeType::STMT_FOR: {
            const auto& forStmt = static_cast<const ForStatement&>(stmt);
            os << " (variable=" << forStmt.variable << ")\n";
            return;
        }
        
        case ASTNodeType::STMT_GOTO: {
            const auto& gotoStmt = static_cast<const GotoStatement&>(stmt);
            if (gotoStmt.isLabel) {
                os << " (target=:" << gotoStmt.label << ")\n";
            } else {
                os << " (target=" << gotoStmt.lineNumber << ")\n";
            }
            return;
        }
        
        case ASTNodeType::STMT_GOSUB: {
            const auto& gosubStmt = static_cast<const GosubStatement&>(stmt);
            os << " (target=" << gosubStmt.lineNumber << ")\n";
            return;
        }
        
        case ASTNodeType::STMT_PRINT: {
            const auto& printStmt = static_cast<const PrintStatement&>(stmt);
            os << " (items=" << printStmt.items.size() << ")\n";
            return;
        }
        
        case ASTNodeType::STMT_LET: {
            const auto& letStmt = static_cast<const LetStatement&>(stmt);
            os << " (variable=" << letStmt.variable << ")\n";
            return;
        }
        
        case ASTNodeType::STMT_DIM: {
            os << "\n";
            return;
        }
        
        case ASTNodeType::STMT_END: {
            os << " [EndStatement]\n";
            return;
        }
        
        case ASTNodeType::STMT_RETURN: {
            os << "\n";
            return;
        }
        
        case ASTNodeType::STMT_REM: {
            const auto& remStmt = static_cast<const RemStatement&>(stmt);
            os << " (comment=\"" << remStmt.comment << "\")\n";
            return;
        }
        
        default:
            os << "\n";
            return;
    }
}

void dumpProgramLine(const ProgramLine& line, int indentLevel, std::ostream& os) {
    os << indent(indentLevel) << "Line " << line.lineNumber 
       << " (" << line.statements.size() << " statements):\n";
    
    for (const auto& stmt : line.statements) {
        dumpStatement(*stmt, indentLevel + 1, os);
    }
}

void dumpAST(const Program& program, std::ostream& os) {
    os << "=== AST DUMP ===\n";
    os << "Program with " << program.lines.size() << " lines\n\n";
    
    for (const auto& line : program.lines) {
        dumpProgramLine(*line, 0, os);
    }
    
    os << "\n=== END AST DUMP ===\n";
}

} // namespace FasterBASIC