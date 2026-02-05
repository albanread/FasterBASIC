//
// fasterbasic_ast_dump.h
// FasterBASIC - AST Dump Utility
//
// Provides functions to dump the AST structure for debugging purposes.
//

#ifndef FASTERBASIC_AST_DUMP_H
#define FASTERBASIC_AST_DUMP_H

#include "fasterbasic_ast.h"
#include <iostream>
#include <string>

namespace FasterBASIC {

// Forward declarations
void dumpAST(const Program& program, std::ostream& os = std::cerr);
void dumpProgramLine(const ProgramLine& line, int indent, std::ostream& os);
void dumpStatement(const Statement& stmt, int indent, std::ostream& os);
std::string getNodeTypeName(ASTNodeType type);
std::string indent(int level);

} // namespace FasterBASIC

#endif // FASTERBASIC_AST_DUMP_H