#include "ast_emitter.h"
#include "../runtime_objects.h"
#include "../modular_commands.h"
#include <sstream>
#include <cmath>
#include <iostream>
#include <cstring>
#include <cstdlib>

namespace fbc {

using namespace FasterBASIC;

ASTEmitter::ASTEmitter(QBEBuilder& builder, TypeManager& typeManager,
                       SymbolMapper& symbolMapper, RuntimeLibrary& runtime,
                       SemanticAnalyzer& semantic)
    : builder_(builder)
    , typeManager_(typeManager)
    , symbolMapper_(symbolMapper)
    , runtime_(runtime)
    , semantic_(semantic)
{
}

bool ASTEmitter::isSAMMEnabled() const {
    return semantic_.getSymbolTable().sammEnabled;
}

// === Expression Emission ===

std::string ASTEmitter::emitExpression(const Expression* expr) {
    if (!expr) {
        builder_.emitComment("ERROR: null expression");
        return "0";
    }
    
    switch (expr->getType()) {
        case ASTNodeType::EXPR_NUMBER:
            return emitNumberLiteral(static_cast<const NumberExpression*>(expr), BaseType::UNKNOWN);
            
        case ASTNodeType::EXPR_STRING:
            return emitStringLiteral(static_cast<const StringExpression*>(expr));
        
        case ASTNodeType::EXPR_VARIABLE:
            return emitVariableExpression(static_cast<const VariableExpression*>(expr));
        
        case ASTNodeType::EXPR_BINARY:
            return emitBinaryExpression(static_cast<const BinaryExpression*>(expr));
        
        case ASTNodeType::EXPR_UNARY:
            return emitUnaryExpression(static_cast<const UnaryExpression*>(expr));
        
        case ASTNodeType::EXPR_ARRAY_ACCESS:
            return emitArrayAccessExpression(static_cast<const ArrayAccessExpression*>(expr));
        
        case ASTNodeType::EXPR_FUNCTION_CALL:
            return emitFunctionCall(static_cast<const FunctionCallExpression*>(expr));
            
        case ASTNodeType::EXPR_IIF:
            return emitIIFExpression(static_cast<const IIFExpression*>(expr));
            
        case ASTNodeType::EXPR_METHOD_CALL:
            return emitMethodCall(static_cast<const MethodCallExpression*>(expr));
            
        case ASTNodeType::EXPR_MEMBER_ACCESS:
            return emitMemberAccessExpression(static_cast<const MemberAccessExpression*>(expr));
            
        // CLASS & Object System expressions
        case ASTNodeType::EXPR_NEW: {
            const auto* newExpr = static_cast<const NewExpression*>(expr);
            const auto& symbolTable = semantic_.getSymbolTable();
            const ClassSymbol* cls = symbolTable.lookupClass(newExpr->className);
            if (!cls) {
                builder_.emitComment("ERROR: CLASS '" + newExpr->className + "' not defined");
                return "0";
            }
            
            builder_.emitComment("NEW " + newExpr->className + "()");
            
            // 1. Allocate object via class_object_new(size, vtable, class_id)
            auto sizeTemp = builder_.newTemp();
            builder_.emitRaw("    " + sizeTemp + " =l copy " + std::to_string(cls->objectSize) + "\n");
            
            auto vtableTemp = builder_.newTemp();
            builder_.emitRaw("    " + vtableTemp + " =l copy $vtable_" + cls->name + "\n");
            
            auto classIdTemp = builder_.newTemp();
            builder_.emitRaw("    " + classIdTemp + " =l copy " + std::to_string(cls->classId) + "\n");
            
            auto objTemp = builder_.newTemp();
            builder_.emitRaw("    " + objTemp + " =l call $class_object_new(l " + sizeTemp + ", l " + vtableTemp + ", l " + classIdTemp + ")\n");
            
            // 2. Call constructor (if any)
            if (cls->hasConstructor) {
                std::string callArgs = "l " + objTemp;
                for (size_t i = 0; i < newExpr->arguments.size(); i++) {
                    std::string argTemp = emitExpression(newExpr->arguments[i].get());
                    // Determine arg type from constructor param types
                    std::string argType = "l";
                    if (i < cls->constructorParamTypes.size()) {
                        if (cls->constructorParamTypes[i].baseType == FasterBASIC::BaseType::INTEGER ||
                            cls->constructorParamTypes[i].baseType == FasterBASIC::BaseType::UINTEGER) {
                            argType = "w";
                        } else if (cls->constructorParamTypes[i].baseType == FasterBASIC::BaseType::DOUBLE) {
                            argType = "d";
                        } else if (cls->constructorParamTypes[i].baseType == FasterBASIC::BaseType::SINGLE) {
                            argType = "s";
                        }
                    }
                    callArgs += ", " + argType + " " + argTemp;
                }
                builder_.emitRaw("    call $" + cls->constructorMangledName + "(" + callArgs + ")\n");
            }
            
            return objTemp;
        }
        
        case ASTNodeType::EXPR_ME: {
            // ME refers to the %me parameter (first parameter of METHOD/CONSTRUCTOR)
            builder_.emitComment("ME (current object reference)");
            return "%me";
        }
        
        case ASTNodeType::EXPR_NOTHING: {
            // NOTHING is the null object reference (0)
            builder_.emitComment("NOTHING (null object reference)");
            return "0";
        }
        
        case ASTNodeType::EXPR_IS_TYPE: {
            const auto* isExpr = static_cast<const IsTypeExpression*>(expr);
            std::string objTemp = emitExpression(isExpr->object.get());
            
            if (isExpr->isNothingCheck) {
                // obj IS NOTHING  →  ceql %obj, 0
                builder_.emitComment("IS NOTHING check");
                auto resultTemp = builder_.newTemp();
                builder_.emitRaw("    " + resultTemp + " =w ceql " + objTemp + ", 0\n");
                return resultTemp;
            } else {
                // obj IS ClassName  →  call $class_is_instance(obj, class_id)
                const auto& symbolTable = semantic_.getSymbolTable();
                const ClassSymbol* targetCls = symbolTable.lookupClass(isExpr->className);
                if (!targetCls) {
                    builder_.emitComment("ERROR: CLASS '" + isExpr->className + "' not defined for IS check");
                    return "0";
                }
                builder_.emitComment("IS " + isExpr->className + " type check");
                auto resultTemp = builder_.newTemp();
                builder_.emitRaw("    " + resultTemp + " =w call $class_is_instance(l " + objTemp + ", l " + std::to_string(targetCls->classId) + ")\n");
                return resultTemp;
            }
        }
        
        case ASTNodeType::EXPR_SUPER_CALL: {
            const auto* superExpr = static_cast<const FasterBASIC::SuperCallExpression*>(expr);
            if (superExpr->isConstructorCall) {
                // SUPER() constructor call — should be handled in emitClassConstructor,
                // but if it appears here as an expression, emit it as a void call.
                if (currentClassContext_ && currentClassContext_->parentClass &&
                    currentClassContext_->parentClass->hasConstructor) {
                    builder_.emitComment("SUPER() constructor call");
                    std::string callArgs = "l %me";
                    for (size_t i = 0; i < superExpr->arguments.size(); i++) {
                        std::string argTemp = emitExpression(superExpr->arguments[i].get());
                        std::string argType = "l";
                        if (i < currentClassContext_->parentClass->constructorParamTypes.size()) {
                            auto pbt = currentClassContext_->parentClass->constructorParamTypes[i].baseType;
                            if (pbt == FasterBASIC::BaseType::INTEGER || pbt == FasterBASIC::BaseType::UINTEGER)
                                argType = "w";
                            else if (pbt == FasterBASIC::BaseType::DOUBLE)
                                argType = "d";
                            else if (pbt == FasterBASIC::BaseType::SINGLE)
                                argType = "s";
                        }
                        callArgs += ", " + argType + " " + argTemp;
                    }
                    builder_.emitRaw("    call $" + currentClassContext_->parentClass->constructorMangledName + "(" + callArgs + ")\n");
                } else {
                    builder_.emitComment("SUPER() — no parent constructor to call");
                }
                return "0";
            } else {
                // SUPER.Method() — direct (non-virtual) call to parent class method
                if (!currentClassContext_ || !currentClassContext_->parentClass) {
                    builder_.emitComment("ERROR: SUPER.Method() without parent class");
                    return "0";
                }
                const auto* parentClass = currentClassContext_->parentClass;
                const auto* methodInfo = parentClass->findMethod(superExpr->methodName);
                if (!methodInfo) {
                    builder_.emitComment("ERROR: parent class '" + parentClass->name + "' has no method '" + superExpr->methodName + "'");
                    return "0";
                }
                builder_.emitComment("SUPER." + superExpr->methodName + "() — direct call to parent");
                
                // Build argument list: ME as first arg, then user args
                std::string callArgs = "l %me";
                for (size_t i = 0; i < superExpr->arguments.size(); i++) {
                    FasterBASIC::BaseType paramBaseType = FasterBASIC::BaseType::LONG;
                    std::string argType = "l";
                    if (i < methodInfo->parameterTypes.size()) {
                        paramBaseType = methodInfo->parameterTypes[i].baseType;
                        if (paramBaseType == FasterBASIC::BaseType::INTEGER || paramBaseType == FasterBASIC::BaseType::UINTEGER)
                            argType = "w";
                        else if (paramBaseType == FasterBASIC::BaseType::DOUBLE)
                            argType = "d";
                        else if (paramBaseType == FasterBASIC::BaseType::SINGLE)
                            argType = "s";
                    }
                    std::string argTemp = emitExpressionAs(superExpr->arguments[i].get(), paramBaseType);
                    callArgs += ", " + argType + " " + argTemp;
                }
                
                // Direct call (not virtual dispatch) to the parent's method
                if (methodInfo->returnType.baseType == FasterBASIC::BaseType::VOID) {
                    builder_.emitRaw("    call $" + methodInfo->mangledName + "(" + callArgs + ")\n");
                    return "0";
                } else {
                    std::string retType = "l";
                    if (methodInfo->returnType.baseType == FasterBASIC::BaseType::INTEGER ||
                        methodInfo->returnType.baseType == FasterBASIC::BaseType::UINTEGER)
                        retType = "w";
                    else if (methodInfo->returnType.baseType == FasterBASIC::BaseType::DOUBLE)
                        retType = "d";
                    else if (methodInfo->returnType.baseType == FasterBASIC::BaseType::SINGLE)
                        retType = "s";
                    auto result = builder_.newTemp();
                    builder_.emitRaw("    " + result + " =" + retType + " call $" + methodInfo->mangledName + "(" + callArgs + ")\n");
                    return result;
                }
            }
        }
        
        default:
            builder_.emitComment("ERROR: unsupported expression type");
            return "0";
    }
}

std::string ASTEmitter::emitExpressionAs(const Expression* expr, BaseType expectedType) {
    if (!expr) {
        return "0";
    }
    
    // Special case: if it's a simple number literal, emit it with the expected type
    if (expr->getType() == ASTNodeType::EXPR_NUMBER) {
        return emitNumberLiteral(static_cast<const NumberExpression*>(expr), expectedType);
    }
    
    // For complex expressions, emit normally and convert if needed
    std::string value = emitExpression(expr);
    BaseType exprType = getExpressionType(expr);
    
    // Convert if necessary
    if (typeManager_.needsConversion(exprType, expectedType)) {
        return emitTypeConversion(value, exprType, expectedType);
    }
    
    return value;
}

// === Expression Emitters (by type) ===

std::string ASTEmitter::emitNumberLiteral(const NumberExpression* expr, BaseType expectedType) {
    double value = expr->value;
    
    // Check if it's an integer value (no fractional part)
    bool isInteger = (value == std::floor(value));
    
    if (isInteger) {
        // Integer literal - check range and expected type
        if (expectedType == BaseType::SINGLE || expectedType == BaseType::DOUBLE) {
            // Need float/double representation
            std::ostringstream oss;
            oss.precision(17);
            oss << (expectedType == BaseType::SINGLE ? "s_" : "d_") << value;
            return oss.str();
        } else if (expectedType == BaseType::LONG || expectedType == BaseType::ULONG) {
            // LONG literal - can represent values up to INT64
            return std::to_string(static_cast<int64_t>(value));
        } else if (value >= INT32_MIN && value <= INT32_MAX) {
            // Regular INTEGER literal
            return std::to_string(static_cast<int>(value));
        } else {
            // Value too large for INT32 but expected type is not LONG
            // Emit as LONG anyway (it will be truncated if stored in INT32)
            return std::to_string(static_cast<int64_t>(value));
        }
    } else {
        // Float/double literal - use expectedType if provided, otherwise default to double
        std::ostringstream oss;
        oss.precision(17);  // Full double precision
        
        if (expectedType == BaseType::SINGLE) {
            oss << "s_" << value;
        } else {
            // Default to double for floating literals (matches getExpressionType)
            oss << "d_" << value;
        }
        return oss.str();
    }
}

std::string ASTEmitter::emitStringLiteral(const StringExpression* expr) {
    // Get the label from the string pool (should already be registered)
    std::string label = builder_.getStringLabel(expr->value);
    
    if (label.empty()) {
        // Fallback: register now if somehow missed during collection
        label = builder_.registerString(expr->value);
        builder_.emitComment("WARNING: String not pre-registered: " + expr->value);
    }
    
    // Convert C string to FasterBASIC string descriptor
    return runtime_.emitStringLiteral(label);
}

std::string ASTEmitter::emitVariableExpression(const VariableExpression* expr) {
    return loadVariable(expr->name);
}

std::string ASTEmitter::emitBinaryExpression(const BinaryExpression* expr) {
    TokenType op = expr->op;
    
    // Get expression types
    BaseType leftType = getExpressionType(expr->left.get());
    BaseType rightType = getExpressionType(expr->right.get());
    
    // Check if this is a string operation
    if (typeManager_.isString(leftType) || typeManager_.isString(rightType)) {
        std::string left = emitExpressionAs(expr->left.get(), BaseType::STRING);
        std::string right = emitExpressionAs(expr->right.get(), BaseType::STRING);
        return emitStringOp(left, right, op);
    }
    
    // Numeric operation - promote to common type
    BaseType commonType = typeManager_.getPromotedType(leftType, rightType);
    
    std::string left = emitExpressionAs(expr->left.get(), commonType);
    std::string right = emitExpressionAs(expr->right.get(), commonType);
    
    // Check operation type
    if (op >= TokenType::EQUAL && op <= TokenType::GREATER_EQUAL) {
        // Comparison operation
        return emitComparisonOp(left, right, op, commonType);
    } else if (op == TokenType::AND || op == TokenType::OR || op == TokenType::XOR) {
        // Bitwise/logical operation
        return emitLogicalOp(left, right, op);
    } else {
        // Arithmetic operation
        return emitArithmeticOp(left, right, op, commonType);
    }
}

std::string ASTEmitter::emitUnaryExpression(const UnaryExpression* expr) {
    std::string operand = emitExpression(expr->expr.get());
    BaseType operandType = getExpressionType(expr->expr.get());
    std::string qbeType = typeManager_.getQBEType(operandType);
    
    if (expr->op == TokenType::MINUS) {
        // Negation
        std::string result = builder_.newTemp();
        builder_.emitNeg(result, qbeType, operand);
        return result;
    } else if (expr->op == TokenType::NOT) {
        // Bitwise NOT - flip all bits
        std::string result = builder_.newTemp();
        
        // Coerce to 32-bit integer if needed
        std::string notOperand = operand;
        if (typeManager_.isFloatingPoint(operandType)) {
            notOperand = builder_.newTemp();
            builder_.emitRaw("    " + notOperand + " =w " + qbeType + "tosi " + operand);
        }
        
        // Perform bitwise NOT using XOR with -1
        builder_.emitBinary(result, "w", "xor", notOperand, "-1");
        return result;
    } else if (expr->op == TokenType::PLUS) {
        // Unary plus - no-op
        return operand;
    } else {
        builder_.emitComment("ERROR: unsupported unary operator");
        return operand;
    }
}

std::string ASTEmitter::emitArrayAccessExpression(const ArrayAccessExpression* expr) {
    return loadArrayElement(expr->name, expr->indices);
}

std::string ASTEmitter::emitMemberAccessExpression(const MemberAccessExpression* expr) {
    // === CLASS Instance Member Access (fast path) ===
    // If the base expression is a variable with CLASS_INSTANCE type, or ME,
    // use pointer + offset access instead of stack-based UDT access.
    {
        const FasterBASIC::ClassSymbol* classSym = nullptr;
        std::string objPtr;

        if (expr->object->getType() == ASTNodeType::EXPR_ME) {
            // ME.Field — %me is already a pointer to the object
            objPtr = "%me";
            // Use the current class context set by emitClassMethod/emitClassConstructor
            if (currentClassContext_) {
                classSym = currentClassContext_;
            } else {
                // Fallback: look up from the member name across all classes
                const auto& symbolTable = semantic_.getSymbolTable();
                for (const auto& pair : symbolTable.classes) {
                    if (pair.second.findField(expr->memberName)) {
                        classSym = &pair.second;
                        break;
                    }
                }
            }
        } else if (expr->object->getType() == ASTNodeType::EXPR_VARIABLE) {
            const auto* varExpr = static_cast<const VariableExpression*>(expr->object.get());
            std::string currentFunc = symbolMapper_.getCurrentFunction();
            const auto* vs = semantic_.lookupVariableScoped(varExpr->name, currentFunc);
            if (vs && vs->typeDesc.isClassType) {
                const auto& symbolTable = semantic_.getSymbolTable();
                classSym = symbolTable.lookupClass(vs->typeDesc.className);
                // Load the object pointer from the variable
                objPtr = loadVariable(varExpr->name);
            }
            // --- METHOD-local CLASS instance fallback ---
            // DIM'd CLASS instances inside METHOD bodies are registered in
            // methodParamAddresses_ / methodParamTypes_ but are NOT in the
            // semantic symbol table.  Check our local maps.
            if (!classSym && currentClassContext_) {
                auto mpTypeIt = methodParamTypes_.find(varExpr->name);
                if (mpTypeIt != methodParamTypes_.end() &&
                    mpTypeIt->second == FasterBASIC::BaseType::CLASS_INSTANCE) {
                    const auto& symbolTable = semantic_.getSymbolTable();
                    auto cnIt = methodParamClassNames_.find(varExpr->name);
                    if (cnIt != methodParamClassNames_.end()) {
                        classSym = symbolTable.lookupClass(cnIt->second);
                    }
                    // Fallback: search all classes for one with this field
                    if (!classSym) {
                        for (const auto& pair : symbolTable.classes) {
                            if (pair.second.findField(expr->memberName)) {
                                classSym = &pair.second;
                                break;
                            }
                        }
                    }
                    if (classSym) {
                        objPtr = loadVariable(varExpr->name);
                    }
                }
            }
        }

        if (classSym) {
            const auto* fieldInfo = classSym->findField(expr->memberName);
            if (fieldInfo) {
                builder_.emitComment("CLASS field access: " + classSym->name + "." + expr->memberName + " (offset " + std::to_string(fieldInfo->offset) + ")");

                // Null-check before field access (skip for ME which is always valid)
                if (objPtr != "%me") {
                    int labelId = builder_.getNextLabelId();
                    std::string nullLabel = "null_field_err_" + std::to_string(labelId);
                    std::string accessLabel = "field_ok_" + std::to_string(labelId);

                    auto isNull = builder_.newTemp();
                    builder_.emitRaw("    " + isNull + " =w ceql " + objPtr + ", 0\n");
                    builder_.emitRaw("    jnz " + isNull + ", @" + nullLabel + ", @" + accessLabel + "\n");

                    builder_.emitLabel(nullLabel);
                    std::string fieldNameLabel = builder_.registerString(expr->memberName);
                    std::string locationStr = "line " + std::to_string(expr->location.line);
                    std::string locationLabel = builder_.registerString(locationStr);
                    builder_.emitRaw("    call $class_null_field_error(l $" + locationLabel + ", l $" + fieldNameLabel + ")\n");
                    builder_.emitRaw("    hlt\n");

                    builder_.emitLabel(accessLabel);
                }

                // Compute field address: obj + offset
                auto fieldAddr = builder_.newTemp();
                builder_.emitRaw("    " + fieldAddr + " =l add " + objPtr + ", " + std::to_string(fieldInfo->offset) + "\n");

                // Load field value based on type
                auto result = builder_.newTemp();
                if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::INTEGER ||
                    fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::UINTEGER) {
                    result = builder_.newTemp();
                    builder_.emitRaw("    " + result + " =w loadw " + fieldAddr + "\n");
                } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::SINGLE) {
                    result = builder_.newTemp();
                    builder_.emitRaw("    " + result + " =s loads " + fieldAddr + "\n");
                } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::DOUBLE) {
                    result = builder_.newTemp();
                    builder_.emitRaw("    " + result + " =d loadd " + fieldAddr + "\n");
                } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::BYTE ||
                           fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::UBYTE) {
                    result = builder_.newTemp();
                    builder_.emitRaw("    " + result + " =w loadsb " + fieldAddr + "\n");
                } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::SHORT ||
                           fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::USHORT) {
                    result = builder_.newTemp();
                    builder_.emitRaw("    " + result + " =w loadsh " + fieldAddr + "\n");
                } else {
                    // Default: pointer-sized load (STRING, CLASS_INSTANCE, LONG, etc.)
                    builder_.emitRaw("    " + result + " =l loadl " + fieldAddr + "\n");
                }

                return result;
            } else {
                builder_.emitComment("ERROR: CLASS '" + classSym->name + "' has no field '" + expr->memberName + "'");
                return "0";
            }
        }
    }

    // === Standard UDT member access below ===
    // Handle UDT member access (e.g., person.Name, point.X, Points(0).X, O.Item.Value)
    
    std::string basePtr;
    std::string varName;
    const VariableSymbol* varSymbol = nullptr;
    
    // Determine the base object type
    if (expr->object->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
        // Nested member access: O.Item.Value
        // Recursively emit the base member access (O.Item), which returns the address
        builder_.emitComment("Nested member access");
        basePtr = emitMemberAccessExpression(static_cast<const MemberAccessExpression*>(expr->object.get()));
        
        // Now we need to find the UDT type of the intermediate result
        // For O.Item.Value, after emitting O.Item, we need to know that Item is of type Inner
        // We need to traverse the type chain to find the final field type
        
        // Get the outer member expression to determine the UDT type
        const auto* outerMemberExpr = static_cast<const MemberAccessExpression*>(expr->object.get());
        
        // We need to determine what type outerMemberExpr returns
        // For now, we'll look it up by examining the base variable
        std::string baseVarName;
        const Expression* baseExpr = outerMemberExpr->object.get();
        while (baseExpr->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
            baseExpr = static_cast<const MemberAccessExpression*>(baseExpr)->object.get();
        }
        
        if (baseExpr->getType() == ASTNodeType::EXPR_VARIABLE) {
            baseVarName = static_cast<const VariableExpression*>(baseExpr)->name;
        } else {
            builder_.emitComment("ERROR: Complex nested member access not yet supported");
            return "0";
        }
        
        // Look up the base variable
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        const auto* baseVarSymbol = semantic_.lookupVariableScoped(baseVarName, currentFunc);
        if (!baseVarSymbol || baseVarSymbol->typeDesc.baseType != BaseType::USER_DEFINED) {
            builder_.emitComment("ERROR: Base variable not found or not UDT: " + baseVarName);
            return "0";
        }
        
        // Now traverse the member chain to find the type of the intermediate field
        std::string currentUDTName = baseVarSymbol->typeName;
        const MemberAccessExpression* currentExpr = outerMemberExpr;
        
        // Walk through the member access chain to find the UDT type at this level
        while (currentExpr != nullptr) {
            // Look up current UDT
            const auto& symbolTable = semantic_.getSymbolTable();
            auto udtIt = symbolTable.types.find(currentUDTName);
            if (udtIt == symbolTable.types.end()) {
                builder_.emitComment("ERROR: UDT not found in chain: " + currentUDTName);
                return "0";
            }
            
            const auto& udtDef = udtIt->second;
            
            // Find the field in this UDT
            const FasterBASIC::TypeSymbol::Field* field = nullptr;
            for (const auto& f : udtDef.fields) {
                if (f.name == currentExpr->memberName) {
                    field = &f;
                    break;
                }
            }
            
            if (!field) {
                builder_.emitComment("ERROR: Field not found in UDT chain: " + currentExpr->memberName);
                return "0";
            }
            
            // Update currentUDTName to this field's type
            if (field->typeDesc.baseType == BaseType::USER_DEFINED) {
                currentUDTName = field->typeDesc.udtName;
            } else {
                // Reached a primitive type - should not happen if we're still traversing
                builder_.emitComment("ERROR: Expected UDT in chain but got primitive");
                return "0";
            }
            
            // Check if we've reached the outer expression
            if (currentExpr == outerMemberExpr) {
                break;
            }
            
            // Move to next level (not needed for simple two-level, but for completeness)
            if (currentExpr->object->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
                currentExpr = static_cast<const MemberAccessExpression*>(currentExpr->object.get());
            } else {
                break;
            }
        }
        
        // Now currentUDTName contains the type of the intermediate result
        // Find the final field in that UDT
        const auto& symbolTable = semantic_.getSymbolTable();
        auto finalUdtIt = symbolTable.types.find(currentUDTName);
        if (finalUdtIt == symbolTable.types.end()) {
            builder_.emitComment("ERROR: Final UDT not found: " + currentUDTName);
            return "0";
        }
        
        const auto& finalUdtDef = finalUdtIt->second;
        std::string memberName = expr->memberName;
        
        // Find the field
        int fieldIndex = -1;
        BaseType fieldType = BaseType::UNKNOWN;
        
        for (size_t i = 0; i < finalUdtDef.fields.size(); ++i) {
            if (finalUdtDef.fields[i].name == memberName) {
                fieldIndex = static_cast<int>(i);
                fieldType = finalUdtDef.fields[i].typeDesc.baseType;
                break;
            }
        }
        
        if (fieldIndex < 0) {
            builder_.emitComment("ERROR: Field not found: " + memberName + " in UDT " + currentUDTName);
            return "0";
        }
        
        // Calculate field offset in the final UDT
        int64_t offset = 0;
        for (int i = 0; i < fieldIndex; ++i) {
            if (finalUdtDef.fields[i].typeDesc.baseType == BaseType::USER_DEFINED) {
                // Nested UDT field - use recursive size calculation
                auto nestedUdtIt = symbolTable.types.find(finalUdtDef.fields[i].typeDesc.udtName);
                if (nestedUdtIt != symbolTable.types.end()) {
                    offset += typeManager_.getUDTSizeRecursive(nestedUdtIt->second, symbolTable.types);
                }
            } else {
                offset += typeManager_.getTypeSize(finalUdtDef.fields[i].typeDesc.baseType);
            }
        }
        
        // Add field offset to base pointer
        std::string fieldPtr = builder_.newTemp();
        if (offset > 0) {
            builder_.emitBinary(fieldPtr, "l", "add", basePtr, std::to_string(offset));
        } else {
            fieldPtr = basePtr;
        }
        
        // For UDT fields, return the address (for chaining); for primitives, load the value
        if (fieldType == BaseType::USER_DEFINED) {
            // Nested UDT - return address for further member access
            return fieldPtr;
        } else {
            // Primitive type - load the value
            std::string result = builder_.newTemp();
            std::string qbeType = typeManager_.getQBEType(fieldType);
            
            if (fieldType == BaseType::STRING) {
                builder_.emitLoad(result, "l", fieldPtr);
            } else {
                builder_.emitLoad(result, qbeType, fieldPtr);
            }
            
            return result;
        }
        
    } else if (expr->object->getType() == ASTNodeType::EXPR_VARIABLE) {
        // Simple variable: P.X
        const auto* varExpr = static_cast<const VariableExpression*>(expr->object.get());
        varName = varExpr->name;
        
        // Look up the variable to get its type
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        varSymbol = semantic_.lookupVariableScoped(varName, currentFunc);
        if (!varSymbol) {
            builder_.emitComment("ERROR: Variable not found: " + varName);
            return "0";
        }
        
        // Get the base address of the UDT variable
        std::string mangledName = symbolMapper_.mangleVariableName(varName, varSymbol->scope.isGlobal());
        basePtr = builder_.newTemp();
        
        // Check if this is a UDT parameter (passed by pointer/reference)
        // In that case, the stack slot contains a POINTER to the struct, not the struct itself.
        // We need an extra level of indirection: load the pointer from the stack slot first.
        bool isUDTParameter = (symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(varName) &&
                               varSymbol->typeDesc.baseType == BaseType::USER_DEFINED);
        
        if (isUDTParameter) {
            // UDT parameter: stack slot holds a pointer TO the actual struct
            builder_.emitComment("Load UDT parameter pointer (pass-by-ref): " + varName);
            builder_.emitLoad(basePtr, "l", mangledName);
        } else if (varSymbol->scope.isGlobal()) {
            // Global UDT - address IS the data (mangledName already includes $ prefix)
            builder_.emitComment("Load address of global UDT: " + varName);
            builder_.emitRaw("    " + basePtr + " =l copy " + mangledName);
        } else {
            // Local UDT - address IS the data on stack (mangledName already includes % prefix)
            builder_.emitComment("Load address of local UDT: " + varName);
            builder_.emitRaw("    " + basePtr + " =l copy " + mangledName);
        }
        
    } else if (expr->object->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        // Array element: Points(0).X
        const auto* arrExpr = static_cast<const ArrayAccessExpression*>(expr->object.get());
        varName = arrExpr->name;
        
        builder_.emitComment("Array element UDT access: " + varName + "(...).member");
        
        // Look up array symbol
        const auto& symbolTable = semantic_.getSymbolTable();
        auto arrIt = symbolTable.arrays.find(varName);
        if (arrIt == symbolTable.arrays.end()) {
            builder_.emitComment("ERROR: Array not found: " + varName);
            return "0";
        }
        
        const auto& arraySymbol = arrIt->second;
        
        // Array element must be UDT type
        if (arraySymbol.elementTypeDesc.baseType != BaseType::USER_DEFINED) {
            builder_.emitComment("ERROR: Array element is not UDT: " + varName);
            return "0";
        }
        
        // Get array element address using runtime array access
        // This returns the address of the UDT element
        basePtr = emitArrayElementAddress(varName, arrExpr->indices);
        
        // Note: varSymbol is not used after this point for array case
        
    } else {
        builder_.emitComment("ERROR: Complex member access not yet supported");
        return "0";
    }
    
    // Get UDT type name
    std::string udtTypeName;
    if (expr->object->getType() == ASTNodeType::EXPR_VARIABLE) {
        // For simple variables, use the variable's typeName
        if (varSymbol->typeDesc.baseType != BaseType::USER_DEFINED) {
            builder_.emitComment("ERROR: Member access on non-UDT variable: " + varName);
            return "0";
        }
        // Try typeName first, fall back to typeDesc.udtName (needed for UDT parameters)
        udtTypeName = varSymbol->typeName;
        if (udtTypeName.empty()) {
            udtTypeName = varSymbol->typeDesc.udtName;
        }
    } else if (expr->object->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        // For array elements, re-lookup the array to get UDT name
        const auto& symbolTable2 = semantic_.getSymbolTable();
        auto arrIt2 = symbolTable2.arrays.find(varName);
        if (arrIt2 != symbolTable2.arrays.end()) {
            udtTypeName = arrIt2->second.elementTypeDesc.udtName;
        } else {
            builder_.emitComment("ERROR: Array not found during UDT lookup: " + varName);
            return "0";
        }
    }
    
    // Look up the UDT definition
    const auto& symbolTable = semantic_.getSymbolTable();
    const auto& udtMap = symbolTable.types;
    auto udtIt = udtMap.find(udtTypeName);
    if (udtIt == udtMap.end()) {
        builder_.emitComment("ERROR: UDT not found: " + udtTypeName);
        return "0";
    }
    
    const auto& udtDef = udtIt->second;
    
    // Find the field
    std::string memberName = expr->memberName;
    int fieldIndex = -1;
    BaseType fieldType = BaseType::UNKNOWN;
    
    for (size_t i = 0; i < udtDef.fields.size(); ++i) {
        if (udtDef.fields[i].name == memberName) {
            fieldIndex = static_cast<int>(i);
            fieldType = udtDef.fields[i].typeDesc.baseType;
            break;
        }
    }
    
    if (fieldIndex < 0) {
        builder_.emitComment("ERROR: Field not found: " + memberName + " in UDT " + udtTypeName);
        return "0";
    }
    
    // Calculate field offset (accounting for nested UDT fields)
    int64_t offset = 0;
    const auto& symbolTable2 = semantic_.getSymbolTable();
    for (int i = 0; i < fieldIndex; ++i) {
        if (udtDef.fields[i].typeDesc.baseType == BaseType::USER_DEFINED) {
            // Nested UDT field - use recursive size calculation
            auto nestedUdtIt = symbolTable2.types.find(udtDef.fields[i].typeDesc.udtName);
            if (nestedUdtIt != symbolTable2.types.end()) {
                offset += typeManager_.getUDTSizeRecursive(nestedUdtIt->second, symbolTable2.types);
            }
        } else {
            offset += typeManager_.getTypeSize(udtDef.fields[i].typeDesc.baseType);
        }
    }
    
    // basePtr is already set from above (either simple variable or array element)
    
    // Add field offset
    std::string fieldPtr = builder_.newTemp();
    if (offset > 0) {
        builder_.emitBinary(fieldPtr, "l", "add", basePtr, std::to_string(offset));
    } else {
        builder_.emitRaw("    " + fieldPtr + " =l copy " + basePtr);
    }
    
    // For UDT fields, return the address (for chaining); for primitives, load the value
    if (fieldType == BaseType::USER_DEFINED) {
        // Nested UDT - return address for further member access
        return fieldPtr;
    } else {
        // Primitive type - load the value
        std::string result = builder_.newTemp();
        std::string qbeType = typeManager_.getQBEType(fieldType);
        
        if (fieldType == BaseType::STRING) {
            // String fields are stored as pointers to StringDescriptor
            builder_.emitLoad(result, "l", fieldPtr);
        } else {
            builder_.emitLoad(result, qbeType, fieldPtr);
        }
        
        return result;
    }
}

std::string ASTEmitter::emitIIFExpression(const IIFExpression* expr) {
    if (!expr || !expr->condition || !expr->trueValue || !expr->falseValue) {
        builder_.emitComment("ERROR: invalid IIF expression");
        return builder_.newTemp();
    }
    
    builder_.emitComment("IIF expression");
    
    // Determine result type from the branches
    BaseType trueType = getExpressionType(expr->trueValue.get());
    BaseType falseType = getExpressionType(expr->falseValue.get());
    
    // Use the promoted type
    BaseType resultType = typeManager_.getPromotedType(trueType, falseType);
    std::string qbeType = typeManager_.getQBEType(resultType);
    
    // Allocate result temporary
    std::string resultTemp = builder_.newTemp();
    
    // Create labels
    std::string trueLabel = symbolMapper_.getUniqueLabel("iif_true");
    std::string falseLabel = symbolMapper_.getUniqueLabel("iif_false");
    std::string endLabel = symbolMapper_.getUniqueLabel("iif_end");
    
    // Evaluate condition
    std::string condTemp = emitExpression(expr->condition.get());
    BaseType condType = getExpressionType(expr->condition.get());
    
    // Convert condition to word if needed
    std::string condWord = condTemp;
    std::string condQbeType = typeManager_.getQBEType(condType);
    if (condQbeType != "w") {
        condWord = builder_.newTemp();
        if (condQbeType == "d") {
            builder_.emitConvert(condWord, "w", "dtosi", condTemp);
        } else if (condQbeType == "s") {
            builder_.emitConvert(condWord, "w", "stosi", condTemp);
        } else if (condQbeType == "l") {
            builder_.emitTrunc(condWord, "w", condTemp);
        }
    }
    
    // Branch based on condition
    builder_.emitBranch(condWord, trueLabel, falseLabel);
    
    // True branch
    builder_.emitLabel(trueLabel);
    std::string trueTemp = emitExpression(expr->trueValue.get());
    
    // Convert true value to result type if needed
    if (trueType != resultType) {
        trueTemp = emitTypeConversion(trueTemp, trueType, resultType);
    }
    
    builder_.emitInstruction(resultTemp + " =" + qbeType + " copy " + trueTemp);
    builder_.emitJump(endLabel);
    
    // False branch
    builder_.emitLabel(falseLabel);
    std::string falseTemp = emitExpression(expr->falseValue.get());
    
    // Convert false value to result type if needed
    if (falseType != resultType) {
        falseTemp = emitTypeConversion(falseTemp, falseType, resultType);
    }
    
    builder_.emitInstruction(resultTemp + " =" + qbeType + " copy " + falseTemp);
    
    // End label
    builder_.emitLabel(endLabel);
    
    return resultTemp;
}

std::string ASTEmitter::emitFunctionCall(const FunctionCallExpression* expr) {
    std::string funcName = expr->name;
    
    // Convert to uppercase for case-insensitive matching
    std::string upperName = funcName;
    std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
    
    // Check for plugin functions first
    auto& cmdRegistry = FasterBASIC::ModularCommands::getGlobalCommandRegistry();
    const auto* pluginFunc = cmdRegistry.getFunction(upperName);
    
    if (pluginFunc && pluginFunc->functionPtr != nullptr) {
        // Plugin function found - emit native call via runtime context
        builder_.emitComment("Plugin function call: " + upperName);
        
        // Allocate runtime context on stack (pointer size)
        std::string ctxPtr = builder_.newTemp();
        builder_.emitCall(ctxPtr, "l", "fb_context_create", "");
        
        // Marshal arguments into context
        for (size_t i = 0; i < expr->arguments.size() && i < pluginFunc->parameters.size(); ++i) {
            std::string argTemp = emitExpression(expr->arguments[i].get());
            BaseType argType = getExpressionType(expr->arguments[i].get());
            
            const auto& param = pluginFunc->parameters[i];
            
            // Add parameter to context based on type
            switch (param.type) {
                case FasterBASIC::ModularCommands::ParameterType::INT:
                case FasterBASIC::ModularCommands::ParameterType::BOOL: {
                    // Convert to int32 if needed
                    if (typeManager_.isFloatingPoint(argType)) {
                        std::string intTemp = builder_.newTemp();
                        std::string qbeType = typeManager_.getQBEType(argType);
                        builder_.emitRaw("    " + intTemp + " =w " + qbeType + "tosi " + argTemp);
                        argTemp = intTemp;
                    } else if (typeManager_.getQBEType(argType) == "l") {
                        // Truncate long to int
                        std::string intTemp = builder_.newTemp();
                        builder_.emitRaw("    " + intTemp + " =w copy " + argTemp);
                        argTemp = intTemp;
                    }
                    builder_.emitCall("", "", "fb_context_add_int_param", "l " + ctxPtr + ", w " + argTemp);
                    break;
                }
                case FasterBASIC::ModularCommands::ParameterType::FLOAT: {
                    // Convert to float if needed
                    if (typeManager_.isIntegral(argType)) {
                        argTemp = emitTypeConversion(argTemp, argType, BaseType::SINGLE);
                    } else if (argType == BaseType::DOUBLE) {
                        std::string floatTemp = builder_.newTemp();
                        builder_.emitRaw("    " + floatTemp + " =s dtof " + argTemp);
                        argTemp = floatTemp;
                    }
                    builder_.emitCall("", "", "fb_context_add_float_param", "l " + ctxPtr + ", s " + argTemp);
                    break;
                }
                case FasterBASIC::ModularCommands::ParameterType::STRING: {
                    // String argument - pass descriptor pointer
                    if (argType != BaseType::STRING) {
                        // Convert non-string to string
                        argTemp = emitTypeConversion(argTemp, argType, BaseType::STRING);
                    }
                    builder_.emitCall("", "", "fb_context_add_string_param", "l " + ctxPtr + ", l " + argTemp);
                    break;
                }
                default:
                    builder_.emitComment("WARNING: Unsupported plugin parameter type");
                    break;
            }
        }
        
        // Get function pointer and call it
        std::string funcPtrTemp = builder_.newTemp();
        // Cast the function pointer to long (pointer)
        std::stringstream funcPtrStr;
        funcPtrStr << reinterpret_cast<intptr_t>(pluginFunc->functionPtr);
        builder_.emitRaw("    " + funcPtrTemp + " =l copy " + funcPtrStr.str());
        
        // Call the plugin function via indirect call
        // The function signature is: void (*)(FB_RuntimeContext*)
        builder_.emitRaw("    call " + funcPtrTemp + "(l " + ctxPtr + ")");
        
        // Check for errors
        std::string hasError = builder_.newTemp();
        builder_.emitCall(hasError, "w", "fb_context_has_error", "l " + ctxPtr);
        
        std::string errorCheckLabel = "plugin_err_" + std::to_string(builder_.getTempCounter());
        std::string noErrorLabel = "plugin_ok_" + std::to_string(builder_.getTempCounter());
        
        builder_.emitRaw("    jnz " + hasError + ", @" + errorCheckLabel + ", @" + noErrorLabel);
        builder_.emitLabel(errorCheckLabel);
        
        // Get error message and print it
        std::string errorMsg = builder_.newTemp();
        builder_.emitCall(errorMsg, "l", "fb_context_get_error", "l " + ctxPtr);
        runtime_.emitPrintString(errorMsg);
        runtime_.emitPrintNewline();
        
        // Call END to terminate program on error
        builder_.emitCall("", "", "basic_end", "w 1");
        
        builder_.emitLabel(noErrorLabel);
        
        // Extract return value based on function return type
        std::string result;
        switch (pluginFunc->returnType) {
            case FasterBASIC::ModularCommands::ReturnType::INT:
            case FasterBASIC::ModularCommands::ReturnType::BOOL:
                result = builder_.newTemp();
                builder_.emitCall(result, "w", "fb_context_get_return_int", "l " + ctxPtr);
                break;
                
            case FasterBASIC::ModularCommands::ReturnType::FLOAT:
                result = builder_.newTemp();
                builder_.emitCall(result, "s", "fb_context_get_return_float", "l " + ctxPtr);
                break;
                
            case FasterBASIC::ModularCommands::ReturnType::STRING:
                result = builder_.newTemp();
                builder_.emitCall(result, "l", "fb_context_get_return_string", "l " + ctxPtr);
                break;
                
            default:
                result = "0";
                break;
        }
        
        // Destroy context (frees temporary allocations)
        builder_.emitCall("", "", "fb_context_destroy", "l " + ctxPtr);
        
        return result;
    }
    
    // Check for intrinsic/built-in functions
    
    // ABS(x) - Absolute value
    if (upperName == "ABS") {
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: ABS requires exactly 1 argument");
            return "0";
        }
        std::string argTemp = emitExpression(expr->arguments[0].get());
        BaseType argType = getExpressionType(expr->arguments[0].get());
        
        if (typeManager_.isIntegral(argType)) {
            // For integers: use conditional to get absolute value
            std::string isNeg = builder_.newTemp();
            builder_.emitCompare(isNeg, "w", "slt", argTemp, "0");
            
            std::string negVal = builder_.newTemp();
            builder_.emitNeg(negVal, "w", argTemp);
            
            // Use phi-like pattern with conditional
            std::string thenLabel = "abs_neg_" + std::to_string(builder_.getTempCounter());
            std::string elseLabel = "abs_pos_" + std::to_string(builder_.getTempCounter());
            std::string endLabel = "abs_end_" + std::to_string(builder_.getTempCounter());
            std::string result = builder_.newTemp();
            
            builder_.emitRaw("    jnz " + isNeg + ", @" + thenLabel + ", @" + elseLabel);
            builder_.emitLabel(thenLabel);
            builder_.emitRaw("    " + result + " =w copy " + negVal);
            builder_.emitRaw("    jmp @" + endLabel);
            builder_.emitLabel(elseLabel);
            builder_.emitRaw("    " + result + " =w copy " + argTemp);
            builder_.emitLabel(endLabel);
            
            return result;
        } else {
            // For floats/doubles: use runtime function
            return runtime_.emitAbs(argTemp, argType);
        }
    }
    
    // SGN(x) - Sign function (-1, 0, or 1)
    if (upperName == "SGN") {
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: SGN requires exactly 1 argument");
            return "0";
        }
        std::string argTemp = emitExpression(expr->arguments[0].get());
        BaseType argType = getExpressionType(expr->arguments[0].get());
        
        if (typeManager_.isIntegral(argType)) {
            // For integers: branchless using (x > 0) - (x < 0)
            std::string isNeg = builder_.newTemp();
            builder_.emitCompare(isNeg, "w", "slt", argTemp, "0");
            
            std::string isPos = builder_.newTemp();
            builder_.emitCompare(isPos, "w", "sgt", argTemp, "0");
            
            std::string result = builder_.newTemp();
            builder_.emitBinary(result, "w", "sub", isPos, isNeg);
            
            return result;
        } else {
            // For floats/doubles: use runtime function
            std::string qbeType = typeManager_.getQBEType(argType);
            std::string result = builder_.newTemp();
            builder_.emitCall(result, "w", "basic_sgn", qbeType + " " + argTemp);
            return result;
        }
    }
    
    if (upperName == "LEN") {
        // LEN(string$) - returns length of string
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: LEN requires exactly 1 argument");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        return runtime_.emitStringLen(strArg);
    }
    
    if (upperName == "MID" || upperName == "MID$") {
        // MID$(string$, start[, length]) - substring extraction
        if (expr->arguments.size() < 2 || expr->arguments.size() > 3) {
            builder_.emitComment("ERROR: MID$ requires 2 or 3 arguments");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        std::string startArg = emitExpression(expr->arguments[1].get());
        std::string lenArg = expr->arguments.size() == 3 ? 
                             emitExpression(expr->arguments[2].get()) : "";
        return runtime_.emitMid(strArg, startArg, lenArg);
    }
    
    if (upperName == "LEFT" || upperName == "LEFT$") {
        // LEFT$(string$, n) - left n characters
        if (expr->arguments.size() != 2) {
            builder_.emitComment("ERROR: LEFT$ requires exactly 2 arguments");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        std::string lenArg = emitExpression(expr->arguments[1].get());
        return runtime_.emitLeft(strArg, lenArg);
    }
    
    if (upperName == "RIGHT" || upperName == "RIGHT$") {
        // RIGHT$(string$, n) - right n characters
        if (expr->arguments.size() != 2) {
            builder_.emitComment("ERROR: RIGHT$ requires exactly 2 arguments");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        std::string lenArg = emitExpression(expr->arguments[1].get());
        return runtime_.emitRight(strArg, lenArg);
    }
    
    if (upperName == "CHR" || upperName == "CHR$") {
        // CHR$(n) - character from ASCII code
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: CHR$ requires exactly 1 argument");
            return "0";
        }
        std::string codeArg = emitExpression(expr->arguments[0].get());
        return runtime_.emitChr(codeArg);
    }
    
    if (upperName == "ASC") {
        // ASC(string$) - ASCII code of first character
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: ASC requires exactly 1 argument");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        return runtime_.emitAsc(strArg);
    }
    
    if (upperName == "STR" || upperName == "STR$") {
        // STR$(n) - convert number to string
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: STR$ requires exactly 1 argument");
            return "0";
        }
        std::string numArg = emitExpression(expr->arguments[0].get());
        BaseType argType = getExpressionType(expr->arguments[0].get());
        return runtime_.emitStr(numArg, argType);
    }
    
    if (upperName == "VAL") {
        // VAL(string$) - convert string to number
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: VAL requires exactly 1 argument");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        return runtime_.emitVal(strArg);
    }
    
    if (upperName == "UCASE" || upperName == "UCASE$") {
        // UCASE$(string$) - convert to uppercase
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: UCASE$ requires exactly 1 argument");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        return runtime_.emitUCase(strArg);
    }
    
    if (upperName == "LCASE" || upperName == "LCASE$") {
        // LCASE$(string$) - convert to lowercase
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: LCASE$ requires exactly 1 argument");
            return "0";
        }
        std::string strArg = emitExpression(expr->arguments[0].get());
        return runtime_.emitLCase(strArg);
    }
    
    if (upperName == "__STRING_SLICE") {
        // __STRING_SLICE(string$, start, end) - internal slice operation
        // Used by parser for slice syntax: text$(start TO end)
        if (expr->arguments.size() != 3) {
            builder_.emitComment("ERROR: __STRING_SLICE requires exactly 3 arguments");
            return "0";
        }
        
        std::string strArg = emitExpression(expr->arguments[0].get());
        std::string startArg = emitExpression(expr->arguments[1].get());
        std::string endArg = emitExpression(expr->arguments[2].get());
        
        // Convert start and end to long if needed
        BaseType startType = getExpressionType(expr->arguments[1].get());
        BaseType endType = getExpressionType(expr->arguments[2].get());
        
        if (typeManager_.isIntegral(startType) && typeManager_.getQBEType(startType) == "w") {
            std::string startLong = builder_.newTemp();
            builder_.emitExtend(startLong, "l", "extsw", startArg);
            startArg = startLong;
        } else if (typeManager_.isFloatingPoint(startType)) {
            startArg = emitTypeConversion(startArg, startType, BaseType::LONG);
        }
        
        if (typeManager_.isIntegral(endType) && typeManager_.getQBEType(endType) == "w") {
            std::string endLong = builder_.newTemp();
            builder_.emitExtend(endLong, "l", "extsw", endArg);
            endArg = endLong;
        } else if (typeManager_.isFloatingPoint(endType)) {
            endArg = emitTypeConversion(endArg, endType, BaseType::LONG);
        }
        
        // Call string_slice runtime function
        std::string result = builder_.newTemp();
        builder_.emitCall(result, "l", "string_slice", "l " + strArg + ", l " + startArg + ", l " + endArg);
        return result;
    }
    
    // Note: INSTR not yet implemented in runtime library
    if (upperName == "INSTR") {
        builder_.emitComment("TODO: INSTR function not yet implemented");
        return "0";
    }
    
    // Math functions that map to runtime
    if (upperName == "SIN" || upperName == "COS" || upperName == "TAN" ||
        upperName == "ATAN" || upperName == "ASIN" || upperName == "ACOS" ||
        upperName == "LOG" || upperName == "EXP" || upperName == "SQRT" || upperName == "SQR") {
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: " + upperName + " requires exactly 1 argument");
            return "0";
        }
        std::string argTemp = emitExpression(expr->arguments[0].get());
        BaseType argType = getExpressionType(expr->arguments[0].get());
        
        // Convert to double if needed
        if (!typeManager_.isFloatingPoint(argType)) {
            argTemp = emitTypeConversion(argTemp, argType, BaseType::DOUBLE);
        }
        
        std::string runtimeFunc = "basic_" + upperName;
        std::transform(runtimeFunc.begin(), runtimeFunc.end(), runtimeFunc.begin(), ::tolower);
        if (upperName == "SQR") runtimeFunc = "basic_sqrt";
        
        std::string result = builder_.newTemp();
        builder_.emitCall(result, "d", runtimeFunc, "d " + argTemp);
        return result;
    }
    
    if (upperName == "INT" || upperName == "FIX") {
        if (expr->arguments.size() != 1) {
            builder_.emitComment("ERROR: " + upperName + " requires exactly 1 argument");
            return "0";
        }
        std::string argTemp = emitExpression(expr->arguments[0].get());
        BaseType argType = getExpressionType(expr->arguments[0].get());
        
        if (typeManager_.isFloatingPoint(argType)) {
            std::string qbeType = typeManager_.getQBEType(argType);
            std::string result = builder_.newTemp();
            builder_.emitRaw("    " + result + " =w " + qbeType + "tosi " + argTemp);
            return result;
        }
        return argTemp;  // Already integer
    }
    
    if (upperName == "RND") {
        // RND() - random number 0.0 to 1.0
        std::string result = builder_.newTemp();
        builder_.emitCall(result, "d", "basic_rnd", "");
        return result;
    }
    
    // Check for user-defined functions (DEF FN)
    const auto& symbolTable = semantic_.getSymbolTable();
    auto funcIt = symbolTable.functions.find(funcName);
    if (funcIt != symbolTable.functions.end()) {
        // User-defined function call
        const auto& funcSymbol = funcIt->second;
        
        builder_.emitComment("User-defined function call: " + funcName);
        
        // Evaluate arguments
        std::vector<std::string> argTemps;
        for (size_t i = 0; i < expr->arguments.size(); ++i) {
            std::string argTemp = emitExpression(expr->arguments[i].get());
            
            // Convert argument to match parameter type if needed
            BaseType argType = getExpressionType(expr->arguments[i].get());
            BaseType paramType = funcSymbol.parameterTypeDescs[i].baseType;
            
            if (argType != paramType) {
                argTemp = emitExpressionAs(expr->arguments[i].get(), paramType);
            }
            
            argTemps.push_back(argTemp);
        }
        
        // Build QBE function name (without $ prefix - emitCall adds it)
        std::string qbeFuncName = "func_" + funcName;
        
        // Get return type
        BaseType returnType = funcSymbol.returnTypeDesc.baseType;
        std::string qbeReturnType = typeManager_.getQBEType(returnType);
        
        // Build argument string
        std::string argsStr;
        for (size_t i = 0; i < argTemps.size(); ++i) {
            if (i > 0) argsStr += ", ";
            // Get parameter type
            BaseType paramType = funcSymbol.parameterTypeDescs[i].baseType;
            std::string qbeParamType = typeManager_.getQBEType(paramType);
            argsStr += qbeParamType + " " + argTemps[i];
        }
        
        // Emit call
        std::string result = builder_.newTemp();
        builder_.emitCall(result, qbeReturnType, qbeFuncName, argsStr);
        return result;
    }
    
    // Unknown function
    builder_.emitComment("ERROR: unknown function " + funcName);
    return "0";
}

void ASTEmitter::emitMethodBody(const std::vector<FasterBASIC::StatementPtr>& body) {
    for (const auto& stmt : body) {
        if (stmt) {
            emitStatement(stmt.get());
        }
    }
}

void ASTEmitter::registerMethodParam(const std::string& name, const std::string& addr, FasterBASIC::BaseType type) {
    methodParamAddresses_[name] = addr;
    methodParamTypes_[name] = type;
}

void ASTEmitter::clearMethodParams() {
    methodParamAddresses_.clear();
    methodParamTypes_.clear();
    methodParamClassNames_.clear();
}

std::string ASTEmitter::emitMethodCall(const MethodCallExpression* expr) {
    if (!expr || !expr->object) {
        builder_.emitComment("ERROR: invalid method call expression");
        return "0";
    }
    
    // Get the object expression - can be a variable or ME
    const VariableExpression* varExpr = dynamic_cast<const VariableExpression*>(expr->object.get());
    const bool isMeCall = (expr->object->getType() == ASTNodeType::EXPR_ME);
    
    std::string objectName;
    if (varExpr) {
        objectName = varExpr->name;
    } else if (isMeCall) {
        objectName = "ME";
    }
    
    if (!varExpr && !isMeCall) {
        builder_.emitComment("ERROR: method call on non-variable expression not yet supported");
        return "0";
    }
    
    std::string methodName = expr->methodName;
    const auto& symbolTable = semantic_.getSymbolTable();
    
    // === CLASS Instance Method Call (virtual dispatch) ===
    {
        const FasterBASIC::ClassSymbol* classSym = nullptr;
        std::string objPtr;
        
        if (isMeCall) {
            objPtr = "%me";
            if (currentClassContext_) {
                classSym = currentClassContext_;
            } else {
                for (const auto& pair : symbolTable.classes) {
                    if (pair.second.findMethod(methodName)) {
                        classSym = &pair.second;
                        break;
                    }
                }
            }
        } else if (varExpr) {
            std::string currentFunc = symbolMapper_.getCurrentFunction();
            const auto* varSym = semantic_.lookupVariableScoped(varExpr->name, currentFunc);
            if (!varSym) {
                varSym = symbolTable.lookupVariableLegacy(varExpr->name);
            }
            if (varSym && varSym->typeDesc.isClassType) {
                classSym = symbolTable.lookupClass(varSym->typeDesc.className);
                objPtr = loadVariable(varExpr->name);
            }
            // --- METHOD-local CLASS instance fallback ---
            // DIM'd CLASS instances inside METHOD bodies are registered in
            // methodParamAddresses_ / methodParamTypes_ but are NOT in the
            // semantic symbol table.  If the symbol-table lookup above did
            // not resolve a class, check if the variable is a method-local
            // CLASS_INSTANCE and look up its class from methodParamClassNames_.
            if (!classSym && currentClassContext_) {
                auto mpTypeIt = methodParamTypes_.find(varExpr->name);
                if (mpTypeIt != methodParamTypes_.end() &&
                    mpTypeIt->second == FasterBASIC::BaseType::CLASS_INSTANCE) {
                    // Look up the CLASS name stored when the variable was DIM'd
                    auto cnIt = methodParamClassNames_.find(varExpr->name);
                    if (cnIt != methodParamClassNames_.end()) {
                        classSym = symbolTable.lookupClass(cnIt->second);
                    }
                    // Fallback: search all classes for one that has the method
                    if (!classSym) {
                        for (const auto& pair : symbolTable.classes) {
                            if (pair.second.findMethod(methodName)) {
                                classSym = &pair.second;
                                break;
                            }
                        }
                    }
                    if (classSym) {
                        objPtr = loadVariable(varExpr->name);
                    }
                }
            }
        }
        
        if (classSym) {
            const auto* methodInfo = classSym->findMethod(methodName);
            if (!methodInfo) {
                builder_.emitComment("ERROR: CLASS '" + classSym->name + "' has no method '" + methodName + "'");
                return "0";
            }
            
            builder_.emitComment("CLASS virtual dispatch: " + objectName + "." + methodName + "()");
            
            // Null check
            int labelId = builder_.getNextLabelId();
            std::string nullLabel = "null_err_" + std::to_string(labelId);
            std::string dispatchLabel = "dispatch_" + std::to_string(labelId);
            
            auto isNull = builder_.newTemp();
            builder_.emitRaw("    " + isNull + " =w ceql " + objPtr + ", 0\n");
            builder_.emitRaw("    jnz " + isNull + ", @" + nullLabel + ", @" + dispatchLabel + "\n");
            
            // Null error block
            builder_.emitLabel(nullLabel);
            std::string methodNameLabel = builder_.registerString(methodName);
            std::string locationStr = "line " + std::to_string(expr->location.line);
            std::string locationLabel = builder_.registerString(locationStr);
            builder_.emitRaw("    call $class_null_method_error(l $" + locationLabel + ", l $" + methodNameLabel + ")\n");
            builder_.emitRaw("    hlt\n");
            
            // Dispatch block
            builder_.emitLabel(dispatchLabel);
            
            // Load vtable pointer from object[0]
            auto vtablePtr = builder_.newTemp();
            builder_.emitRaw("    " + vtablePtr + " =l loadl " + objPtr + "\n");
            
            // Compute method slot address: vtable + VTABLE_METHODS_OFFSET + slot * 8
            int slotOffset = 32 + methodInfo->vtableSlot * 8;
            auto slotAddr = builder_.newTemp();
            builder_.emitRaw("    " + slotAddr + " =l add " + vtablePtr + ", " + std::to_string(slotOffset) + "\n");
            
            // Load method function pointer
            auto methodPtr = builder_.newTemp();
            builder_.emitRaw("    " + methodPtr + " =l loadl " + slotAddr + "\n");
            
            // Build argument list: ME (obj) as first arg, then user args
            std::string callArgs = "l " + objPtr;
            for (size_t i = 0; i < expr->arguments.size(); i++) {
                std::string argType = "l";
                FasterBASIC::BaseType paramBaseType = FasterBASIC::BaseType::LONG;
                if (i < methodInfo->parameterTypes.size()) {
                    paramBaseType = methodInfo->parameterTypes[i].baseType;
                    if (paramBaseType == FasterBASIC::BaseType::INTEGER ||
                        paramBaseType == FasterBASIC::BaseType::UINTEGER) {
                        argType = "w";
                    } else if (paramBaseType == FasterBASIC::BaseType::DOUBLE) {
                        argType = "d";
                    } else if (paramBaseType == FasterBASIC::BaseType::SINGLE) {
                        argType = "s";
                    }
                }
                // Use emitExpressionAs to properly convert argument types
                // (e.g. integer literal 5 → double 5.0 when param is DOUBLE)
                std::string argTemp = emitExpressionAs(expr->arguments[i].get(), paramBaseType);
                callArgs += ", " + argType + " " + argTemp;
            }
            
            // Indirect call through method pointer
            if (methodInfo->returnType.baseType == FasterBASIC::BaseType::VOID) {
                builder_.emitRaw("    call " + methodPtr + "(" + callArgs + ")\n");
                return "0";
            } else {
                std::string retType = "l";
                if (methodInfo->returnType.baseType == FasterBASIC::BaseType::INTEGER ||
                    methodInfo->returnType.baseType == FasterBASIC::BaseType::UINTEGER) {
                    retType = "w";
                } else if (methodInfo->returnType.baseType == FasterBASIC::BaseType::DOUBLE) {
                    retType = "d";
                } else if (methodInfo->returnType.baseType == FasterBASIC::BaseType::SINGLE) {
                    retType = "s";
                }
                auto result = builder_.newTemp();
                builder_.emitRaw("    " + result + " =" + retType + " call " + methodPtr + "(" + callArgs + ")\n");
                return result;
            }
        }
    }
    
    // === Runtime Object Method Call (HASHMAP, etc.) ===
    if (!varExpr) {
        builder_.emitComment("ERROR: method call requires a variable for runtime objects");
        return "0";
    }
    
    const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(objectName);
    if (!varSym) {
        builder_.emitComment("ERROR: undefined variable " + objectName);
        return "0";
    }
    
    const FasterBASIC::TypeDescriptor& objectTypeDesc = varSym->typeDesc;
    
    auto& registry = FasterBASIC::getRuntimeObjectRegistry();
    if (!registry.isObjectType(objectTypeDesc)) {
        builder_.emitComment("ERROR: method call on non-object type");
        return "0";
    }
    
    const FasterBASIC::ObjectTypeDescriptor* objDesc = registry.getObjectType(objectTypeDesc.objectTypeName);
    if (!objDesc) {
        builder_.emitComment("ERROR: object type not found in registry");
        return "0";
    }
    
    const FasterBASIC::MethodSignature* method = objDesc->findMethod(methodName);
    if (!method) {
        builder_.emitComment("ERROR: object has no method '" + methodName + "'");
        return "0";
    }
    
    builder_.emitComment(objDesc->typeName + " method: " + objectName + "." + methodName + "(...)");
    
    std::string objectPtr = loadVariable(objectName);
    
    size_t requiredArgs = method->requiredParamCount();
    size_t totalArgs = method->totalParamCount();
    size_t providedArgs = expr->arguments.size();
    
    if (providedArgs < requiredArgs) {
        builder_.emitComment("ERROR: " + methodName + " requires at least " + 
                           std::to_string(requiredArgs) + " argument(s), got " + 
                           std::to_string(providedArgs));
        return "0";
    }
    
    if (providedArgs > totalArgs) {
        builder_.emitComment("WARNING: " + methodName + " expects at most " + 
                           std::to_string(totalArgs) + " argument(s), got " + 
                           std::to_string(providedArgs));
    }
    
    std::string argsStr = "l " + objectPtr;
    
    for (size_t i = 0; i < providedArgs && i < method->parameters.size(); ++i) {
        const auto& param = method->parameters[i];
        std::string argValue = emitExpressionAs(expr->arguments[i].get(), param.type);
        
        if (param.type == BaseType::STRING) {
            std::string cStringPtr = builder_.newTemp();
            builder_.emitCall(cStringPtr, "l", "string_to_utf8", "l " + argValue);
            argsStr += ", l " + cStringPtr;
        } else {
            std::string qbeType = typeManager_.getQBEType(param.type);
            argsStr += ", " + qbeType + " " + argValue;
        }
    }
    
    if (method->returnType == BaseType::UNKNOWN) {
        builder_.emitCall("", "", method->runtimeFunctionName, argsStr);
        return "0";
    } else {
        std::string qbeReturnType = typeManager_.getQBEType(method->returnType);
        std::string result = builder_.newTemp();
        builder_.emitCall(result, qbeReturnType, method->runtimeFunctionName, argsStr);
        
        if (method->returnType == BaseType::LONG && qbeReturnType == "l") {
            std::string result32 = builder_.newTemp();
            builder_.emitInstruction(result32 + " =w copy " + result);
            return result32;
        }
        
        return result;
    }
}

// === Binary Operation Helpers ===

std::string ASTEmitter::emitArithmeticOp(const std::string& left, const std::string& right,
                                         TokenType op, BaseType type) {
    // Special case: MOD operator with floating-point types needs to call fmod() runtime function
    if (op == TokenType::MOD && (type == BaseType::SINGLE || type == BaseType::DOUBLE)) {
        std::string result = builder_.newTemp();
        
        // Convert operands to double for fmod() call
        std::string leftDouble = left;
        std::string rightDouble = right;
        
        if (type == BaseType::SINGLE) {
            leftDouble = builder_.newTemp();
            rightDouble = builder_.newTemp();
            builder_.emitInstruction(leftDouble + " =d exts " + left);
            builder_.emitInstruction(rightDouble + " =d exts " + right);
        }
        
        // Call fmod(double, double) -> double
        std::string fmodResult = builder_.newTemp();
        builder_.emitCall(fmodResult, "d", "fmod", "d " + leftDouble + ", d " + rightDouble);
        
        // Convert result back to original type if needed
        if (type == BaseType::SINGLE) {
            builder_.emitInstruction(result + " =s truncd " + fmodResult);
        } else {
            result = fmodResult;  // Already double
        }
        
        return result;
    }
    
    // Special case: POWER operator needs to call pow() runtime function
    if (op == TokenType::POWER) {
        std::string result = builder_.newTemp();
        
        // Convert operands to double for pow() call
        std::string leftDouble = left;
        std::string rightDouble = right;
        
        if (type != BaseType::DOUBLE) {
            // Convert to double
            if (typeManager_.isIntegral(type)) {
                leftDouble = builder_.newTemp();
                rightDouble = builder_.newTemp();
                builder_.emitInstruction(leftDouble + " =d swtof " + left);
                builder_.emitInstruction(rightDouble + " =d swtof " + right);
            } else if (type == BaseType::SINGLE) {
                leftDouble = builder_.newTemp();
                rightDouble = builder_.newTemp();
                builder_.emitInstruction(leftDouble + " =d exts " + left);
                builder_.emitInstruction(rightDouble + " =d exts " + right);
            }
        }
        
        // Call pow(double, double) -> double
        std::string powResult = builder_.newTemp();
        builder_.emitCall(powResult, "d", "pow", "d " + leftDouble + ", d " + rightDouble);
        
        // Convert result back to original type if needed
        if (type == BaseType::INTEGER || type == BaseType::UINTEGER) {
            builder_.emitInstruction(result + " =w dtosi " + powResult);
        } else if (type == BaseType::LONG || type == BaseType::ULONG) {
            builder_.emitInstruction(result + " =l dtosi " + powResult);
        } else if (type == BaseType::SINGLE) {
            builder_.emitInstruction(result + " =s truncd " + powResult);
        } else {
            result = powResult;  // Already double
        }
        
        return result;
    }
    
    // Regular arithmetic operations
    std::string qbeType = typeManager_.getQBEType(type);
    std::string qbeOp = getQBEArithmeticOp(op);
    
    std::string result = builder_.newTemp();
    builder_.emitBinary(result, qbeType, qbeOp, left, right);
    
    return result;
}

std::string ASTEmitter::emitComparisonOp(const std::string& left, const std::string& right,
                                         TokenType op, BaseType type) {
    std::string qbeType = typeManager_.getQBEType(type);
    std::string qbeOp = getQBEComparisonOp(op);
    
    std::string result = builder_.newTemp();
    builder_.emitCompare(result, qbeType, qbeOp, left, right);
    
    return result;
}

std::string ASTEmitter::emitLogicalOp(const std::string& left, const std::string& right,
                                      TokenType op) {
    std::string result = builder_.newTemp();
    
    if (op == TokenType::AND) {
        builder_.emitBinary(result, "w", "and", left, right);
    } else if (op == TokenType::OR) {
        builder_.emitBinary(result, "w", "or", left, right);
    } else if (op == TokenType::XOR) {
        builder_.emitBinary(result, "w", "xor", left, right);
    } else {
        builder_.emitComment("ERROR: unsupported logical operator");
        builder_.emitBinary(result, "w", "copy", left, "0");
    }
    
    return result;
}

std::string ASTEmitter::emitStringOp(const std::string& left, const std::string& right,
                                     TokenType op) {
    if (op == TokenType::PLUS) {
        // String concatenation
        return runtime_.emitStringConcat(left, right);
    } else if (op == TokenType::EQUAL) {
        // String equality
        std::string cmpResult = runtime_.emitStringCompare(left, right);
        std::string result = builder_.newTemp();
        builder_.emitCompare(result, "w", "eq", cmpResult, "0");
        return result;
    } else if (op == TokenType::NOT_EQUAL) {
        // String inequality
        std::string cmpResult = runtime_.emitStringCompare(left, right);
        std::string result = builder_.newTemp();
        builder_.emitCompare(result, "w", "ne", cmpResult, "0");
        return result;
    } else {
        builder_.emitComment("ERROR: unsupported string operator");
        return "0";
    }
}

// === Type Conversion Helpers ===

std::string ASTEmitter::emitTypeConversion(const std::string& value,
                                           BaseType fromType, BaseType toType) {
    if (fromType == toType) {
        return value;
    }
    
    std::string convOp = typeManager_.getConversionOp(fromType, toType);
    if (convOp.empty()) {
        return value;
    }
    
    // Handle integer to double conversions — go directly to double
    // NOTE: QBE's swtof/sltof can target "d" (double) directly.
    // The old code went int→single→double which lost precision for
    // integers > ~16M (SINGLE has only ~7 decimal digits of precision).
    if (convOp == "INT_TO_DOUBLE_W" || convOp == "INT_TO_DOUBLE_L") {
        std::string result = builder_.newTemp();
        std::string op1 = (convOp == "INT_TO_DOUBLE_W") ? "swtof" : "sltof";
        builder_.emitConvert(result, "d", op1, value);
        return result;
    }
    
    // Handle special two-step conversions for double/float to long
    if (convOp == "DOUBLE_TO_LONG") {
        // QBE doesn't have direct double→long, must go double→int→long
        std::string intTemp = builder_.newTemp();
        builder_.emitConvert(intTemp, "w", "dtosi", value);
        
        std::string result = builder_.newTemp();
        builder_.emitConvert(result, "l", "extsw", intTemp);
        return result;
    }
    
    if (convOp == "FLOAT_TO_LONG") {
        // QBE doesn't have direct float→long, must go float→int→long
        std::string intTemp = builder_.newTemp();
        builder_.emitConvert(intTemp, "w", "stosi", value);
        
        std::string result = builder_.newTemp();
        builder_.emitConvert(result, "l", "extsw", intTemp);
        return result;
    }
    
    std::string qbeToType = typeManager_.getQBEType(toType);
    std::string result = builder_.newTemp();
    
    builder_.emitConvert(result, qbeToType, convOp, value);
    
    return result;
}

// === Statement Emission ===

void ASTEmitter::emitStatement(const Statement* stmt) {
    if (!stmt) {
        builder_.emitComment("ERROR: null statement");
        return;
    }
    
    switch (stmt->getType()) {
        case ASTNodeType::STMT_LET:
            emitLetStatement(static_cast<const LetStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_PRINT:
            emitPrintStatement(static_cast<const PrintStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_INPUT:
            emitInputStatement(static_cast<const InputStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_END:
            emitEndStatement(static_cast<const EndStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_DIM:
            emitDimStatement(static_cast<const DimStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_REDIM:
            emitRedimStatement(static_cast<const RedimStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_ERASE:
            emitEraseStatement(static_cast<const EraseStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_FOR:
            if (currentClassContext_) {
                emitForDirect(static_cast<const ForStatement*>(stmt));
            } else {
                emitForInit(static_cast<const ForStatement*>(stmt));
            }
            break;
            
        case ASTNodeType::STMT_FOR_IN:
            emitForEachInit(static_cast<const ForInStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_WHILE:
            if (currentClassContext_) {
                emitWhileDirect(static_cast<const WhileStatement*>(stmt));
            } else {
                // WHILE condition is handled by CFG edges
                builder_.emitComment("WHILE loop header");
            }
            break;
            
        case ASTNodeType::STMT_DO:
            // DO condition is handled by CFG edges
            builder_.emitComment("DO loop header");
            break;
            
        case ASTNodeType::STMT_LOOP:
            // LOOP condition is handled by CFG edges
            builder_.emitComment("LOOP statement");
            break;
            
        case ASTNodeType::STMT_IF:
            if (currentClassContext_) {
                emitIfDirect(static_cast<const IfStatement*>(stmt));
            } else {
                // IF condition is handled by CFG edges
                builder_.emitComment("IF statement");
            }
            break;
            
        case ASTNodeType::STMT_GOSUB:
            // GOSUB is handled by CFG edges
            builder_.emitComment("GOSUB statement");
            break;
            
        case ASTNodeType::STMT_READ:
            emitReadStatement(static_cast<const ReadStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_SLICE_ASSIGN:
            emitSliceAssignStatement(static_cast<const SliceAssignStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_RESTORE:
            emitRestoreStatement(static_cast<const RestoreStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_LOCAL:
            // LOCAL is like DIM but for function-local variables
            emitLocalStatement(static_cast<const LocalStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_SHARED:
            // SHARED is purely declarative - no code emission needed
            // Variables are already registered during function entry
            break;
            
        case ASTNodeType::STMT_GLOBAL:
            // GLOBAL is purely declarative - no code emission needed
            // Variables are declared at module level
            break;
            
        case ASTNodeType::STMT_CALL:
            emitCallStatement(static_cast<const CallStatement*>(stmt));
            break;
            
        case ASTNodeType::STMT_RETURN:
            emitReturnStatement(static_cast<const ReturnStatement*>(stmt));
            break;
            
        // CLASS & Object System statements
        case ASTNodeType::STMT_CLASS:
            // CLASS declarations are not executable — they are processed at compile time
            // (vtable data and method functions are emitted separately)
            builder_.emitComment("CLASS declaration (processed at compile time)");
            break;
            
        case ASTNodeType::STMT_DELETE: {
            const auto* delStmt = static_cast<const DeleteStatement*>(stmt);
            builder_.emitComment("DELETE " + delStmt->variableName);
            std::string varAddr = getVariableAddress(delStmt->variableName);
            builder_.emitRaw("    call $class_object_delete(l " + varAddr + ")\n");
            break;
        }
            
        default:
            builder_.emitComment("TODO: statement type " + std::to_string(static_cast<int>(stmt->getType())) + " not yet implemented");
            break;
    }
}

void ASTEmitter::emitLetStatement(const LetStatement* stmt) {
    // Invalidate array element cache - assignment may change index variables or array contents
    clearArrayElementCache();
    // Check if this is UDT member assignment: udt.field = value or array(i).field = value
    if (!stmt->memberChain.empty()) {
        // === CLASS Instance Member Assignment (fast path) ===
        // Check if the base variable is a CLASS instance — use pointer + offset store
        if (stmt->indices.empty()) {
            // Special case: ME.Field = value  (inside METHOD/CONSTRUCTOR)
            if (stmt->variable == "ME" && currentClassContext_) {
                const auto& symbolTable = semantic_.getSymbolTable();
                const FasterBASIC::ClassSymbol* classSym = currentClassContext_;
                {
                    std::string objPtr = "%me";
                    const FasterBASIC::ClassSymbol* currentClass = classSym;

                    // Traverse all but the last member (for nested access like ME.inner.field)
                    for (size_t i = 0; i + 1 < stmt->memberChain.size(); i++) {
                        const auto* fi = currentClass->findField(stmt->memberChain[i]);
                        if (!fi) {
                            builder_.emitComment("ERROR: CLASS '" + currentClass->name + "' has no field '" + stmt->memberChain[i] + "'");
                            return;
                        }
                        auto addr = builder_.newTemp();
                        builder_.emitRaw("    " + addr + " =l add " + objPtr + ", " + std::to_string(fi->offset) + "\n");
                        objPtr = builder_.newTemp();
                        builder_.emitRaw("    " + objPtr + " =l loadl " + addr + "\n");
                        if (fi->typeDesc.isClassType) {
                            currentClass = symbolTable.lookupClass(fi->typeDesc.className);
                            if (!currentClass) {
                                builder_.emitComment("ERROR: CLASS '" + fi->typeDesc.className + "' not defined");
                                return;
                            }
                        }
                    }

                    const std::string& finalMember = stmt->memberChain.back();
                    const auto* fieldInfo = currentClass->findField(finalMember);
                    if (!fieldInfo) {
                        builder_.emitComment("ERROR: CLASS '" + currentClass->name + "' has no field '" + finalMember + "'");
                        return;
                    }

                    std::string chainStr = "ME";
                    for (const auto& m : stmt->memberChain) chainStr += "." + m;
                    builder_.emitComment("CLASS member assignment: " + chainStr + " (offset " + std::to_string(fieldInfo->offset) + ")");

                    std::string val = emitExpression(stmt->value.get());

                    auto fieldAddr = builder_.newTemp();
                    builder_.emitRaw("    " + fieldAddr + " =l add " + objPtr + ", " + std::to_string(fieldInfo->offset) + "\n");

                    if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::INTEGER ||
                        fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::UINTEGER) {
                        builder_.emitRaw("    storew " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::SINGLE) {
                        builder_.emitRaw("    stores " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::DOUBLE) {
                        builder_.emitRaw("    stored " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::BYTE ||
                               fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::UBYTE) {
                        builder_.emitRaw("    storeb " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::SHORT ||
                               fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::USHORT) {
                        builder_.emitRaw("    storeh " + val + ", " + fieldAddr + "\n");
                    } else {
                        builder_.emitRaw("    storel " + val + ", " + fieldAddr + "\n");
                    }
                    return;
                }
            }

            std::string currentFunc = symbolMapper_.getCurrentFunction();
            const auto* varSymbol = semantic_.lookupVariableScoped(stmt->variable, currentFunc);
            if (varSymbol && varSymbol->typeDesc.isClassType) {
                const auto& symbolTable = semantic_.getSymbolTable();
                const FasterBASIC::ClassSymbol* classSym = symbolTable.lookupClass(varSymbol->typeDesc.className);
                if (classSym) {
                    // Walk the member chain through class fields
                    std::string objPtr = loadVariable(stmt->variable);

                    // Null-check before field store
                    {
                        int labelId = builder_.getNextLabelId();
                        std::string nullLabel = "null_store_err_" + std::to_string(labelId);
                        std::string okLabel = "store_ok_" + std::to_string(labelId);

                        auto isNull = builder_.newTemp();
                        builder_.emitRaw("    " + isNull + " =w ceql " + objPtr + ", 0\n");
                        builder_.emitRaw("    jnz " + isNull + ", @" + nullLabel + ", @" + okLabel + "\n");

                        builder_.emitLabel(nullLabel);
                        std::string fieldNameLabel = builder_.registerString(stmt->memberChain.front());
                        std::string locationStr = "line " + std::to_string(stmt->location.line);
                        std::string locationLabel = builder_.registerString(locationStr);
                        builder_.emitRaw("    call $class_null_field_error(l $" + locationLabel + ", l $" + fieldNameLabel + ")\n");
                        builder_.emitRaw("    hlt\n");

                        builder_.emitLabel(okLabel);
                    }

                    const FasterBASIC::ClassSymbol* currentClass = classSym;

                    // Traverse all but the last member (for nested access like obj.inner.field)
                    for (size_t i = 0; i + 1 < stmt->memberChain.size(); i++) {
                        const auto* fi = currentClass->findField(stmt->memberChain[i]);
                        if (!fi) {
                            builder_.emitComment("ERROR: CLASS '" + currentClass->name + "' has no field '" + stmt->memberChain[i] + "'");
                            return;
                        }
                        // Load the nested object pointer
                        auto addr = builder_.newTemp();
                        builder_.emitRaw("    " + addr + " =l add " + objPtr + ", " + std::to_string(fi->offset) + "\n");
                        objPtr = builder_.newTemp();
                        builder_.emitRaw("    " + objPtr + " =l loadl " + addr + "\n");
                        if (fi->typeDesc.isClassType) {
                            currentClass = symbolTable.lookupClass(fi->typeDesc.className);
                            if (!currentClass) {
                                builder_.emitComment("ERROR: CLASS '" + fi->typeDesc.className + "' not defined");
                                return;
                            }
                        }
                    }

                    // Now assign to the final field
                    const std::string& finalMember = stmt->memberChain.back();
                    const auto* fieldInfo = currentClass->findField(finalMember);
                    if (!fieldInfo) {
                        builder_.emitComment("ERROR: CLASS '" + currentClass->name + "' has no field '" + finalMember + "'");
                        return;
                    }

                    std::string chainStr = stmt->variable;
                    for (const auto& m : stmt->memberChain) chainStr += "." + m;
                    builder_.emitComment("CLASS member assignment: " + chainStr + " (offset " + std::to_string(fieldInfo->offset) + ")");

                    // Emit the value expression
                    std::string val = emitExpression(stmt->value.get());

                    // Compute field address
                    auto fieldAddr = builder_.newTemp();
                    builder_.emitRaw("    " + fieldAddr + " =l add " + objPtr + ", " + std::to_string(fieldInfo->offset) + "\n");

                    // Store based on field type
                    if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::INTEGER ||
                        fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::UINTEGER) {
                        builder_.emitRaw("    storew " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::SINGLE) {
                        builder_.emitRaw("    stores " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::DOUBLE) {
                        builder_.emitRaw("    stored " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::BYTE ||
                               fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::UBYTE) {
                        builder_.emitRaw("    storeb " + val + ", " + fieldAddr + "\n");
                    } else if (fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::SHORT ||
                               fieldInfo->typeDesc.baseType == FasterBASIC::BaseType::USHORT) {
                        builder_.emitRaw("    storeh " + val + ", " + fieldAddr + "\n");
                    } else {
                        // Default: pointer-sized store (STRING, CLASS_INSTANCE, LONG, etc.)
                        builder_.emitRaw("    storel " + val + ", " + fieldAddr + "\n");
                    }
                    return;
                }
            }
        }

        // === Standard UDT member assignment below ===
        // Handle UDT member assignment (including nested: O.Item.Value = 99)
        if (!stmt->indices.empty()) {
            // Array element member assignment: Points(0).X = 10
            builder_.emitComment("Array element UDT member assignment: " + stmt->variable + "(...).member");
        } else {
            // Simple or nested UDT member assignment
            std::string chainStr = stmt->variable;
            for (const auto& m : stmt->memberChain) {
                chainStr += "." + m;
            }
            builder_.emitComment("UDT member assignment: " + chainStr);
        }
        
        // Build the base address by traversing all but the last member in the chain
        std::string basePtr;
        std::string udtTypeName;
        
        // Handle nested member chains (e.g., O.Item.Value - traverse O.Item first)
        if (stmt->memberChain.size() > 1) {
            // Multi-level: need to traverse all but the last member
            // Start with the variable
            std::string currentFunc = symbolMapper_.getCurrentFunction();
            const auto* varSymbol = semantic_.lookupVariableScoped(stmt->variable, currentFunc);
            if (!varSymbol || varSymbol->typeDesc.baseType != BaseType::USER_DEFINED) {
                builder_.emitComment("ERROR: Base variable not UDT: " + stmt->variable);
                return;
            }
            
            // Get base address
            std::string mangledName = symbolMapper_.mangleVariableName(stmt->variable, varSymbol->scope.isGlobal());
            basePtr = builder_.newTemp();
            
            // Check if this is a UDT parameter (passed by pointer/reference)
            bool isUDTParam = (symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(stmt->variable) &&
                               varSymbol->typeDesc.baseType == BaseType::USER_DEFINED);
            
            if (isUDTParam) {
                // UDT parameter: stack slot holds a pointer TO the actual struct
                builder_.emitComment("Load UDT parameter pointer (pass-by-ref): " + stmt->variable);
                builder_.emitLoad(basePtr, "l", mangledName);
            } else if (varSymbol->scope.isGlobal()) {
                builder_.emitRaw("    " + basePtr + " =l copy " + mangledName);
            } else {
                builder_.emitRaw("    " + basePtr + " =l copy " + mangledName);
            }
            
            // Get UDT type name - try typeName first, fall back to typeDesc.udtName
            std::string currentUDTName = varSymbol->typeName;
            if (currentUDTName.empty()) {
                currentUDTName = varSymbol->typeDesc.udtName;
            }
            
            // Traverse all but the last member
            for (size_t i = 0; i < stmt->memberChain.size() - 1; ++i) {
                const auto& memberName = stmt->memberChain[i];
                
                // Look up current UDT
                const auto& symbolTable = semantic_.getSymbolTable();
                auto udtIt = symbolTable.types.find(currentUDTName);
                if (udtIt == symbolTable.types.end()) {
                    builder_.emitComment("ERROR: UDT not found: " + currentUDTName);
                    return;
                }
                
                const auto& udtDef = udtIt->second;
                
                // Find the field
                int fieldIndex = -1;
                BaseType fieldType = BaseType::UNKNOWN;
                std::string fieldUDTName;
                
                for (size_t j = 0; j < udtDef.fields.size(); ++j) {
                    if (udtDef.fields[j].name == memberName) {
                        fieldIndex = static_cast<int>(j);
                        fieldType = udtDef.fields[j].typeDesc.baseType;
                        if (fieldType == BaseType::USER_DEFINED) {
                            fieldUDTName = udtDef.fields[j].typeDesc.udtName;
                        }
                        break;
                    }
                }
                
                if (fieldIndex < 0) {
                    builder_.emitComment("ERROR: Field not found: " + memberName);
                    return;
                }
                
                // Calculate offset to this field
                int64_t offset = 0;
                for (int j = 0; j < fieldIndex; ++j) {
                    if (udtDef.fields[j].typeDesc.baseType == BaseType::USER_DEFINED) {
                        auto nestedIt = symbolTable.types.find(udtDef.fields[j].typeDesc.udtName);
                        if (nestedIt != symbolTable.types.end()) {
                            offset += typeManager_.getUDTSizeRecursive(nestedIt->second, symbolTable.types);
                        }
                    } else {
                        offset += typeManager_.getTypeSize(udtDef.fields[j].typeDesc.baseType);
                    }
                }
                
                // Add offset to base pointer
                if (offset > 0) {
                    std::string newBasePtr = builder_.newTemp();
                    builder_.emitBinary(newBasePtr, "l", "add", basePtr, std::to_string(offset));
                    basePtr = newBasePtr;
                }
                
                // Update current UDT name for next iteration
                if (fieldType != BaseType::USER_DEFINED) {
                    builder_.emitComment("ERROR: Intermediate member is not UDT: " + memberName);
                    return;
                }
                currentUDTName = fieldUDTName;
            }
            
            // Now basePtr points to the parent UDT of the final field
            udtTypeName = currentUDTName;
            
        } else if (!stmt->indices.empty()) {
            // Array element: Points(0).X = 10
            const auto& symbolTable = semantic_.getSymbolTable();
            auto arrIt = symbolTable.arrays.find(stmt->variable);
            if (arrIt == symbolTable.arrays.end()) {
                builder_.emitComment("ERROR: Array not found: " + stmt->variable);
                return;
            }
            
            const auto& arraySymbol = arrIt->second;
            
            // Array element must be UDT type
            if (arraySymbol.elementTypeDesc.baseType != BaseType::USER_DEFINED) {
                builder_.emitComment("ERROR: Array element is not UDT: " + stmt->variable);
                return;
            }
            
            // Get array element address
            basePtr = emitArrayElementAddress(stmt->variable, stmt->indices);
            udtTypeName = arraySymbol.elementTypeDesc.udtName;
            
        } else {
            // Simple variable: P.X = 10
            std::string currentFunc = symbolMapper_.getCurrentFunction();
            const auto* varSymbol = semantic_.lookupVariableScoped(stmt->variable, currentFunc);
            if (!varSymbol) {
                builder_.emitComment("ERROR: Variable not found: " + stmt->variable);
                return;
            }
            
            // Must be a UDT
            if (varSymbol->typeDesc.baseType != BaseType::USER_DEFINED) {
                builder_.emitComment("ERROR: Member access on non-UDT variable: " + stmt->variable);
                return;
            }
            
            // Get the base address of the UDT variable
            std::string mangledName = symbolMapper_.mangleVariableName(stmt->variable, varSymbol->scope.isGlobal());
            basePtr = builder_.newTemp();
            
            // Check if this is a UDT parameter (passed by pointer/reference)
            bool isUDTParam = (symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(stmt->variable) &&
                               varSymbol->typeDesc.baseType == BaseType::USER_DEFINED);
            
            if (isUDTParam) {
                // UDT parameter: stack slot holds a pointer TO the actual struct
                builder_.emitComment("Load UDT parameter pointer (pass-by-ref): " + stmt->variable);
                builder_.emitLoad(basePtr, "l", mangledName);
            } else if (varSymbol->scope.isGlobal()) {
                // Global UDT - get address (mangledName already includes $ prefix)
                builder_.emitRaw("    " + basePtr + " =l copy " + mangledName);
            } else {
                // Local UDT - get address from stack (mangledName already includes % prefix)
                builder_.emitRaw("    " + basePtr + " =l copy " + mangledName);
            }
            
            // Get UDT type name - try typeName first, fall back to typeDesc.udtName
            udtTypeName = varSymbol->typeName;
            if (udtTypeName.empty()) {
                udtTypeName = varSymbol->typeDesc.udtName;
            }
        }
        
        // Look up the UDT definition
        const auto& symbolTable = semantic_.getSymbolTable();
        const auto& udtMap = symbolTable.types;
        auto udtIt = udtMap.find(udtTypeName);
        if (udtIt == udtMap.end()) {
            builder_.emitComment("ERROR: UDT not found: " + udtTypeName);
            return;
        }
        
        const auto& udtDef = udtIt->second;
        std::string memberName = stmt->memberChain.back();  // Use LAST member in chain
        
        // Find the field
        int fieldIndex = -1;
        BaseType fieldType = BaseType::UNKNOWN;
        
        for (size_t i = 0; i < udtDef.fields.size(); ++i) {
            if (udtDef.fields[i].name == memberName) {
                fieldIndex = static_cast<int>(i);
                fieldType = udtDef.fields[i].typeDesc.baseType;
                break;
            }
        }
        
        if (fieldIndex < 0) {
            builder_.emitComment("ERROR: Field not found: " + memberName + " in UDT " + udtTypeName);
            return;
        }
        
        // Calculate field offset (accounting for nested UDT fields)
        int64_t offset = 0;
        const auto& symbolTable2 = semantic_.getSymbolTable();
        for (int i = 0; i < fieldIndex; ++i) {
            if (udtDef.fields[i].typeDesc.baseType == BaseType::USER_DEFINED) {
                // Nested UDT field - use recursive size calculation
                auto nestedUdtIt = symbolTable2.types.find(udtDef.fields[i].typeDesc.udtName);
                if (nestedUdtIt != symbolTable2.types.end()) {
                    offset += typeManager_.getUDTSizeRecursive(nestedUdtIt->second, symbolTable2.types);
                }
            } else {
                offset += typeManager_.getTypeSize(udtDef.fields[i].typeDesc.baseType);
            }
        }
        
        // Emit the value expression with proper type
        std::string value = emitExpressionAs(stmt->value.get(), fieldType);
        
        // Add field offset to base pointer
        std::string fieldPtr = builder_.newTemp();
        if (offset > 0) {
            builder_.emitBinary(fieldPtr, "l", "add", basePtr, std::to_string(offset));
        } else {
            fieldPtr = basePtr;
        }
        
        // Store the value at the field address
        std::string qbeType = typeManager_.getQBEType(fieldType);
        if (fieldType == BaseType::STRING) {
            // String fields are stored as pointers to StringDescriptor
            builder_.emitStore("l", value, fieldPtr);
        } else {
            builder_.emitStore(qbeType, value, fieldPtr);
        }
        
        return;
    }
    
    // Check if this is UDT-to-UDT assignment: P2 = P1
    // This must come BEFORE object subscript check and AFTER member chain check
    if (stmt->memberChain.empty() && stmt->indices.empty()) {
        // Simple variable assignment - check if both sides are UDTs
        BaseType targetType = getVariableType(stmt->variable);
        
        if (targetType == BaseType::USER_DEFINED) {
            // Get the UDT type name and definition for the target variable
            std::string currentFunc = symbolMapper_.getCurrentFunction();
            const auto* targetVarSymbol = semantic_.lookupVariableScoped(stmt->variable, currentFunc);
            if (!targetVarSymbol) {
                builder_.emitComment("ERROR: Target UDT variable not found: " + stmt->variable);
                return;
            }
            
            std::string targetUDTName = targetVarSymbol->typeName;
            if (targetUDTName.empty()) {
                targetUDTName = targetVarSymbol->typeDesc.udtName;
            }
            
            const auto& symbolTable = semantic_.getSymbolTable();
            auto udtIt = symbolTable.types.find(targetUDTName);
            if (udtIt == symbolTable.types.end()) {
                builder_.emitComment("ERROR: UDT type not found: " + targetUDTName);
                return;
            }
            
            const auto& udtDef = udtIt->second;
            
            // Get target UDT base address
            std::string targetAddr = getVariableAddress(stmt->variable);
            
            // ── NEON Phase 2: try element-wise UDT arithmetic first ──
            // Detects C = A + B (and -, *, /) where A, B, C are the same
            // SIMD-eligible UDT type and emits NEON vector instructions.
            if (tryEmitNEONArithmetic(stmt, targetAddr, udtDef, symbolTable.types)) {
                builder_.emitComment("End NEON UDT arithmetic assignment");
                return;
            }
            
            // ── Scalar fallback for UDT arithmetic (when NEON disabled) ──
            // Detects C = A + B (and -, *, /) where A, B, C are the same
            // UDT type and emits scalar field-by-field arithmetic.
            if (emitScalarUDTArithmetic(stmt, targetAddr, udtDef, symbolTable.types)) {
                builder_.emitComment("End scalar UDT arithmetic assignment");
                return;
            }
            
            // Target is a UDT - check if source is also a UDT (or UDT member access)
            BaseType sourceType = getExpressionType(stmt->value.get());
            
            if (sourceType == BaseType::USER_DEFINED) {
                // UDT-to-UDT assignment: P2 = P1
                builder_.emitComment("UDT-to-UDT assignment: " + stmt->variable + " = <UDT>");
                
                // Get source UDT address based on source expression type
                std::string sourceAddr;
                
                if (stmt->value->getType() == ASTNodeType::EXPR_VARIABLE) {
                    // Simple variable: P1
                    const auto* varExpr = static_cast<const VariableExpression*>(stmt->value.get());
                    sourceAddr = getVariableAddress(varExpr->name);
                } else if (stmt->value->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
                    // Member access: Container.Inner (returns address for UDT fields)
                    sourceAddr = emitMemberAccessExpression(
                        static_cast<const MemberAccessExpression*>(stmt->value.get()));
                } else if (stmt->value->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
                    // Array element: People(i) (where People is array of UDTs)
                    const auto* arrExpr = static_cast<const ArrayAccessExpression*>(stmt->value.get());
                    sourceAddr = emitArrayElementAddress(arrExpr->name, arrExpr->indices);
                } else {
                    builder_.emitComment("ERROR: Unsupported UDT source expression type");
                    return;
                }
                
                // Copy field-by-field using recursive helper (handles strings
                // with proper refcounting at any nesting depth)
                builder_.emitComment("Copying UDT fields with proper string handling");
                emitUDTCopyFieldByField(sourceAddr, targetAddr, udtDef, symbolTable.types);
                
                builder_.emitComment("End UDT-to-UDT assignment");
                return;
            }
        }
    }
    
    // Check if this is an object subscript assignment: obj("key") = value
    if (!stmt->indices.empty()) {
        // Use semantic analyzer's symbol table lookup to handle scoped variable names
        const auto& symbolTable = semantic_.getSymbolTable();
        const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(stmt->variable);
        
        // Check if the variable is an object type with subscript operator
        if (varSym && varSym->typeDesc.isObject()) {
            // This is object subscript assignment: obj(key) = value
            auto& registry = FasterBASIC::getRuntimeObjectRegistry();
            const FasterBASIC::ObjectTypeDescriptor* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
            
            if (objDesc && objDesc->hasSubscriptOperator) {
                builder_.emitComment(objDesc->typeName + " subscript insert: " + stmt->variable + "(...) = value");
                
                // Get the object pointer
                std::string objectPtr = loadVariable(stmt->variable);
                
                // Evaluate the key expression
                if (stmt->indices.size() != 1) {
                    builder_.emitComment("ERROR: object subscript requires exactly 1 key");
                    return;
                }
                
                std::string keyValue = emitExpressionAs(stmt->indices[0].get(), objDesc->subscriptKeyType.baseType);
                
                // If key is a string descriptor, extract C string pointer
                std::string keyArg = keyValue;
                if (objDesc->subscriptKeyType.baseType == BaseType::STRING) {
                    std::string cStringPtr = builder_.newTemp();
                    builder_.emitCall(cStringPtr, "l", "string_to_utf8", "l " + keyValue);
                    keyArg = cStringPtr;
                }
                
                // Evaluate the value expression
                std::string value = emitExpression(stmt->value.get());
                
                // TODO: Box the value if it's a scalar type
                // For now, assume value is already a pointer (works for strings/arrays)
                std::string boxedValue = value;
                
                // Call the subscript set function from registry
                std::string resultReg = builder_.newTemp();
                builder_.emitCall(resultReg, "w", objDesc->subscriptSetFunction,
                                "l " + objectPtr + ", l " + keyArg + ", l " + boxedValue);
                
                return;
            }
        }
    }
    
    // ── Array element UDT assignment: Arr(i) = <UDT expr> ──
    // Must be handled specially because the generic path would store
    // only a pointer (storel) instead of copying the full UDT data.
    if (!stmt->indices.empty()) {
        const auto& symbolTable = semantic_.getSymbolTable();
        auto arrIt = symbolTable.arrays.find(stmt->variable);
        if (arrIt != symbolTable.arrays.end() &&
            arrIt->second.elementTypeDesc.baseType == BaseType::USER_DEFINED) {

            std::string udtTypeName = arrIt->second.elementTypeDesc.udtName;
            auto udtIt = symbolTable.types.find(udtTypeName);
            if (udtIt != symbolTable.types.end()) {
                const auto& udtDef = udtIt->second;

                // Compute the target array element address
                std::string targetAddr = emitArrayElementAddress(stmt->variable, stmt->indices);

                // Try NEON arithmetic first: Arr(i) = A + B
                if (tryEmitNEONArithmetic(stmt, targetAddr, udtDef, symbolTable.types)) {
                    builder_.emitComment("End NEON UDT array element arithmetic");
                    return;
                }

                // Try scalar UDT arithmetic fallback: Arr(i) = A + B (when NEON disabled)
                if (emitScalarUDTArithmetic(stmt, targetAddr, udtDef, symbolTable.types)) {
                    builder_.emitComment("End scalar UDT array element arithmetic");
                    return;
                }

                // Check if source is also a UDT expression
                BaseType sourceType = getExpressionType(stmt->value.get());
                if (sourceType == BaseType::USER_DEFINED) {
                    std::string sourceAddr;
                    bool sourceOk = true;

                    if (stmt->value->getType() == ASTNodeType::EXPR_VARIABLE) {
                        const auto* varExpr = static_cast<const VariableExpression*>(stmt->value.get());
                        sourceAddr = getVariableAddress(varExpr->name);
                    } else if (stmt->value->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
                        const auto* srcArrExpr = static_cast<const ArrayAccessExpression*>(stmt->value.get());
                        sourceAddr = emitArrayElementAddress(srcArrExpr->name, srcArrExpr->indices);
                    } else if (stmt->value->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
                        sourceAddr = emitMemberAccessExpression(
                            static_cast<const MemberAccessExpression*>(stmt->value.get()));
                    } else {
                        builder_.emitComment("WARNING: Unsupported UDT source for array element, falling through");
                        sourceOk = false;
                    }

                    if (sourceOk) {
                        builder_.emitComment("UDT array element copy: " + stmt->variable + "(...) = <UDT>");
                        emitUDTCopyFieldByField(sourceAddr, targetAddr, udtDef, symbolTable.types);
                        builder_.emitComment("End UDT array element copy");
                        return;
                    }
                }
            }
        }
    }

    // Determine target type based on whether it's an array or scalar
    BaseType targetType;
    
    if (!stmt->indices.empty()) {
        // Array assignment: get element type from array descriptor
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.arrays.find(stmt->variable);
        if (it != symbolTable.arrays.end()) {
            targetType = it->second.elementTypeDesc.baseType;
        } else {
            targetType = BaseType::UNKNOWN;
        }
    } else {
        // Scalar assignment: get variable type
        targetType = getVariableType(stmt->variable);
    }
    
    // Emit the right-hand side expression with type context for smart literal generation
    std::string value = emitExpressionAs(stmt->value.get(), targetType);
    
    // Use variable name as-is - it's already mangled by the parser/semantic analyzer
    // (e.g., "Y#" becomes "Y_DOUBLE" in the symbol table)
    
    // Check if this is an array assignment
    if (!stmt->indices.empty()) {
        // Array assignment: arr(i,j) = value
        storeArrayElement(stmt->variable, stmt->indices, value);
    } else {
        // Regular variable assignment: x = value
        storeVariable(stmt->variable, value);
    }
}

void ASTEmitter::emitPrintStatement(const PrintStatement* stmt) {
    for (const auto& item : stmt->items) {
        if (item.expr) {
            BaseType exprType = getExpressionType(item.expr.get());
            std::string value = emitExpression(item.expr.get());
            
            if (typeManager_.isString(exprType)) {
                runtime_.emitPrintString(value);
            } else if (typeManager_.isFloatingPoint(exprType)) {
                if (exprType == BaseType::SINGLE) {
                    runtime_.emitPrintFloat(value);
                } else {
                    runtime_.emitPrintDouble(value);
                }
            } else {
                runtime_.emitPrintInt(value, exprType);
            }
        }
        
        // Handle separators
        if (item.comma) {
            runtime_.emitPrintTab();
        }
    }
    
    // Add final newline if not suppressed
    if (stmt->trailingNewline) {
        runtime_.emitPrintNewline();
    }
}

void ASTEmitter::emitInputStatement(const InputStatement* stmt) {
    // Invalidate array element cache - INPUT modifies a variable
    clearArrayElementCache();
    // TODO: Handle prompt
    
    for (const auto& varName : stmt->variables) {
        BaseType varType = getVariableType(varName);
        std::string varAddr = getVariableAddress(varName);
        
        if (typeManager_.isString(varType)) {
            runtime_.emitInputString(varAddr);
        } else if (typeManager_.isFloatingPoint(varType)) {
            if (varType == BaseType::SINGLE) {
                runtime_.emitInputFloat(varAddr);
            } else {
                runtime_.emitInputDouble(varAddr);
            }
        } else {
            runtime_.emitInputInt(varAddr);
        }
    }
}

void ASTEmitter::emitEndStatement(const EndStatement* stmt) {
    // END statement - terminate execution.
    // SAMM: Must shut down scope-aware memory management before exiting
    // so that the background cleanup worker is stopped, all pending
    // destructors are called, and diagnostic metrics are printed.
    if (isSAMMEnabled()) {
        builder_.emitComment("SAMM: Shutdown before END");
        builder_.emitCall("", "", "samm_shutdown", "");
    }

    builder_.emitComment("END statement - program exit");
    builder_.emitReturn("0");
}

void ASTEmitter::emitReturnStatement(const ReturnStatement* stmt) {
    // RETURN statement - return from FUNCTION, SUB, or METHOD
    if (stmt->returnValue) {
        // === METHOD return (direct ret) ===
        // If we're inside a METHOD body (methodReturnType_ != VOID), emit a
        // direct QBE `ret <value>` instead of the FUNCTION-style
        // store-to-return-var-and-jump pattern, because methods are standalone
        // QBE functions that use ret directly.
        if (methodReturnType_ != FasterBASIC::BaseType::VOID) {
            std::string value = emitExpressionAs(stmt->returnValue.get(), methodReturnType_);

            // SAMM: If returning a CLASS instance from a METHOD, RETAIN it
            // to the parent scope so it survives the current method scope's
            // cleanup. This is essential for factory methods and methods that
            // create and return new objects.
            if (isSAMMEnabled() && methodReturnType_ == FasterBASIC::BaseType::CLASS_INSTANCE) {
                builder_.emitComment("SAMM: RETAIN returned CLASS instance to parent scope");
                builder_.emitCall("", "", "samm_retain_parent", "l " + value);
            }

            // SAMM: If returning a STRING from a METHOD, RETAIN it to the
            // parent scope so it survives the current method scope's cleanup.
            // String descriptors are now auto-tracked by SAMM in every scope,
            // so without RETAIN the returned string would be released on
            // scope exit before the caller can use it.
            if (isSAMMEnabled() && methodReturnType_ == FasterBASIC::BaseType::STRING) {
                builder_.emitComment("SAMM: RETAIN returned STRING to parent scope");
                builder_.emitCall("", "", "samm_retain_parent", "l " + value);
            }

            // SAMM: Exit METHOD scope before returning. All tracked
            // allocations (except RETAINed ones) are queued for cleanup.
            if (isSAMMEnabled()) {
                builder_.emitComment("SAMM: Exit METHOD scope");
                builder_.emitCall("", "", "samm_exit_scope", "");
            }

            builder_.emitComment("METHOD RETURN");
            builder_.emitReturn(value);
            return;
        }
        
        // === FUNCTION return (store + jump to exit block) ===
        std::string value = emitExpression(stmt->returnValue.get());
        
        // Get current function name
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        if (currentFunc.empty()) {
            builder_.emitComment("ERROR: RETURN outside of function");
            return;
        }
        
        // Look up function to get return type
        const auto& symbolTable = semantic_.getSymbolTable();
        auto funcIt = symbolTable.functions.find(currentFunc);
        if (funcIt == symbolTable.functions.end()) {
            builder_.emitComment("ERROR: Current function not found in symbol table");
            return;
        }
        
        BaseType returnType = funcIt->second.returnTypeDesc.baseType;
        std::string returnVarName = typeManager_.getReturnVariableName(currentFunc, returnType);
        
        // Store the value in the return variable
        storeVariable(returnVarName, value);
        
        builder_.emitComment("RETURN statement - jump to exit");
        // Jump to exit block (block 1 by convention)
        builder_.emitJump("block_1");
    } else {
        // No return value — could be SUB, GOSUB RETURN, or void METHOD RETURN.
        //
        // Methods are emitted via emitMethodBody() (linear statement walk),
        // NOT via CFG, so there is no block_1 exit block to jump to.
        // Detect the method context and emit a direct `ret` with SAMM
        // scope exit instead.
        if (currentClassContext_ != nullptr) {
            // We're inside a METHOD/CONSTRUCTOR body — emit direct return
            if (isSAMMEnabled()) {
                builder_.emitComment("SAMM: Exit METHOD scope (early void RETURN)");
                builder_.emitCall("", "", "samm_exit_scope", "");
            }

            builder_.emitComment("METHOD RETURN (void)");
            builder_.emitReturn();
        } else {
            // SUB or GOSUB RETURN — jump to exit block (handled by CFG)
            builder_.emitComment("RETURN statement (SUB/GOSUB)");
            builder_.emitJump("block_1");
        }
    }
}

void ASTEmitter::emitLocalStatement(const LocalStatement* stmt) {
    // Invalidate array element cache - LOCAL declares/initializes variables
    clearArrayElementCache();
    // LOCAL statement: allocate stack space for local variables in SUBs/FUNCTIONs
    // Similar to DIM but specifically for function-local scope
    
    for (const auto& varDecl : stmt->variables) {
        const std::string& varName = varDecl.name;
        
        builder_.emitComment("LOCAL variable: " + varName);
        
        // Look up variable in symbol table using scoped lookup
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        const auto* varSymbol = semantic_.lookupVariableScoped(varName, currentFunc);
        if (!varSymbol) {
            builder_.emitComment("ERROR: LOCAL variable not found in symbol table: " + varName);
            continue;
        }
        
        // Allocate stack space for the local variable
        std::string mangledName = symbolMapper_.mangleVariableName(varName, false);
        BaseType varType = varSymbol->typeDesc.baseType;
        int64_t size = typeManager_.getTypeSize(varType);
        
        // For UDT types, calculate actual struct size from field definitions
        if (varType == BaseType::USER_DEFINED) {
            const auto& symbolTable = semantic_.getSymbolTable();
            auto udtIt = symbolTable.types.find(varSymbol->typeName);
            if (udtIt != symbolTable.types.end()) {
                size = typeManager_.getUDTSizeRecursive(udtIt->second, symbolTable.types);
            }
        }
        
        // For SIMD-eligible UDTs that use a full Q register (128 bits),
        // use alloc16 to guarantee 16-byte alignment for NEON ldr/str q.
        bool needsAlign16 = false;
        if (varType == BaseType::USER_DEFINED) {
            const auto& symbolTable2 = semantic_.getSymbolTable();
            auto udtIt2 = symbolTable2.types.find(varSymbol->typeName);
            if (udtIt2 != symbolTable2.types.end()) {
                auto simdInfo = typeManager_.getSIMDInfo(udtIt2->second);
                if (simdInfo.isValid() && simdInfo.isFullQ) {
                    needsAlign16 = true;
                }
            }
        }

        if (needsAlign16) {
            // NEON-aligned: pad size to 16 and use alloc16
            int64_t alignedSize = (size + 15) & ~15;
            builder_.emitRaw("    " + mangledName + " =l alloc16 " + std::to_string(alignedSize));
        } else if (size == 4) {
            builder_.emitRaw("    " + mangledName + " =l alloc4 4");
        } else if (size == 8) {
            builder_.emitRaw("    " + mangledName + " =l alloc8 8");
        } else {
            builder_.emitRaw("    " + mangledName + " =l alloc8 " + std::to_string(size));
        }
        
        // Initialize to zero (BASIC variables are implicitly initialized)
        if (typeManager_.isString(varType)) {
            // Strings initialized to null pointer
            builder_.emitRaw("    storel 0, " + mangledName);
        } else if (varType == BaseType::USER_DEFINED && size > 8) {
            // UDT types: zero-initialize all bytes using memset
            builder_.emitComment("Zero-initialize UDT (" + std::to_string(size) + " bytes)");
            builder_.emitCall("", "", "memset",
                            "l " + mangledName + ", w 0, l " + std::to_string(size));
        } else if (size == 4) {
            builder_.emitRaw("    storew 0, " + mangledName);
        } else if (size == 8) {
            builder_.emitRaw("    storel 0, " + mangledName);
        }
    }
}

void ASTEmitter::emitDimStatement(const DimStatement* stmt) {
    // Invalidate array element cache - DIM creates/initializes arrays and variables
    clearArrayElementCache();
    // DIM statement: allocate arrays using runtime array_new() function
    // Note: DIM can also declare scalar variables, which we skip here
    
    for (const auto& arrayDecl : stmt->arrays) {
        const std::string& arrayName = arrayDecl.name;
        
        // Handle scalar variables (those without dimensions)
        if (arrayDecl.dimensions.empty()) {
            builder_.emitComment("DIM scalar variable: " + arrayName);
            
            // Check if this is a CLASS instance variable
            if (arrayDecl.hasAsType) {
                const auto& symbolTable = semantic_.getSymbolTable();
                const FasterBASIC::ClassSymbol* cls = symbolTable.lookupClass(arrayDecl.asTypeName);
                if (cls) {
                    // CLASS instance variable — pointer semantics
                    builder_.emitComment("DIM " + arrayName + " AS " + cls->name + " (CLASS instance)");
                    
                    // === METHOD-local CLASS instance DIM ===
                    // Method bodies don't go through CFGEmitter, so local
                    // variables are NOT pre-allocated.  Allocate a stack slot
                    // here and register it so loadVariable/storeVariable/
                    // getVariableAddress can resolve it.
                    if (currentClassContext_) {
                        std::string varSlot = "%var_" + arrayName;
                        builder_.emitComment("METHOD-local DIM: " + arrayName + " AS " + cls->name);
                        builder_.emitRaw("    " + varSlot + " =l alloc8 8\n");
                        // Zero-initialize (NOTHING)
                        builder_.emitRaw("    storel 0, " + varSlot + "\n");
                        // Register so load/store/getVariableAddress can resolve it
                        registerMethodParam(arrayName, varSlot, FasterBASIC::BaseType::CLASS_INSTANCE);
                        // Store the CLASS name so emitMethodCall can resolve
                        // the correct ClassSymbol for virtual dispatch.
                        methodParamClassNames_[arrayName] = cls->name;
                        
                        // Handle initializer (e.g., = NEW ClassName(...))
                        if (arrayDecl.initializer) {
                            std::string initVal = emitExpression(arrayDecl.initializer.get());
                            builder_.emitRaw("    storel " + initVal + ", " + varSlot + "\n");
                        }
                        continue;
                    }
                    
                    // Get variable address (global / function-local via CFG)
                    std::string varAddr = getVariableAddress(arrayName);
                    
                    // If there's an initializer (e.g., = NEW ClassName(...)), emit it
                    if (arrayDecl.initializer) {
                        std::string initVal = emitExpression(arrayDecl.initializer.get());
                        builder_.emitRaw("    storel " + initVal + ", " + varAddr + "\n");
                    } else {
                        // Default to NOTHING (0)
                        builder_.emitRaw("    storel 0, " + varAddr + "\n");
                    }
                    
                    continue;
                }
            }
            
            // Check if this is an object type variable (HASHMAP, etc.)
            if (arrayDecl.hasAsType) {
                auto& registry = FasterBASIC::getRuntimeObjectRegistry();
                
                // Get the type descriptor from the semantic analyzer to find object type name
                const auto& symbolTable = semantic_.getSymbolTable();
                const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(arrayName);
                
                // Check if it's an object type and get its descriptor
                const FasterBASIC::ObjectTypeDescriptor* objDesc = nullptr;
                if (varSym && registry.isObjectType(varSym->typeDesc)) {
                    objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
                }
                
                if (objDesc && !objDesc->constructorFunction.empty()) {
                    // Initialize object with default constructor
                    builder_.emitComment("DIM " + arrayName + " AS " + objDesc->typeName);
                    
                    // Determine if variable is global or local
                    // OBJECT types (hashmaps, etc.) are always treated as globals to avoid stack issues
                    // Also check for explicit GLOBAL keyword
                    bool isGlobal = varSym->isGlobal || (varSym->typeDesc.baseType == BaseType::OBJECT);
                    
                    // Get variable name (mangle it)
                    std::string varName = symbolMapper_.mangleVariableName(arrayName, isGlobal);
                    
                    // Call constructor with default arguments
                    std::string objectPtr = builder_.newTemp();
                    
                    // Build argument string from default args
                    std::string argsStr;
                    for (const auto& arg : objDesc->constructorDefaultArgs) {
                        if (!argsStr.empty()) argsStr += ", ";
                        argsStr += arg;
                    }
                    
                    builder_.emitCall(objectPtr, "l", objDesc->constructorFunction, argsStr);
                    
                    // Store the object pointer in the variable
                    builder_.emitStore("l", objectPtr, varName);
                    
                    continue;
                }
            }
            
            // === DIM inside METHOD/CONSTRUCTOR/DESTRUCTOR body ===
            // Method bodies don't go through CFGEmitter, so local variables
            // are NOT pre-allocated. We must allocate a stack slot here and
            // register it so loadVariable/storeVariable can find it.
            if (currentClassContext_) {
                // Determine the type from the DIM declaration
                FasterBASIC::BaseType localType = FasterBASIC::BaseType::LONG;
                if (arrayDecl.hasAsType) {
                    std::string upper = arrayDecl.asTypeName;
                    for (auto& c : upper) c = toupper(c);
                    if (upper == "STRING") {
                        localType = FasterBASIC::BaseType::STRING;
                    } else if (upper == "INTEGER" || upper == "INT") {
                        localType = FasterBASIC::BaseType::INTEGER;
                    } else if (upper == "LONG") {
                        localType = FasterBASIC::BaseType::LONG;
                    } else if (upper == "DOUBLE") {
                        localType = FasterBASIC::BaseType::DOUBLE;
                    } else if (upper == "SINGLE") {
                        localType = FasterBASIC::BaseType::SINGLE;
                    }
                } else {
                    // Infer from suffix: name$->STRING, name%->INTEGER, name#->DOUBLE, name!->SINGLE
                    char last = arrayName.empty() ? '\0' : arrayName.back();
                    if (last == '$') localType = FasterBASIC::BaseType::STRING;
                    else if (last == '%') localType = FasterBASIC::BaseType::INTEGER;
                    else if (last == '#') localType = FasterBASIC::BaseType::DOUBLE;
                    else if (last == '!') localType = FasterBASIC::BaseType::SINGLE;
                }
                
                int slotSize = (localType == FasterBASIC::BaseType::INTEGER ||
                                localType == FasterBASIC::BaseType::SINGLE) ? 4 : 8;
                std::string varSlot = "%var_" + arrayName;
                builder_.emitComment("METHOD-local DIM: " + arrayName);
                builder_.emitRaw("    " + varSlot + " =l alloc8 " + std::to_string(slotSize) + "\n");
                
                // Zero-initialize
                if (slotSize == 4) {
                    builder_.emitRaw("    storew 0, " + varSlot + "\n");
                } else {
                    builder_.emitRaw("    storel 0, " + varSlot + "\n");
                }
                
                // Register so load/store/getVariableAddress can resolve it
                registerMethodParam(arrayName, varSlot, localType);
                
                // Handle initializer if present
                if (arrayDecl.initializer) {
                    std::string initVal = emitExpression(arrayDecl.initializer.get());
                    if (localType == FasterBASIC::BaseType::STRING) {
                        builder_.emitRaw("    storel " + initVal + ", " + varSlot + "\n");
                    } else if (localType == FasterBASIC::BaseType::INTEGER) {
                        builder_.emitRaw("    storew " + initVal + ", " + varSlot + "\n");
                    } else if (localType == FasterBASIC::BaseType::SINGLE) {
                        builder_.emitRaw("    stores " + initVal + ", " + varSlot + "\n");
                    } else if (localType == FasterBASIC::BaseType::DOUBLE) {
                        builder_.emitRaw("    stored " + initVal + ", " + varSlot + "\n");
                    } else {
                        builder_.emitRaw("    storel " + initVal + ", " + varSlot + "\n");
                    }
                }
                
                continue;
            }
            
            // NOTE: Local scalar variables are already allocated at function entry
            // in CFGEmitter::emitBlock for block 0. We don't need to allocate them again.
            // DIM for scalars is essentially a no-op in terms of codegen (declaration only).
            
            continue;
        }
        
        // Look up array symbol in semantic analyzer
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.arrays.find(arrayName);
        if (it == symbolTable.arrays.end()) {
            builder_.emitComment("ERROR: array not found in symbol table: " + arrayName);
            continue;
        }
        
        const auto& arraySymbol = it->second;
        BaseType elemType = arraySymbol.elementTypeDesc.baseType;
        
        // Determine if array is global or local
        bool isGlobal = arraySymbol.functionScope.empty();
        
        // Get mangled array descriptor name
        std::string descName = symbolMapper_.getArrayDescriptorName(arrayName);
        if (isGlobal && descName[0] != '$') {
            descName = "$" + descName;
        } else if (!isGlobal && descName[0] != '%') {
            descName = "%" + descName;
        }
        
        builder_.emitComment("DIM " + arrayName + " - call array_new()");
        
        // Check if this is a UDT array
        bool isUDTArray = (elemType == BaseType::USER_DEFINED);
        int64_t elemSize = 0;
        
        // Get type suffix character for runtime (or compute element size for UDTs)
        char typeSuffix;
        if (isUDTArray) {
            // For UDT arrays, we use a special suffix and custom element size
            typeSuffix = 'U';  // Special marker for UDT arrays
            
            // Look up UDT size (with recursive calculation for nested UDTs)
            const auto& udtMap = symbolTable.types;
            auto udtIt = udtMap.find(arraySymbol.elementTypeDesc.udtName);
            if (udtIt != udtMap.end()) {
                elemSize = typeManager_.getUDTSizeRecursive(udtIt->second, udtMap);
            } else {
                builder_.emitComment("ERROR: UDT not found: " + arraySymbol.elementTypeDesc.udtName);
                continue;
            }
        } else {
            typeSuffix = getTypeSuffixChar(elemType);
        }
        
        // Determine number of dimensions
        int numDims = arraySymbol.dimensions.size();
        
        if (numDims < 1 || numDims > 8) {
            builder_.emitComment("ERROR: Invalid array dimensions: " + std::to_string(numDims));
            continue;
        }
        
        // Use the shared bounds buffer (pre-allocated in entry block) so
        // that no alloc instructions are emitted in non-start blocks.
        std::string boundsArrayPtr;
        if (!sharedBoundsBuffer_.empty()) {
            boundsArrayPtr = sharedBoundsBuffer_;
        } else {
            // Fallback: inline alloc (only safe if DIM is in entry block)
            boundsArrayPtr = builder_.newTemp();
            int boundsSize = numDims * 2 * 4;
            builder_.emitAlloc(boundsArrayPtr, boundsSize);
        }
        
        // Fill in bounds array
        for (int i = 0; i < numDims; i++) {
            // Lower bound (always 0 for OPTION BASE 0)
            int64_t lowerBound = 0;
            std::string lowerAddr = builder_.newTemp();
            int lowerOffset = i * 2 * 4;
            builder_.emitBinary(lowerAddr, "l", "add", boundsArrayPtr, std::to_string(lowerOffset));
            builder_.emitStore("w", std::to_string(lowerBound), lowerAddr);
            
            // Upper bound (dimensions[i] - 1)
            int64_t upperBound = arraySymbol.dimensions[i] - 1;
            std::string upperAddr = builder_.newTemp();
            int upperOffset = (i * 2 + 1) * 4;
            builder_.emitBinary(upperAddr, "l", "add", boundsArrayPtr, std::to_string(upperOffset));
            builder_.emitStore("w", std::to_string(upperBound), upperAddr);
        }
        
        // Call array_new(char type_suffix, int32_t dimensions, int32_t* bounds, int32_t base)
        std::string typeSuffixReg = builder_.newTemp();
        builder_.emitInstruction(typeSuffixReg + " =w copy " + std::to_string((int)typeSuffix));
        
        std::string dimsReg = builder_.newTemp();
        builder_.emitInstruction(dimsReg + " =w copy " + std::to_string(numDims));
        
        std::string baseReg = builder_.newTemp();
        builder_.emitInstruction(baseReg + " =w copy 0");  // OPTION BASE 0
        
        std::string arrayPtr = builder_.newTemp();
        
        if (isUDTArray) {
            // For UDT arrays, call array_new_custom with element size
            std::string elemSizeReg = builder_.newTemp();
            builder_.emitInstruction(elemSizeReg + " =l copy " + std::to_string(elemSize));
            
            builder_.emitCall(arrayPtr, "l", "array_new_custom",
                             "l " + elemSizeReg +
                             ", w " + dimsReg +
                             ", l " + boundsArrayPtr +
                             ", w " + baseReg);
        } else {
            // Regular typed arrays
            builder_.emitCall(arrayPtr, "l", "array_new", 
                             "w " + typeSuffixReg + 
                             ", w " + dimsReg + 
                             ", l " + boundsArrayPtr + 
                             ", w " + baseReg);
        }
        
        // Store the BasicArray* pointer in the array variable
        builder_.emitStore("l", arrayPtr, descName);
    }
}

void ASTEmitter::emitRedimStatement(const RedimStatement* stmt) {
    // Invalidate array element cache - REDIM reallocates arrays
    clearArrayElementCache();
    // REDIM statement: resize existing array (with or without PRESERVE)
    
    for (const auto& arrayDecl : stmt->arrays) {
        const std::string& arrayName = arrayDecl.name;
        
        builder_.emitComment("REDIM" + std::string(stmt->preserve ? " PRESERVE " : " ") + arrayName);
        
        // Look up array symbol in semantic analyzer
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.arrays.find(arrayName);
        if (it == symbolTable.arrays.end()) {
            builder_.emitComment("ERROR: array not found in symbol table: " + arrayName);
            continue;
        }
        
        const auto& arraySymbol = it->second;
        
        // Get the array descriptor pointer (the array variable itself)
        std::string descName = symbolMapper_.getArrayDescriptorName(arrayName);
        bool isGlobal = arraySymbol.functionScope.empty();
        if (isGlobal && descName[0] != '$') {
            descName = "$" + descName;
        } else if (!isGlobal && descName[0] != '%') {
            descName = "%" + descName;
        }
        
        // Evaluate dimension expressions to get new bounds
        std::vector<std::string> newBounds;
        for (const auto& dimExpr : arrayDecl.dimensions) {
            std::string upperBound = emitExpressionAs(dimExpr.get(), BaseType::LONG);
            newBounds.push_back(upperBound);
        }
        
        // Allocate bounds array: [lower1, upper1, lower2, upper2, ...]
        int numDims = newBounds.size();
        std::string boundsArraySize = std::to_string(numDims * 2 * 4); // 2 int32_t per dimension
        std::string boundsPtr = builder_.newTemp();
        builder_.emitCall(boundsPtr, "l", "malloc", "l " + boundsArraySize);
        
        // Fill in bounds array
        int32_t lowerBound = 0; // OPTION BASE 0 for now
        for (int i = 0; i < numDims; i++) {
            // Convert upper bound from long to word if needed
            std::string upperBoundWord = builder_.newTemp();
            builder_.emitInstruction(upperBoundWord + " =w copy " + newBounds[i]);
            
            // Store lower bound
            std::string lowerAddr = builder_.newTemp();
            builder_.emitBinary(lowerAddr, "l", "add", boundsPtr, std::to_string(i * 2 * 4));
            builder_.emitStore("w", std::to_string(lowerBound), lowerAddr);
            
            // Store upper bound
            std::string upperAddr = builder_.newTemp();
            builder_.emitBinary(upperAddr, "l", "add", boundsPtr, std::to_string((i * 2 + 1) * 4));
            builder_.emitStore("w", upperBoundWord, upperAddr);
        }
        
        // Load the BasicArray* pointer from the descriptor variable
        std::string arrayPtr = builder_.newTemp();
        builder_.emitLoad(arrayPtr, "l", descName);
        
        // Call array_redim(array, new_bounds, preserve)
        std::string preserveFlag = stmt->preserve ? "1" : "0";
        builder_.emitCall("", "", "array_redim", "l " + arrayPtr + ", l " + boundsPtr + ", w " + preserveFlag);
        
        // Free the temporary bounds array
        builder_.emitCall("", "", "free", "l " + boundsPtr);
        
        builder_.emitBlankLine();
    }
}

void ASTEmitter::emitEraseStatement(const EraseStatement* stmt) {
    // Invalidate array element cache - ERASE destroys arrays
    clearArrayElementCache();
    // ERASE statement: deallocate array memory
    
    for (const std::string& arrayName : stmt->arrayNames) {
        builder_.emitComment("ERASE " + arrayName);
        
        // Look up array symbol in semantic analyzer
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.arrays.find(arrayName);
        if (it == symbolTable.arrays.end()) {
            builder_.emitComment("ERROR: array not found in symbol table: " + arrayName);
            continue;
        }
        
        const auto& arraySymbol = it->second;
        
        // Get the array descriptor pointer
        std::string descName = symbolMapper_.getArrayDescriptorName(arrayName);
        bool isGlobal = arraySymbol.functionScope.empty();
        if (isGlobal && descName[0] != '$') {
            descName = "$" + descName;
        } else if (!isGlobal && descName[0] != '%') {
            descName = "%" + descName;
        }
        
        // Load the BasicArray* pointer from the descriptor variable
        std::string arrayPtr = builder_.newTemp();
        builder_.emitLoad(arrayPtr, "l", descName);
        
        // Call array_erase(array)
        builder_.emitCall("", "", "array_erase", "l " + arrayPtr);
        
        builder_.emitBlankLine();
    }
}

void ASTEmitter::emitCallStatement(const CallStatement* stmt) {
    // Invalidate array element cache - SUB calls may modify anything
    clearArrayElementCache();
    // Check if this is a method call statement (e.g., dict.CLEAR())
    if (stmt->subName == "__method_call" && stmt->methodCallExpr) {
        // Emit the method call expression and discard the result
        emitExpression(stmt->methodCallExpr.get());
        return;
    }
    
    // Check for plugin commands first
    std::string upperName = stmt->subName;
    std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
    
    auto& cmdRegistry = FasterBASIC::ModularCommands::getGlobalCommandRegistry();
    const auto* pluginCmd = cmdRegistry.getCommand(upperName);
    
    if (pluginCmd && pluginCmd->functionPtr != nullptr) {
        // Plugin command found - emit native call via runtime context
        builder_.emitComment("Plugin command call: " + upperName);
        
        // Allocate runtime context
        std::string ctxPtr = builder_.newTemp();
        builder_.emitCall(ctxPtr, "l", "fb_context_create", "");
        
        // Marshal arguments into context
        for (size_t i = 0; i < stmt->arguments.size() && i < pluginCmd->parameters.size(); ++i) {
            std::string argTemp = emitExpression(stmt->arguments[i].get());
            BaseType argType = getExpressionType(stmt->arguments[i].get());
            
            const auto& param = pluginCmd->parameters[i];
            
            // Add parameter to context based on type
            switch (param.type) {
                case FasterBASIC::ModularCommands::ParameterType::INT:
                case FasterBASIC::ModularCommands::ParameterType::BOOL: {
                    // Convert to int32 if needed
                    if (typeManager_.isFloatingPoint(argType)) {
                        std::string intTemp = builder_.newTemp();
                        std::string qbeType = typeManager_.getQBEType(argType);
                        builder_.emitRaw("    " + intTemp + " =w " + qbeType + "tosi " + argTemp);
                        argTemp = intTemp;
                    } else if (typeManager_.getQBEType(argType) == "l") {
                        // Truncate long to int
                        std::string intTemp = builder_.newTemp();
                        builder_.emitRaw("    " + intTemp + " =w copy " + argTemp);
                        argTemp = intTemp;
                    }
                    builder_.emitCall("", "", "fb_context_add_int_param", "l " + ctxPtr + ", w " + argTemp);
                    break;
                }
                case FasterBASIC::ModularCommands::ParameterType::FLOAT: {
                    // Convert to float if needed
                    if (typeManager_.isIntegral(argType)) {
                        argTemp = emitTypeConversion(argTemp, argType, BaseType::SINGLE);
                    } else if (argType == BaseType::DOUBLE) {
                        std::string floatTemp = builder_.newTemp();
                        builder_.emitRaw("    " + floatTemp + " =s dtof " + argTemp);
                        argTemp = floatTemp;
                    }
                    builder_.emitCall("", "", "fb_context_add_float_param", "l " + ctxPtr + ", s " + argTemp);
                    break;
                }
                case FasterBASIC::ModularCommands::ParameterType::STRING: {
                    // String argument - pass descriptor pointer
                    if (argType != BaseType::STRING) {
                        // Convert non-string to string
                        argTemp = emitTypeConversion(argTemp, argType, BaseType::STRING);
                    }
                    builder_.emitCall("", "", "fb_context_add_string_param", "l " + ctxPtr + ", l " + argTemp);
                    break;
                }
                default:
                    builder_.emitComment("WARNING: Unsupported plugin parameter type");
                    break;
            }
        }
        
        // Get function pointer and call it
        std::string funcPtrTemp = builder_.newTemp();
        // Cast the function pointer to long (pointer)
        std::stringstream funcPtrStr;
        funcPtrStr << reinterpret_cast<intptr_t>(pluginCmd->functionPtr);
        builder_.emitRaw("    " + funcPtrTemp + " =l copy " + funcPtrStr.str());
        
        // Call the plugin function via indirect call
        // The function signature is: void (*)(FB_RuntimeContext*)
        builder_.emitRaw("    call " + funcPtrTemp + "(l " + ctxPtr + ")");
        
        // Check for errors
        std::string hasError = builder_.newTemp();
        builder_.emitCall(hasError, "w", "fb_context_has_error", "l " + ctxPtr);
        
        std::string errorCheckLabel = "plugin_err_" + std::to_string(builder_.getTempCounter());
        std::string noErrorLabel = "plugin_ok_" + std::to_string(builder_.getTempCounter());
        
        builder_.emitRaw("    jnz " + hasError + ", @" + errorCheckLabel + ", @" + noErrorLabel);
        builder_.emitLabel(errorCheckLabel);
        
        // Get error message and print it
        std::string errorMsg = builder_.newTemp();
        builder_.emitCall(errorMsg, "l", "fb_context_get_error", "l " + ctxPtr);
        runtime_.emitPrintString(errorMsg);
        runtime_.emitPrintNewline();
        
        // Call END to terminate program on error
        builder_.emitCall("", "", "basic_end", "w 1");
        
        builder_.emitLabel(noErrorLabel);
        
        // Destroy context (frees temporary allocations)
        builder_.emitCall("", "", "fb_context_destroy", "l " + ctxPtr);
        
        return;
    }
    
    // Get the mangled SUB name
    std::string mangledName = symbolMapper_.mangleSubName(stmt->subName);
    
    // Evaluate all arguments
    std::vector<std::string> argTemps;
    std::vector<BaseType> argTypes;
    
    for (const auto& arg : stmt->arguments) {
        BaseType argType = getExpressionType(arg.get());
        std::string argTemp = emitExpression(arg.get());
        argTemps.push_back(argTemp);
        argTypes.push_back(argType);
    }
    
    // Build argument list string for QBE call
    std::string args;
    for (size_t i = 0; i < argTemps.size(); ++i) {
        if (i > 0) args += ", ";
        std::string qbeType = typeManager_.getQBEType(argTypes[i]);
        args += qbeType + " " + argTemps[i];
    }
    
    // Strip leading $ from mangled name since emitCall adds it
    std::string callName = mangledName;
    if (!callName.empty() && callName[0] == '$') {
        callName = callName.substr(1);
    }
    
    // Emit the call (SUBs return void, so no destination)
    builder_.emitCall("", "", callName, args);
}

// === Variable Access ===

// Helper to normalize FOR loop variable names
// If varName references a FOR loop variable (by base name), returns the normalized name
// with the correct integer suffix. Otherwise returns varName unchanged.
std::string ASTEmitter::normalizeForLoopVarName(const std::string& varName) const {
    if (varName.empty()) return varName;
    
    // Strip any existing suffix to get base name (handle both character and text suffixes)
    std::string baseName = varName;
    
    // Check for text suffixes first (from parser mangling)
    if (baseName.length() > 4 && baseName.substr(baseName.length() - 4) == "_INT") {
        baseName = baseName.substr(0, baseName.length() - 4);
    } else if (baseName.length() > 5 && baseName.substr(baseName.length() - 5) == "_LONG") {
        baseName = baseName.substr(0, baseName.length() - 5);
    } else if (baseName.length() > 7 && baseName.substr(baseName.length() - 7) == "_STRING") {
        baseName = baseName.substr(0, baseName.length() - 7);
    } else if (baseName.length() > 7 && baseName.substr(baseName.length() - 7) == "_DOUBLE") {
        baseName = baseName.substr(0, baseName.length() - 7);
    } else if (baseName.length() > 6 && baseName.substr(baseName.length() - 6) == "_FLOAT") {
        baseName = baseName.substr(0, baseName.length() - 6);
    } else if (baseName.length() > 5 && baseName.substr(baseName.length() - 5) == "_BYTE") {
        baseName = baseName.substr(0, baseName.length() - 5);
    } else if (baseName.length() > 6 && baseName.substr(baseName.length() - 6) == "_SHORT") {
        baseName = baseName.substr(0, baseName.length() - 6);
    } else {
        // Check for character suffixes (if not already converted by parser)
        char lastChar = baseName.back();
        if (lastChar == '%' || lastChar == '&' || lastChar == '!' || 
            lastChar == '#' || lastChar == '$' || lastChar == '@' || lastChar == '^') {
            baseName = baseName.substr(0, baseName.length() - 1);
        }
    }
    
    // Check if this base name is a FOR loop variable
    if (semantic_.isForLoopVariable(baseName)) {
        // This is a FOR loop variable - return base name with correct integer suffix
        // The suffix is determined by OPTION FOR setting
        // Use text suffix format (_INT or _LONG) to match parser mangling
        std::string intSuffix = semantic_.getForLoopIntegerSuffix();
        std::string result = baseName + intSuffix;
        return result;
    }
    
    // Not a FOR loop variable - return original name unchanged
    return varName;
}

std::string ASTEmitter::stripTextTypeSuffix(const std::string& name) {
    if (name.empty()) return name;
    // Check for text suffixes appended by parser mangling
    struct { const char* suffix; size_t len; } suffixes[] = {
        {"_STRING", 7}, {"_DOUBLE", 7}, {"_FLOAT", 6},
        {"_SHORT", 6}, {"_LONG", 5}, {"_BYTE", 5}, {"_INT", 4}
    };
    for (const auto& s : suffixes) {
        if (name.length() > s.len &&
            name.compare(name.length() - s.len, s.len, s.suffix) == 0) {
            return name.substr(0, name.length() - s.len);
        }
    }
    return name;
}

std::string ASTEmitter::normalizeVariableName(const std::string& varName) const {
    // First check if it's a FOR loop variable
    std::string forNormalized = normalizeForLoopVarName(varName);
    if (forNormalized != varName) {
        return forNormalized;
    }
    
    // Check if this is a FOR EACH iteration variable (not in symbol table by design)
    if (forEachVarTypes_.count(varName) > 0) {
        return varName;  // Return raw name — loadVariable/storeVariable handle the rest
    }
    
    // --- METHOD/CONSTRUCTOR local-variable & parameter check ---
    // Variables registered via registerMethodParam() (method parameters,
    // DIM'd locals inside METHOD bodies, FOR loop vars, and the method
    // return-value slot) are NOT in the semantic symbol table.
    // Check our local parameter map BEFORE falling through to the symbol
    // table, using both the raw name and the suffix-stripped base name.
    if (!methodParamAddresses_.empty()) {
        // Try raw name first (e.g. "acc", "m", "last")
        if (methodParamAddresses_.count(varName) > 0) {
            return varName;
        }
        // Try suffix-stripped base name (e.g. "m_INT" -> "m", "acc_DOUBLE" -> "acc")
        std::string baseName = stripTextTypeSuffix(varName);
        if (baseName != varName && methodParamAddresses_.count(baseName) > 0) {
            return baseName;
        }
    }
    
    // Not a FOR loop variable - check if name already has a suffix
    // If it does, the parser already mangled it, so return as-is
    if (varName.find("_INT") != std::string::npos ||
        varName.find("_DOUBLE") != std::string::npos ||
        varName.find("_FLOAT") != std::string::npos ||
        varName.find("_STRING") != std::string::npos ||
        varName.find("_LONG") != std::string::npos ||
        varName.find("_BYTE") != std::string::npos ||
        varName.find("_SHORT") != std::string::npos) {
        return varName;
    }
    
    // No suffix - check if variable exists in symbol table with any suffix
    std::string currentFunc = symbolMapper_.getCurrentFunction();
    const auto& symbolTable = semantic_.getSymbolTable();
    
    // First try the variable name without any suffix (for OBJECT and user-defined types)
    const auto* varSymbolUnsuffixed = semantic_.lookupVariableScoped(varName, currentFunc);
    if (varSymbolUnsuffixed) {
        return varName;
    }
    
    // Try all possible suffixes to see if the variable already exists
    std::vector<std::string> suffixes = {"_INT", "_LONG", "_SHORT", "_BYTE", "_DOUBLE", "_FLOAT", "_STRING"};
    for (const auto& suffix : suffixes) {
        std::string candidate = varName + suffix;
        const auto* varSymbol = semantic_.lookupVariableScoped(candidate, currentFunc);
        if (varSymbol) {
            return candidate;
        }
    }
    
    // Variable doesn't exist in symbol table - this is an error!
    // Codegen should never create variables; they must all be declared by semantic analyzer
    builder_.emitComment("ERROR: Variable '" + varName + "' not found in symbol table");
    return varName + "_UNKNOWN";  // Return something to avoid crashes, but this is an error
}

std::string ASTEmitter::getVariableAddress(const std::string& varName) {
    // Normalize variable name using semantic analyzer's type inference
    std::string lookupName = normalizeVariableName(varName);
    
    // --- METHOD/CONSTRUCTOR parameter fallback ---
    // Parameters registered via registerMethodParam() are not in the semantic
    // symbol table.  Check our local parameter map first.
    {
        auto mpIt = methodParamAddresses_.find(varName);
        if (mpIt != methodParamAddresses_.end()) {
            return mpIt->second;
        }
        // Also try the normalized name
        if (varName != lookupName) {
            mpIt = methodParamAddresses_.find(lookupName);
            if (mpIt != methodParamAddresses_.end()) {
                return mpIt->second;
            }
        }
    }
    
    // --- FOR EACH variable fallback ---
    // FOR EACH iteration variables are not in the symbol table.  Their stack
    // slot addresses are registered in globalVarAddresses_ during init/preamble.
    if (forEachVarTypes_.count(lookupName) > 0) {
        auto git = globalVarAddresses_.find(lookupName);
        if (git != globalVarAddresses_.end()) {
            return git->second;
        }
        builder_.emitComment("ERROR: FOR EACH variable address not yet allocated: " + lookupName);
        return builder_.newTemp();
    }
    
    // Look up variable with scoped lookup
    std::string currentFunc = symbolMapper_.getCurrentFunction();
    
    const auto* varSymbolPtr = semantic_.lookupVariableScoped(lookupName, currentFunc);
    
    if (!varSymbolPtr) {
        builder_.emitComment("ERROR: variable not found: " + varName + " (normalized: " + lookupName + ")");
        return builder_.newTemp();
    }
    const auto& varSymbol = *varSymbolPtr;
    
    // Check if we're in a function and the variable is SHARED
    bool isShared = symbolMapper_.isSharedVariable(lookupName);
    bool isParameter = symbolMapper_.isParameter(lookupName);
    // OBJECT types (hashmaps, etc.) are always treated as globals to avoid stack issues
    bool isObjectType = (varSymbol.typeDesc.baseType == BaseType::OBJECT);
    // UDT types in main/global scope are treated as globals (they're allocated as data sections)
    // Function-local UDTs are stack-allocated and should NOT be treated as globals
    bool isUDTType = (varSymbol.typeDesc.baseType == BaseType::USER_DEFINED && varSymbol.scope.isGlobal());
    bool treatAsGlobal = (varSymbol.isGlobal || isShared || isParameter || isObjectType || isUDTType);
    
    // Mangle the variable name properly (strips type suffixes, sanitizes, etc.)
    // Use lookupName (with suffix stripped for FOR loop vars)
    std::string mangledName = symbolMapper_.mangleVariableName(lookupName, treatAsGlobal);
    
    // For UDT parameters passed by reference, the stack slot contains a POINTER
    // to the actual struct. We need to load that pointer to get the real address.
    if (varSymbol.typeDesc.baseType == BaseType::USER_DEFINED &&
        symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(lookupName) &&
        !isShared) {
        builder_.emitComment("Deref UDT parameter pointer: " + lookupName);
        std::string ptrTemp = builder_.newTemp();
        builder_.emitLoad(ptrTemp, "l", mangledName);
        return ptrTemp;
    }
    
    if (treatAsGlobal) {
        // Cache the address
        if (globalVarAddresses_.find(mangledName) == globalVarAddresses_.end()) {
            globalVarAddresses_[mangledName] = mangledName;
        }
        
        return mangledName;
    } else {
        // Local variable
        return mangledName;
    }
}

std::string ASTEmitter::loadVariable(const std::string& varName) {
    // Normalize variable name using semantic analyzer's type inference
    std::string lookupName = normalizeVariableName(varName);
    
    // --- METHOD/CONSTRUCTOR parameter fallback ---
    // Parameters registered via registerMethodParam() are not in the semantic
    // symbol table.  Check our local parameter map first.
    {
        auto mpIt = methodParamAddresses_.find(varName);
        std::string mpKey = varName;
        if (mpIt == methodParamAddresses_.end() && varName != lookupName) {
            mpIt = methodParamAddresses_.find(lookupName);
            mpKey = lookupName;
        }
        if (mpIt != methodParamAddresses_.end()) {
            std::string addr = mpIt->second;
            BaseType mpType = BaseType::LONG;  // default: pointer
            auto typeIt = methodParamTypes_.find(mpKey);
            if (typeIt != methodParamTypes_.end()) {
                mpType = typeIt->second;
            }
            std::string qbeT = typeManager_.getQBEType(mpType);
            std::string loadOp;
            if (qbeT == "w")      loadOp = "loadw";
            else if (qbeT == "l") loadOp = "loadl";
            else if (qbeT == "s") loadOp = "loads";
            else if (qbeT == "d") loadOp = "loadd";
            else                  loadOp = "loadl";
            std::string result = builder_.newTemp();
            builder_.emitRaw("    " + result + " =" + qbeT + " " + loadOp + " " + addr + "\n");
            return result;
        }
    }
    
    // --- FOR EACH variable fallback ---
    // FOR EACH iteration variables are not in the symbol table.  Their slot
    // addresses and types are tracked by the emitter itself.
    {
        auto feIt = forEachVarTypes_.find(lookupName);
        if (feIt != forEachVarTypes_.end()) {
            std::string addr = getVariableAddress(lookupName);
            BaseType feType = feIt->second;
            std::string qbeT = typeManager_.getQBEType(feType);
            std::string loadOp;
            if (qbeT == "w")      loadOp = "loadw";
            else if (qbeT == "l") loadOp = "loadl";
            else if (qbeT == "s") loadOp = "loads";
            else if (qbeT == "d") loadOp = "loadd";
            else                  loadOp = "loadl";
            std::string result = builder_.newTemp();
            builder_.emitRaw("    " + result + " =" + qbeT + " " + loadOp + " " + addr);
            return result;
        }
    }
    
    // Look up variable with scoped lookup
    std::string currentFunc = symbolMapper_.getCurrentFunction();
    
    const auto* varSymbolPtr = semantic_.lookupVariableScoped(lookupName, currentFunc);
    
    if (!varSymbolPtr) {
        builder_.emitComment("ERROR: variable not found: " + varName + " (normalized: " + lookupName + ")");
        return builder_.newTemp();
    }
    const auto& varSymbol = *varSymbolPtr;
    
    // Check if this is a function parameter FIRST - parameters are passed as QBE temporaries
    // and don't need to be loaded from memory
    if (symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(lookupName)) {
        // Parameter - return the parameter temporary directly (e.g., %a_INT)
        builder_.emitComment("Loading parameter: " + lookupName);
        return "%" + lookupName;
    }
    
    BaseType varType = getVariableType(lookupName);
    std::string qbeType = typeManager_.getQBEType(varType);
    
    // UDT types are value types stored inline at the variable's address.
    // "Loading" a UDT means getting its address (pointer), not reading from it.
    // The address IS the value we pass around – member access and assignment
    // functions all work with addresses.
    if (varType == BaseType::USER_DEFINED) {
        std::string addr = getVariableAddress(lookupName);
        builder_.emitComment("UDT variable address (pass-by-ref): " + lookupName);
        return addr;
    }
    
    // Check if we're in a function and the variable is SHARED
    bool treatAsGlobal = varSymbol.isGlobal || 
                         (symbolMapper_.inFunctionScope() && symbolMapper_.isSharedVariable(lookupName));
    
    // All variables (global and local) are stored in memory and must be loaded
    std::string addr = getVariableAddress(lookupName);
    std::string result = builder_.newTemp();
    
    if (treatAsGlobal) {
        // Global variable - load from global memory
        builder_.emitLoad(result, qbeType, addr);
    } else {
        // Local variable - load from stack allocation
        builder_.emitLoad(result, qbeType, addr);
    }
    
    return result;
}

void ASTEmitter::storeVariable(const std::string& varName, const std::string& value) {
    // Normalize variable name using semantic analyzer's type inference
    std::string lookupName = normalizeVariableName(varName);
    
    // --- METHOD/CONSTRUCTOR local-variable & return-slot fallback ---
    // Variables registered via registerMethodParam() (method parameters,
    // DIM'd locals inside METHOD bodies, and the method return-value slot)
    // are NOT in the semantic symbol table.  Check our local map first,
    // mirroring the fallback in loadVariable / getVariableAddress.
    {
        auto mpIt = methodParamAddresses_.find(varName);
        std::string mpKey = varName;
        if (mpIt == methodParamAddresses_.end() && varName != lookupName) {
            mpIt = methodParamAddresses_.find(lookupName);
            mpKey = lookupName;
        }
        if (mpIt != methodParamAddresses_.end()) {
            std::string addr = mpIt->second;
            BaseType mpType = BaseType::LONG;  // default
            auto typeIt = methodParamTypes_.find(mpKey);
            if (typeIt != methodParamTypes_.end()) {
                mpType = typeIt->second;
            }

            // STRING assignment with reference counting
            if (typeManager_.isString(mpType)) {
                builder_.emitComment("Method-local string assignment: " + varName);
                std::string oldPtr = builder_.newTemp();
                builder_.emitRaw("    " + oldPtr + " =l loadl " + addr + "\n");
                std::string retainedPtr = builder_.newTemp();
                builder_.emitCall(retainedPtr, "l", "string_retain", "l " + value);
                builder_.emitRaw("    storel " + retainedPtr + ", " + addr + "\n");
                builder_.emitCall("", "", "string_release", "l " + oldPtr);
            } else {
                std::string qbeT = typeManager_.getQBEType(mpType);
                std::string storeOp;
                if (qbeT == "w")      storeOp = "storew";
                else if (qbeT == "s") storeOp = "stores";
                else if (qbeT == "d") storeOp = "stored";
                else                  storeOp = "storel";
                builder_.emitRaw("    " + storeOp + " " + value + ", " + addr + "\n");
            }
            return;
        }
    }

    // --- FOR EACH variable fallback ---
    {
        auto feIt = forEachVarTypes_.find(lookupName);
        if (feIt != forEachVarTypes_.end()) {
            std::string addr = getVariableAddress(lookupName);
            BaseType feType = feIt->second;
            std::string qbeT = typeManager_.getQBEType(feType);
            builder_.emitStore(qbeT, value, addr);
            return;
        }
    }
    
    BaseType varType = getVariableType(lookupName);
    std::string qbeType = typeManager_.getQBEType(varType);
    
    // Check if this is a function parameter
    // In BASIC, parameters can be modified (pass-by-reference semantics)
    if (symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(lookupName)) {
        // Parameter - need to allocate stack space and copy parameter value there
        // Then update all references to use the stack location
        // For now, we'll treat parameters as modifiable temporaries
        builder_.emitComment("WARNING: Modifying parameter " + lookupName + " (using copy assignment)");
        builder_.emitRaw("    %" + varName + " =" + qbeType + " copy " + value);
        return;
    }
    
    // Look up variable with scoped lookup
    std::string currentFunc = symbolMapper_.getCurrentFunction();
    const auto* varSymbolPtr = semantic_.lookupVariableScoped(lookupName, currentFunc);
    if (!varSymbolPtr) {
        builder_.emitComment("ERROR: variable not found: " + varName + " (normalized: " + lookupName + ")");
        return;
    }
    const auto& varSymbol = *varSymbolPtr;
    
    // Check if we're in a function and the variable is SHARED
    bool treatAsGlobal = varSymbol.isGlobal || 
                         (symbolMapper_.inFunctionScope() && symbolMapper_.isSharedVariable(lookupName));
    
    // All variables (global and local) are stored in memory
    std::string addr = getVariableAddress(lookupName);
    
    // *** STRING ASSIGNMENT WITH REFERENCE COUNTING ***
    // Strings require special handling to prevent memory leaks and ensure
    // proper reference counting semantics
    if (typeManager_.isString(varType)) {
        builder_.emitComment("String assignment: " + varName + " = <value>");
        
        // 1. Load old string pointer from variable
        std::string oldPtr = builder_.newTemp();
        builder_.emitLoad(oldPtr, "l", addr);
        
        // 2. Retain new string (increments refcount)
        //    This shares ownership - the variable now references the same descriptor
        std::string retainedPtr = builder_.newTemp();
        builder_.emitCall(retainedPtr, "l", "string_retain", "l " + value);
        
        // 3. Store new pointer to variable
        builder_.emitStore("l", retainedPtr, addr);
        
        // 4. Release old string (decrements refcount, frees if 0)
        //    Done AFTER storing new value to handle self-assignment correctly
        //    string_release handles NULL pointers gracefully
        builder_.emitCall("", "", "string_release", "l " + oldPtr);
        
        builder_.emitComment("End string assignment");
    } else {
        // Non-string types: regular store (no reference counting needed)
        if (treatAsGlobal) {
            // Global variable - store to global memory
            builder_.emitStore(qbeType, value, addr);
        } else {
            // Local variable - store to stack allocation
            builder_.emitStore(qbeType, value, addr);
        }
    }
}

// === Array Access ===

std::string ASTEmitter::emitArrayAccess(const std::string& arrayName,
                                        const std::vector<ExpressionPtr>& indices) {
    // Look up array symbol
    const auto& symbolTable = semantic_.getSymbolTable();
    auto it = symbolTable.arrays.find(arrayName);
    if (it == symbolTable.arrays.end()) {
        builder_.emitComment("ERROR: array not found: " + arrayName);
        return builder_.newTemp();
    }
    
    const auto& arraySymbol = it->second;
    
    // Get array descriptor pointer (now a BasicArray*)
    bool isGlobal = arraySymbol.functionScope.empty();
    std::string descName = symbolMapper_.getArrayDescriptorName(arrayName);
    if (isGlobal && descName[0] != '$') {
        descName = "$" + descName;
    } else if (!isGlobal && descName[0] != '%') {
        descName = "%" + descName;
    }
    
    int numIndices = indices.size();
    builder_.emitComment("Array access: " + arrayName + " (using array_get_address)");
    
    // Load the BasicArray* pointer
    std::string arrayPtr = builder_.newTemp();
    builder_.emitLoad(arrayPtr, "l", descName);
    
    // Use the shared indices buffer (pre-allocated in entry block) so
    // that no alloc instructions are emitted in non-start blocks.
    std::string indicesArrayPtr;
    if (!sharedIndicesBuffer_.empty()) {
        indicesArrayPtr = sharedIndicesBuffer_;
    } else {
        // Fallback: inline alloc (only safe if this block is the entry block)
        indicesArrayPtr = builder_.newTemp();
        int indicesSize = numIndices * 4;
        builder_.emitAlloc(indicesArrayPtr, indicesSize);
    }
    
    // Store each index into the indices array
    for (int i = 0; i < numIndices; i++) {
        // Evaluate index expression
        std::string indexReg = emitExpression(indices[i].get());
        
        // Convert index to int32_t (word) if needed
        std::string indexWord = builder_.newTemp();
        std::string indexType = typeManager_.getQBEType(getExpressionType(indices[i].get()));
        if (indexType == "l") {
            // Truncate long to int
            builder_.emitInstruction(indexWord + " =w copy " + indexReg);
        } else {
            builder_.emitInstruction(indexWord + " =w copy " + indexReg);
        }
        
        // Store into indices array at offset i*4
        std::string indexAddr = builder_.newTemp();
        int offset = i * 4;
        if (offset == 0) {
            builder_.emitInstruction(indexAddr + " =l copy " + indicesArrayPtr);
        } else {
            builder_.emitBinary(indexAddr, "l", "add", indicesArrayPtr, std::to_string(offset));
        }
        builder_.emitStore("w", indexWord, indexAddr);
    }
    
    // Call array_get_address(BasicArray* array, int32_t* indices)
    std::string elementPtr = builder_.newTemp();
    builder_.emitCall(elementPtr, "l", "array_get_address", 
                     "l " + arrayPtr + ", l " + indicesArrayPtr);
    
    return elementPtr;
}

std::string ASTEmitter::loadArrayElement(const std::string& arrayName,
                                         const std::vector<ExpressionPtr>& indices) {
    // Check if this is an object subscript lookup: obj(key)
    const auto& symbolTable = semantic_.getSymbolTable();
    const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(arrayName);
    
    // Check if the variable is an object type with subscript operator
    if (varSym) {
        auto& registry = FasterBASIC::getRuntimeObjectRegistry();
        if (registry.isObjectType(varSym->typeDesc)) {
            const FasterBASIC::ObjectTypeDescriptor* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
            
            if (objDesc && objDesc->hasSubscriptOperator) {
                // This is object subscript lookup: obj(key)
                builder_.emitComment(objDesc->typeName + " subscript lookup: " + arrayName + "(...)");
                
                // Get the object pointer
                std::string objectPtr = loadVariable(arrayName);
                
                // Evaluate the key expression
                if (indices.size() != 1) {
                    builder_.emitComment("ERROR: object subscript requires exactly 1 key");
                    return builder_.newTemp();
                }
                
                std::string keyValue = emitExpressionAs(indices[0].get(), objDesc->subscriptKeyType.baseType);
                
                // If key is a string descriptor, extract C string pointer
                std::string keyArg = keyValue;
                if (objDesc->subscriptKeyType.baseType == BaseType::STRING) {
                    std::string cStringPtr = builder_.newTemp();
                    builder_.emitCall(cStringPtr, "l", "string_to_utf8", "l " + keyValue);
                    keyArg = cStringPtr;
                }
                
                // Call the subscript get function from registry
                std::string resultPtr = builder_.newTemp();
                builder_.emitCall(resultPtr, "l", objDesc->subscriptGetFunction,
                                "l " + objectPtr + ", l " + keyArg);
                
                // For now, return the pointer directly
                // TODO: Implement proper unboxing for different value types
                return resultPtr;
            }
        }
    }
    
    // Normal array access
    std::string elemAddr = emitArrayAccess(arrayName, indices);
    
    // Get array element type
    auto it = symbolTable.arrays.find(arrayName);
    if (it == symbolTable.arrays.end()) {
        builder_.emitComment("ERROR: array not found: " + arrayName);
        return builder_.newTemp();
    }
    const auto& arraySymbol = it->second;
    
    BaseType elemType = arraySymbol.elementTypeDesc.baseType;
    std::string qbeType = typeManager_.getQBEType(elemType);
    
    std::string result = builder_.newTemp();
    builder_.emitLoad(result, qbeType, elemAddr);
    
    return result;
}

void ASTEmitter::storeArrayElement(const std::string& arrayName,
                                   const std::vector<ExpressionPtr>& indices,
                                   const std::string& value) {
    // Check if this is an object subscript assignment: obj(key) = value
    const auto& symbolTable = semantic_.getSymbolTable();
    const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(arrayName);
    
    // Check if the variable is an object type with subscript operator
    if (varSym) {
        auto& registry = FasterBASIC::getRuntimeObjectRegistry();
        if (registry.isObjectType(varSym->typeDesc)) {
            const FasterBASIC::ObjectTypeDescriptor* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
            
            if (objDesc && objDesc->hasSubscriptOperator) {
                // This is object subscript assignment: obj(key) = value
                builder_.emitComment(objDesc->typeName + " subscript assignment: " + arrayName + "(...) = ...");
                
                // Get the object pointer
                std::string objectPtr = loadVariable(arrayName);
                
                // Evaluate the key expression
                if (indices.size() != 1) {
                    builder_.emitComment("ERROR: object subscript requires exactly 1 key");
                    return;
                }
                
                std::string keyValue = emitExpressionAs(indices[0].get(), objDesc->subscriptKeyType.baseType);
                
                // If key is a string descriptor, extract C string pointer
                std::string keyArg = keyValue;
                if (objDesc->subscriptKeyType.baseType == BaseType::STRING) {
                    std::string cStringPtr = builder_.newTemp();
                    builder_.emitCall(cStringPtr, "l", "string_to_utf8", "l " + keyValue);
                    keyArg = cStringPtr;
                }
                
                // For now, we'll pass the value directly as a long (pointer or integer)
                // TODO: Implement proper boxing for different value types
                std::string valueQBEType = "l"; // Assume pointer for now
                builder_.emitCall("", "l", objDesc->subscriptSetFunction,
                                "l " + objectPtr + ", l " + keyArg + ", " + valueQBEType + " " + value);
                
                return;
            }
        }
    }
    
    // Normal array access
    std::string elemAddr = emitArrayAccess(arrayName, indices);
    
    // Get array element type
    auto it = symbolTable.arrays.find(arrayName);
    if (it == symbolTable.arrays.end()) {
        builder_.emitComment("ERROR: array not found: " + arrayName);
        return;
    }
    const auto& arraySymbol = it->second;
    
    BaseType elemType = arraySymbol.elementTypeDesc.baseType;
    std::string qbeType = typeManager_.getQBEType(elemType);
    
    builder_.emitStore(qbeType, value, elemAddr);
}

// === Type Inference ===

BaseType ASTEmitter::getExpressionType(const Expression* expr) {
    if (!expr) {
        return BaseType::UNKNOWN;
    }
    
    switch (expr->getType()) {
        case ASTNodeType::EXPR_NUMBER: {
            const auto* numExpr = static_cast<const NumberExpression*>(expr);
            // Check if it's an integer value (no fractional part)
            if (numExpr->value == std::floor(numExpr->value)) {
                // Integer literal - check range
                if (numExpr->value >= INT32_MIN && numExpr->value <= INT32_MAX) {
                    return BaseType::INTEGER;
                } else if (numExpr->value >= INT64_MIN && numExpr->value <= INT64_MAX) {
                    return BaseType::LONG;
                } else {
                    // Too large even for LONG, use DOUBLE
                    return BaseType::DOUBLE;
                }
            } else {
                // Has fractional part, it's a float
                return BaseType::DOUBLE;
            }
        }
        
        case ASTNodeType::EXPR_STRING:
            return BaseType::STRING;
            
        case ASTNodeType::EXPR_VARIABLE: {
            const auto* varExpr = static_cast<const VariableExpression*>(expr);
            return getVariableType(varExpr->name);
        }
        
        case ASTNodeType::EXPR_BINARY: {
            const auto* binExpr = static_cast<const BinaryExpression*>(expr);
            
            // Comparison operations ALWAYS return INTEGER (boolean), regardless of operand types
            if (binExpr->op >= TokenType::EQUAL && binExpr->op <= TokenType::GREATER_EQUAL) {
                return BaseType::INTEGER;
            }
            
            BaseType leftType = getExpressionType(binExpr->left.get());
            BaseType rightType = getExpressionType(binExpr->right.get());
            
            // String concatenation returns string
            if (typeManager_.isString(leftType) || typeManager_.isString(rightType)) {
                return BaseType::STRING;
            }
            
            // Arithmetic operations promote to common type
            return typeManager_.getPromotedType(leftType, rightType);
        }
        
        case ASTNodeType::EXPR_UNARY: {
            const auto* unaryExpr = static_cast<const UnaryExpression*>(expr);
            if (unaryExpr->op == TokenType::NOT) {
                return BaseType::INTEGER;  // Logical NOT returns boolean
            }
            return getExpressionType(unaryExpr->expr.get());
        }
        
        case ASTNodeType::EXPR_ARRAY_ACCESS: {
            const auto* arrExpr = static_cast<const ArrayAccessExpression*>(expr);
            const auto& symbolTable = semantic_.getSymbolTable();
            
            // Check if this is an object subscript first
            const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(arrExpr->name);
            if (varSym) {
                auto& registry = FasterBASIC::getRuntimeObjectRegistry();
                if (registry.isObjectType(varSym->typeDesc)) {
                    const FasterBASIC::ObjectTypeDescriptor* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
                    if (objDesc && objDesc->hasSubscriptOperator) {
                        // Object subscript returns the value type (for now, assume pointer/long)
                        // TODO: Return proper type based on object's value type descriptor
                        return objDesc->subscriptReturnType.baseType;
                    }
                }
            }
            
            // Normal array access
            auto it = symbolTable.arrays.find(arrExpr->name);
            if (it == symbolTable.arrays.end()) {
                return BaseType::UNKNOWN;
            }
            const auto& arraySymbol = it->second;
            return arraySymbol.elementTypeDesc.baseType;
        }
        
        case ASTNodeType::EXPR_IIF: {
            const auto* iifExpr = static_cast<const IIFExpression*>(expr);
            // IIF result type is the promoted type of true/false branches
            BaseType trueType = getExpressionType(iifExpr->trueValue.get());
            BaseType falseType = getExpressionType(iifExpr->falseValue.get());
            return typeManager_.getPromotedType(trueType, falseType);
        }
        
        case ASTNodeType::EXPR_FUNCTION_CALL: {
            const auto* callExpr = static_cast<const FunctionCallExpression*>(expr);
            
            // Look up function in symbol table to get return type
            const auto& symbolTable = semantic_.getSymbolTable();
            auto it = symbolTable.functions.find(callExpr->name);
            if (it != symbolTable.functions.end()) {
                return it->second.returnTypeDesc.baseType;
            }
            
            // Check for intrinsic functions
            std::string upperName = callExpr->name;
            std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
            
            // String functions
            if (upperName.back() == '$' || upperName == "CHR" || upperName == "STR" || 
                upperName == "LEFT" || upperName == "RIGHT" || upperName == "MID" ||
                upperName == "SPACE" || upperName == "STRING" || upperName == "UCASE" || 
                upperName == "LCASE" || upperName == "TRIM" || upperName == "LTRIM" || 
                upperName == "RTRIM" || upperName == "__STRING_SLICE") {
                return BaseType::STRING;
            }
            
            // Integer functions
            if (upperName == "LEN" || upperName == "ASC" || upperName == "INSTR" ||
                upperName == "INT" || upperName == "FIX" || upperName == "SGN" ||
                upperName == "CINT" || upperName == "ERR" || upperName == "ERL") {
                return BaseType::INTEGER;
            }
            
            // ABS returns same type as argument
            if (upperName == "ABS" && callExpr->arguments.size() == 1) {
                return getExpressionType(callExpr->arguments[0].get());
            }
            
            // Floating point math functions
            if (upperName == "SIN" || upperName == "COS" || upperName == "TAN" ||
                upperName == "SQRT" || upperName == "SQR" || upperName == "LOG" || 
                upperName == "EXP" || upperName == "RND" || upperName == "VAL") {
                return BaseType::DOUBLE;
            }
            
            // Default to DOUBLE for unknown functions
            return BaseType::DOUBLE;
        }
        
        case ASTNodeType::EXPR_METHOD_CALL: {
            const auto* methodExpr = static_cast<const MethodCallExpression*>(expr);
            
            // === CLASS instance method return type resolution ===
            // Check ME.Method() calls first
            if (methodExpr->object->getType() == ASTNodeType::EXPR_ME) {
                const FasterBASIC::ClassSymbol* cls = currentClassContext_;
                if (!cls) {
                    // Fallback: search all classes for the method
                    for (const auto& pair : semantic_.getSymbolTable().classes) {
                        if (pair.second.findMethod(methodExpr->methodName)) {
                            cls = &pair.second;
                            break;
                        }
                    }
                }
                if (cls) {
                    const auto* mi = cls->findMethod(methodExpr->methodName);
                    if (mi) {
                        return mi->returnType.baseType;
                    }
                }
            }
            
            // Check variable.Method() calls
            if (methodExpr->object->getType() == ASTNodeType::EXPR_VARIABLE) {
                const auto* varExpr = static_cast<const VariableExpression*>(methodExpr->object.get());
                std::string objectName = varExpr->name;
                
                // Look up the variable to get its type descriptor
                std::string currentFunc = symbolMapper_.getCurrentFunction();
                const auto* varSym = semantic_.lookupVariableScoped(objectName, currentFunc);
                if (!varSym) {
                    varSym = semantic_.getSymbolTable().lookupVariableLegacy(objectName);
                }
                if (!varSym) {
                    auto varIt = semantic_.getSymbolTable().variables.find(objectName);
                    if (varIt != semantic_.getSymbolTable().variables.end()) {
                        varSym = &varIt->second;
                    }
                }
                
                if (varSym) {
                    // CLASS instance method
                    if (varSym->typeDesc.isClassType) {
                        const FasterBASIC::ClassSymbol* cls = semantic_.getSymbolTable().lookupClass(varSym->typeDesc.className);
                        if (cls) {
                            const auto* mi = cls->findMethod(methodExpr->methodName);
                            if (mi) {
                                return mi->returnType.baseType;
                            }
                        }
                    }
                    
                    const FasterBASIC::TypeDescriptor& objectTypeDesc = varSym->typeDesc;
                    
                    // Runtime object method (HASHMAP, etc.)
                    auto& registry = FasterBASIC::getRuntimeObjectRegistry();
                    if (registry.isObjectType(objectTypeDesc)) {
                        const FasterBASIC::ObjectTypeDescriptor* objDesc = registry.getObjectType(objectTypeDesc.objectTypeName);
                        if (objDesc) {
                            const FasterBASIC::MethodSignature* method = objDesc->findMethod(methodExpr->methodName);
                            if (method) {
                                return method->returnType;
                            }
                        }
                    }
                }
                
                // --- METHOD-local CLASS instance fallback ---
                // DIM'd CLASS instances inside METHOD bodies are registered
                // in methodParamTypes_ / methodParamClassNames_ but are NOT
                // in the semantic symbol table.  Resolve the return type
                // from the ClassSymbol stored at DIM time.
                if (!varSym && currentClassContext_) {
                    auto mpTypeIt = methodParamTypes_.find(objectName);
                    if (mpTypeIt != methodParamTypes_.end() &&
                        mpTypeIt->second == FasterBASIC::BaseType::CLASS_INSTANCE) {
                        const FasterBASIC::ClassSymbol* cls = nullptr;
                        auto cnIt = methodParamClassNames_.find(objectName);
                        if (cnIt != methodParamClassNames_.end()) {
                            cls = semantic_.getSymbolTable().lookupClass(cnIt->second);
                        }
                        // Fallback: search all classes for one with this method
                        if (!cls) {
                            for (const auto& pair : semantic_.getSymbolTable().classes) {
                                if (pair.second.findMethod(methodExpr->methodName)) {
                                    cls = &pair.second;
                                    break;
                                }
                            }
                        }
                        if (cls) {
                            const auto* mi = cls->findMethod(methodExpr->methodName);
                            if (mi) {
                                return mi->returnType.baseType;
                            }
                        }
                    }
                }
            }
            
            return BaseType::UNKNOWN;
        }
        
        case ASTNodeType::EXPR_MEMBER_ACCESS: {
            const auto* memberExpr = static_cast<const MemberAccessExpression*>(expr);
            
            // === CLASS Instance Member Type Resolution ===
            // Check if the base is ME or a CLASS variable — resolve field type from ClassSymbol
            {
                const FasterBASIC::ClassSymbol* classSym = nullptr;
                
                if (memberExpr->object->getType() == ASTNodeType::EXPR_ME) {
                    // ME.Field — use current class context or search all classes
                    if (currentClassContext_) {
                        classSym = currentClassContext_;
                    } else {
                        const auto& symbolTable = semantic_.getSymbolTable();
                        for (const auto& pair : symbolTable.classes) {
                            if (pair.second.findField(memberExpr->memberName)) {
                                classSym = &pair.second;
                                break;
                            }
                        }
                    }
                } else if (memberExpr->object->getType() == ASTNodeType::EXPR_VARIABLE) {
                    const auto* varExpr = static_cast<const VariableExpression*>(memberExpr->object.get());
                    std::string currentFunc = symbolMapper_.getCurrentFunction();
                    const auto* varSymbol = semantic_.lookupVariableScoped(varExpr->name, currentFunc);
                    if (!varSymbol) {
                        varSymbol = semantic_.getSymbolTable().lookupVariableLegacy(varExpr->name);
                    }
                    if (varSymbol && varSymbol->typeDesc.isClassType) {
                        classSym = semantic_.getSymbolTable().lookupClass(varSymbol->typeDesc.className);
                    }
                }
                
                if (classSym) {
                    const auto* fieldInfo = classSym->findField(memberExpr->memberName);
                    if (fieldInfo) {
                        return fieldInfo->typeDesc.baseType;
                    }
                    // Could be a method call disguised as member access — fall through
                }
            }
            
            // === Standard UDT Member Type Resolution ===
            // Determine the UDT type name of the base object
            std::string udtTypeName;
            
            if (memberExpr->object->getType() == ASTNodeType::EXPR_VARIABLE) {
                // Simple variable: P.X
                const auto* varExpr = static_cast<const VariableExpression*>(memberExpr->object.get());
                std::string varName = varExpr->name;
                
                std::string currentFunc = symbolMapper_.getCurrentFunction();
                const auto* varSymbol = semantic_.lookupVariableScoped(varName, currentFunc);
                if (!varSymbol || varSymbol->typeDesc.baseType != BaseType::USER_DEFINED) {
                    return BaseType::UNKNOWN;
                }
                udtTypeName = varSymbol->typeName;
                
            } else if (memberExpr->object->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
                // Array element: Points(0).X
                const auto* arrExpr = static_cast<const ArrayAccessExpression*>(memberExpr->object.get());
                const auto& symbolTable = semantic_.getSymbolTable();
                auto arrIt = symbolTable.arrays.find(arrExpr->name);
                if (arrIt == symbolTable.arrays.end() ||
                    arrIt->second.elementTypeDesc.baseType != BaseType::USER_DEFINED) {
                    return BaseType::UNKNOWN;
                }
                udtTypeName = arrIt->second.elementTypeDesc.udtName;
                
            } else if (memberExpr->object->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
                // Nested member access: O.Item.Value
                // Walk to the root variable, then traverse the chain to find the
                // UDT type of the intermediate member (the base of this expression).
                
                // Collect the chain of member names from root to the parent of this expr
                std::vector<std::string> chainNames;
                const Expression* cur = memberExpr->object.get();
                while (cur->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
                    const auto* ma = static_cast<const MemberAccessExpression*>(cur);
                    chainNames.push_back(ma->memberName);
                    cur = ma->object.get();
                }
                // chainNames is in reverse order (innermost first)
                std::reverse(chainNames.begin(), chainNames.end());
                
                // cur should now be the root variable or array access
                std::string rootUDTName;
                if (cur->getType() == ASTNodeType::EXPR_VARIABLE) {
                    const auto* rootVar = static_cast<const VariableExpression*>(cur);
                    std::string currentFunc = symbolMapper_.getCurrentFunction();
                    const auto* rootSym = semantic_.lookupVariableScoped(rootVar->name, currentFunc);
                    if (!rootSym || rootSym->typeDesc.baseType != BaseType::USER_DEFINED) {
                        return BaseType::UNKNOWN;
                    }
                    rootUDTName = rootSym->typeName;
                } else if (cur->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
                    const auto* arrExpr = static_cast<const ArrayAccessExpression*>(cur);
                    const auto& symbolTable = semantic_.getSymbolTable();
                    auto arrIt = symbolTable.arrays.find(arrExpr->name);
                    if (arrIt == symbolTable.arrays.end() ||
                        arrIt->second.elementTypeDesc.baseType != BaseType::USER_DEFINED) {
                        return BaseType::UNKNOWN;
                    }
                    rootUDTName = arrIt->second.elementTypeDesc.udtName;
                } else {
                    return BaseType::UNKNOWN;
                }
                
                // Traverse the chain to find the UDT type of the intermediate result
                const auto& symbolTable = semantic_.getSymbolTable();
                std::string currentUDT = rootUDTName;
                for (const auto& name : chainNames) {
                    auto it = symbolTable.types.find(currentUDT);
                    if (it == symbolTable.types.end()) return BaseType::UNKNOWN;
                    const auto* fld = it->second.findField(name);
                    if (!fld) return BaseType::UNKNOWN;
                    if (fld->typeDesc.baseType != BaseType::USER_DEFINED) {
                        return BaseType::UNKNOWN; // intermediate must be UDT
                    }
                    currentUDT = fld->typeDesc.udtName;
                }
                udtTypeName = currentUDT;
                
            } else {
                return BaseType::UNKNOWN;
            }
            
            // Look up the UDT definition and find the field type
            const auto& symbolTable = semantic_.getSymbolTable();
            auto udtIt = symbolTable.types.find(udtTypeName);
            if (udtIt == symbolTable.types.end()) {
                return BaseType::UNKNOWN;
            }
            
            const auto& udtDef = udtIt->second;
            
            // Find the field type
            for (const auto& field : udtDef.fields) {
                if (field.name == memberExpr->memberName) {
                    return field.typeDesc.baseType;
                }
            }
            
            return BaseType::UNKNOWN;
        }
        
        // CLASS & Object System expression types
        case ASTNodeType::EXPR_NEW:
            return BaseType::CLASS_INSTANCE;
        
        case ASTNodeType::EXPR_ME:
            return BaseType::CLASS_INSTANCE;
        
        case ASTNodeType::EXPR_NOTHING:
            return BaseType::CLASS_INSTANCE;
        
        case ASTNodeType::EXPR_IS_TYPE:
            return BaseType::INTEGER;  // IS returns a boolean (0 or 1)
        
        case ASTNodeType::EXPR_SUPER_CALL:
            return BaseType::UNKNOWN;  // SUPER() is a statement, not a value
        
        default:
            return BaseType::UNKNOWN;
    }
}

BaseType ASTEmitter::getVariableType(const std::string& varName) {
    // Normalize the variable name first to match symbol table entries
    std::string normalizedName = normalizeVariableName(varName);
    
    // --- Method parameter fallback ---
    // Inside CLASS methods/constructors, parameters are registered in
    // methodParamTypes_ and are NOT in the global symbol table.
    {
        auto mpIt = methodParamTypes_.find(normalizedName);
        if (mpIt != methodParamTypes_.end()) {
            return mpIt->second;
        }
        // Also try the raw (un-normalized) name — registerMethodParam stores
        // the name exactly as given by the parser.
        auto mpIt2 = methodParamTypes_.find(varName);
        if (mpIt2 != methodParamTypes_.end()) {
            return mpIt2->second;
        }
    }
    
    // --- FOR EACH variable fallback ---
    // FOR EACH iteration variables are intentionally kept out of the symbol
    // table; their types are tracked in forEachVarTypes_.
    {
        auto feIt = forEachVarTypes_.find(normalizedName);
        if (feIt != forEachVarTypes_.end()) {
            return feIt->second;
        }
    }
    
    // Check if this is a parameter first - get type from function symbol
    if (symbolMapper_.inFunctionScope() && symbolMapper_.isParameter(normalizedName)) {
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.functions.find(currentFunc);
        if (it != symbolTable.functions.end()) {
            const auto& funcSymbol = it->second;
            // Find the parameter index
            for (size_t i = 0; i < funcSymbol.parameters.size(); ++i) {
                if (funcSymbol.parameters[i] == normalizedName) {
                    BaseType paramType = funcSymbol.parameterTypeDescs[i].baseType;
                    return paramType;
                }
            }
        }
    }
    
    // Use scoped lookup for variable type with normalized name
    std::string currentFunc = symbolMapper_.getCurrentFunction();
    const auto* varSymbol = semantic_.lookupVariableScoped(normalizedName, currentFunc);
    if (!varSymbol) {
        return BaseType::UNKNOWN;
    }
    
    return varSymbol->typeDesc.baseType;
}



// === Helper: get QBE operator names ===

std::string ASTEmitter::getQBEArithmeticOp(TokenType op) {
    switch (op) {
        case TokenType::PLUS:       return "add";
        case TokenType::MINUS:      return "sub";
        case TokenType::MULTIPLY:   return "mul";
        case TokenType::DIVIDE:     return "div";
        case TokenType::INT_DIVIDE: return "div";  // Integer division (same as regular div for now)
        case TokenType::MOD:        return "rem";
        case TokenType::POWER:      return "pow";  // TODO: implement power as runtime call
        default:                    return "add";
    }
}

std::string ASTEmitter::getQBEComparisonOp(TokenType op) {
    switch (op) {
        case TokenType::EQUAL:         return "eq";
        case TokenType::NOT_EQUAL:     return "ne";
        case TokenType::LESS_THAN:     return "slt";
        case TokenType::LESS_EQUAL:    return "sle";
        case TokenType::GREATER_THAN:  return "sgt";
        case TokenType::GREATER_EQUAL: return "sge";
        default:                       return "eq";
    }
}

// === FOR Loop Helpers (including FOR EACH / FOR...IN) ===

void ASTEmitter::emitForInit(const ForStatement* stmt) {
    // Invalidate array element cache - FOR init modifies loop variable
    clearArrayElementCache();
    // FOR loop initialization: evaluate start, limit, and step ONCE
    // All values must be treated as integers (BASIC requirement)
    
    // 1. Evaluate and store start value to loop variable
    std::string startValue = emitExpressionAs(stmt->start.get(), BaseType::INTEGER);
    storeVariable(stmt->variable, startValue);

    // Check if slots were pre-allocated in the entry block
    std::string limitVar = "__for_limit_" + stmt->variable;
    std::string stepVar  = "__for_step_" + stmt->variable;
    bool slotsPreAllocated = forLoopTempAddresses_.find(limitVar) != forLoopTempAddresses_.end();

    if (slotsPreAllocated) {
        // Use pre-allocated slots — only emit stores
        std::string limitAddr = forLoopTempAddresses_[limitVar];
        std::string limitValue = emitExpressionAs(stmt->end.get(), BaseType::INTEGER);
        builder_.emitRaw("    storew " + limitValue + ", " + limitAddr);

        std::string stepAddr = forLoopTempAddresses_[stepVar];
        std::string stepValue;
        if (stmt->step) {
            stepValue = emitExpressionAs(stmt->step.get(), BaseType::INTEGER);
        } else {
            stepValue = builder_.newTemp();
            builder_.emitRaw("    " + stepValue + " =w copy 1");
        }
        builder_.emitRaw("    storew " + stepValue + ", " + stepAddr);
    } else {
        // Fallback: inline allocs (only safe if init block not in a loop)
        // 2. Allocate and initialize limit variable (constant during loop)
        std::string limitAddr = builder_.newTemp();
        builder_.emitRaw("    " + limitAddr + " =l alloc4 4");
        std::string limitValue = emitExpressionAs(stmt->end.get(), BaseType::INTEGER);
        builder_.emitRaw("    storew " + limitValue + ", " + limitAddr);
        forLoopTempAddresses_[limitVar] = limitAddr;

        // 3. Allocate and initialize step variable (constant during loop, default to 1)
        std::string stepAddr = builder_.newTemp();
        builder_.emitRaw("    " + stepAddr + " =l alloc4 4");
        std::string stepValue;
        if (stmt->step) {
            stepValue = emitExpressionAs(stmt->step.get(), BaseType::INTEGER);
        } else {
            stepValue = builder_.newTemp();
            builder_.emitRaw("    " + stepValue + " =w copy 1");
        }
        builder_.emitRaw("    storew " + stepValue + ", " + stepAddr);
        forLoopTempAddresses_[stepVar] = stepAddr;
    }
}

std::string ASTEmitter::emitForCondition(const ForStatement* stmt) {
    // FOR loop condition: check if loop should continue
    // Load loop variable and limit, load step, and do simple comparison
    
    // Load loop variable (may have been modified in loop body)
    std::string loopVar = loadVariable(stmt->variable);
    
    // Load limit (constant, evaluated once at init)
    std::string limitVar = "__for_limit_" + stmt->variable;
    std::string limitAddr = forLoopTempAddresses_[limitVar];
    std::string limitValue = builder_.newTemp();
    builder_.emitRaw("    " + limitValue + " =w loadw " + limitAddr);
    
    // Load step value to check sign
    std::string stepVar = "__for_step_" + stmt->variable;
    std::string stepAddr = forLoopTempAddresses_[stepVar];
    std::string stepValue = builder_.newTemp();
    builder_.emitRaw("    " + stepValue + " =w loadw " + stepAddr);
    
    // Check if step is negative
    std::string stepIsNeg = builder_.newTemp();
    builder_.emitRaw("    " + stepIsNeg + " =w csltw " + stepValue + ", 0");
    
    // For positive step: continue while loopVar <= limit
    // For negative step: continue while loopVar >= limit
    // We compute both and select based on sign
    
    // Positive case: loopVar <= limit is !(loopVar > limit)
    std::string loopGtLimit = builder_.newTemp();
    builder_.emitRaw("    " + loopGtLimit + " =w csgtw " + loopVar + ", " + limitValue);
    std::string posCondition = builder_.newTemp();
    builder_.emitRaw("    " + posCondition + " =w xor " + loopGtLimit + ", 1");
    
    // Negative case: loopVar >= limit is !(loopVar < limit)
    std::string loopLtLimit = builder_.newTemp();
    builder_.emitRaw("    " + loopLtLimit + " =w csltw " + loopVar + ", " + limitValue);
    std::string negCondition = builder_.newTemp();
    builder_.emitRaw("    " + negCondition + " =w xor " + loopLtLimit + ", 1");
    
    // Select: if stepIsNeg then negCondition else posCondition
    // Use arithmetic: result = stepIsNeg * negCondition + (1 - stepIsNeg) * posCondition
    std::string negPart = builder_.newTemp();
    builder_.emitRaw("    " + negPart + " =w and " + stepIsNeg + ", " + negCondition);
    std::string notStepIsNeg = builder_.newTemp();
    builder_.emitRaw("    " + notStepIsNeg + " =w xor " + stepIsNeg + ", 1");
    std::string posPart = builder_.newTemp();
    builder_.emitRaw("    " + posPart + " =w and " + notStepIsNeg + ", " + posCondition);
    std::string result = builder_.newTemp();
    builder_.emitRaw("    " + result + " =w or " + negPart + ", " + posPart);
    
    return result;
}

void ASTEmitter::emitForIncrement(const ForStatement* stmt) {
    // Invalidate array element cache - FOR NEXT modifies loop variable
    clearArrayElementCache();
    // FOR loop increment: add step to loop variable
    // Step was evaluated once at init and is constant
    
    // Load current loop variable value (may have been modified in body)
    std::string loopVar = loadVariable(stmt->variable);
    
    // Load step value (constant, evaluated once at init)
    std::string stepVar = "__for_step_" + stmt->variable;
    std::string stepAddr = forLoopTempAddresses_[stepVar];
    std::string stepValue = builder_.newTemp();
    builder_.emitRaw("    " + stepValue + " =w loadw " + stepAddr);
    
    // Increment: var = var + step
    std::string newValue = builder_.newTemp();
    builder_.emitBinary(newValue, "w", "add", loopVar, stepValue);
    
    // Store back to variable
    storeVariable(stmt->variable, newValue);
}

// =============================================================================
// FOR EACH / FOR...IN Loop Helpers
// =============================================================================
// FOR EACH elem IN arr  (or  FOR elem, idx IN arr)
//
// Lowered to an index-counted loop:
//   __foreach_idx_<var> = LBOUND(arr, 1)
//   __foreach_ub_<var>  = UBOUND(arr, 1)
//   loop while __foreach_idx_<var> <= __foreach_ub_<var>:
//       elem = arr(__foreach_idx_<var>)
//       [idx  = __foreach_idx_<var>]   (if index variable present)
//       <body>
//       __foreach_idx_<var> += 1
// =============================================================================

// ---------------------------------------------------------------------------
// Pre-allocate shared scratch buffers in the entry block.
// QBE requires ALL alloc instructions to be in the function's start block.
// DIM statements and array accesses use temporary alloc'd buffers for
// bounds/indices arrays; these must be hoisted to block 0.
// ---------------------------------------------------------------------------

void ASTEmitter::preAllocateSharedBuffers() {
    if (!sharedBoundsBuffer_.empty())
        return; // already allocated

    builder_.emitComment("Pre-alloc shared scratch buffers (bounds & indices)");

    // Bounds buffer: 8 dims × 2 (lower+upper) × 4 bytes = 64 bytes
    sharedBoundsBuffer_ = builder_.newTemp();
    builder_.emitRaw("    " + sharedBoundsBuffer_ + " =l alloc8 64");

    // Indices buffer: 8 dims × 4 bytes = 32 bytes
    sharedIndicesBuffer_ = builder_.newTemp();
    builder_.emitRaw("    " + sharedIndicesBuffer_ + " =l alloc8 32");
}

// ---------------------------------------------------------------------------
// Pre-allocate stack slots for FOR loop temporaries.
// QBE requires ALL alloc instructions to be in the function's start block.
// These methods emit only the alloc instructions (no stores/init); the
// corresponding emitForInit / emitForEachInit methods then use the
// pre-allocated addresses from forLoopTempAddresses_ and emit only stores.
// ---------------------------------------------------------------------------

void ASTEmitter::preAllocateForSlots(const ForStatement* stmt) {
    std::string limitVar = "__for_limit_" + stmt->variable;
    if (forLoopTempAddresses_.find(limitVar) != forLoopTempAddresses_.end())
        return; // already allocated

    std::string limitAddr = builder_.newTemp();
    builder_.emitRaw("    " + limitAddr + " =l alloc4 4");
    builder_.emitStore("w", "0", limitAddr);
    forLoopTempAddresses_[limitVar] = limitAddr;

    std::string stepVar = "__for_step_" + stmt->variable;
    std::string stepAddr = builder_.newTemp();
    builder_.emitRaw("    " + stepAddr + " =l alloc4 4");
    builder_.emitStore("w", "0", stepAddr);
    forLoopTempAddresses_[stepVar] = stepAddr;
}

void ASTEmitter::preAllocateForEachSlots(const ForInStatement* stmt) {
    std::string idxVarKey = "__foreach_idx_" + stmt->variable;
    if (forLoopTempAddresses_.find(idxVarKey) != forLoopTempAddresses_.end())
        return; // already allocated

    // --- Resolve the collection name from the expression ---
    std::string collectionName;
    if (stmt->array && stmt->array->getType() == ASTNodeType::EXPR_VARIABLE) {
        const auto* varExpr = static_cast<const VariableExpression*>(stmt->array.get());
        collectionName = varExpr->name;
    } else {
        return; // can't pre-allocate without knowing the collection
    }

    const auto& symbolTable = semantic_.getSymbolTable();

    // --- Detect HASHMAP vs ARRAY ---
    bool isHashmap = false;
    {
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        const auto* varSym = semantic_.lookupVariableScoped(collectionName, currentFunc);
        if (varSym && varSym->typeDesc.baseType == BaseType::OBJECT &&
            varSym->typeDesc.objectTypeName == "HASHMAP") {
            isHashmap = true;
        }
    }

    builder_.emitComment("Pre-alloc FOR EACH slots for: " + stmt->variable +
                         (isHashmap ? " (hashmap)" : " (array)"));

    if (isHashmap) {
        // idx (0-based index, w)
        std::string idxAddr = builder_.newTemp();
        builder_.emitRaw("    " + idxAddr + " =l alloc4 4");
        builder_.emitStore("w", "0", idxAddr);
        forLoopTempAddresses_[idxVarKey] = idxAddr;

        // upper bound / count (w)
        std::string ubVar = "__foreach_ub_" + stmt->variable;
        std::string ubAddr = builder_.newTemp();
        builder_.emitRaw("    " + ubAddr + " =l alloc4 4");
        builder_.emitStore("w", "0", ubAddr);
        forLoopTempAddresses_[ubVar] = ubAddr;

        // keys array pointer (l)
        std::string keysVar = "__foreach_arr_" + stmt->variable;
        std::string keysAddr = builder_.newTemp();
        builder_.emitRaw("    " + keysAddr + " =l alloc8 8");
        builder_.emitStore("l", "0", keysAddr);
        forLoopTempAddresses_[keysVar] = keysAddr;

        // map pointer (l)
        std::string mapVar = "__foreach_map_" + stmt->variable;
        std::string mapAddr = builder_.newTemp();
        builder_.emitRaw("    " + mapAddr + " =l alloc8 8");
        builder_.emitStore("l", "0", mapAddr);
        forLoopTempAddresses_[mapVar] = mapAddr;

        // key variable slot (STRING = l)
        std::string varSlotKey = "__foreach_slot_" + stmt->variable;
        std::string slotAddr = builder_.newTemp();
        builder_.emitRaw("    " + slotAddr + " =l alloc8 8");
        builder_.emitStore("l", "0", slotAddr);
        forLoopTempAddresses_[varSlotKey] = slotAddr;
        globalVarAddresses_[stmt->variable] = slotAddr;

        // Register type as STRING for hashmap keys
        forEachVarTypes_[stmt->variable] = BaseType::STRING;

        // value variable slot if present (STRING = l)
        if (!stmt->indexVariable.empty()) {
            std::string valSlotKey = "__foreach_slot_" + stmt->indexVariable;
            std::string valAddr = builder_.newTemp();
            builder_.emitRaw("    " + valAddr + " =l alloc8 8");
            builder_.emitStore("l", "0", valAddr);
            forLoopTempAddresses_[valSlotKey] = valAddr;
            globalVarAddresses_[stmt->indexVariable] = valAddr;
            forEachVarTypes_[stmt->indexVariable] = BaseType::STRING;
        }
    } else {
        // --- ARRAY iteration ---
        BaseType elemType = BaseType::DOUBLE;
        auto ait = symbolTable.arrays.find(collectionName);
        if (ait != symbolTable.arrays.end()) {
            elemType = ait->second.elementTypeDesc.baseType;
        }

        // idx (w)
        std::string idxAddr = builder_.newTemp();
        builder_.emitRaw("    " + idxAddr + " =l alloc4 4");
        builder_.emitStore("w", "0", idxAddr);
        forLoopTempAddresses_[idxVarKey] = idxAddr;

        // upper bound (w)
        std::string ubVar = "__foreach_ub_" + stmt->variable;
        std::string ubAddr = builder_.newTemp();
        builder_.emitRaw("    " + ubAddr + " =l alloc4 4");
        builder_.emitStore("w", "0", ubAddr);
        forLoopTempAddresses_[ubVar] = ubAddr;

        // array descriptor pointer (l)
        std::string arrVar = "__foreach_arr_" + stmt->variable;
        std::string arrAddr = builder_.newTemp();
        builder_.emitRaw("    " + arrAddr + " =l alloc8 8");
        builder_.emitStore("l", "0", arrAddr);
        forLoopTempAddresses_[arrVar] = arrAddr;

        // element variable slot
        std::string qbeType = typeManager_.getQBEType(elemType);
        std::string varSlotKey = "__foreach_slot_" + stmt->variable;
        int slotSize = (qbeType == "l" || qbeType == "d") ? 8 : 4;
        std::string allocOp = (slotSize == 8) ? "alloc8" : "alloc4";
        std::string slotAddr = builder_.newTemp();
        builder_.emitRaw("    " + slotAddr + " =l " + allocOp + " " + std::to_string(slotSize));
        if (slotSize == 8) builder_.emitStore("l", "0", slotAddr);
        else               builder_.emitStore("w", "0", slotAddr);
        forLoopTempAddresses_[varSlotKey] = slotAddr;
        globalVarAddresses_[stmt->variable] = slotAddr;

        // Register element type
        forEachVarTypes_[stmt->variable] = elemType;

        // index variable slot if present (INTEGER = w)
        if (!stmt->indexVariable.empty()) {
            std::string idxSlotKey = "__foreach_slot_" + stmt->indexVariable;
            std::string idxSlot = builder_.newTemp();
            builder_.emitRaw("    " + idxSlot + " =l alloc4 4");
            builder_.emitStore("w", "0", idxSlot);
            forLoopTempAddresses_[idxSlotKey] = idxSlot;
            globalVarAddresses_[stmt->indexVariable] = idxSlot;
            forEachVarTypes_[stmt->indexVariable] = BaseType::INTEGER;
        }
    }
}

void ASTEmitter::emitForEachInit(const ForInStatement* stmt) {
    clearArrayElementCache();
    builder_.emitComment("FOR EACH " + stmt->variable +
                         (stmt->indexVariable.empty() ? "" : ", " + stmt->indexVariable) +
                         " IN <collection>");

    // --- Resolve the collection name from the expression ---
    std::string collectionName;
    if (stmt->array && stmt->array->getType() == ASTNodeType::EXPR_VARIABLE) {
        const auto* varExpr = static_cast<const VariableExpression*>(stmt->array.get());
        collectionName = varExpr->name;
    } else {
        builder_.emitComment("ERROR: FOR EACH collection expression is not a simple variable");
        return;
    }

    const auto& symbolTable = semantic_.getSymbolTable();

    // --- Detect HASHMAP vs ARRAY ---
    // Check if the collection is a HASHMAP (OBJECT type) by looking in the
    // variable symbol table rather than the arrays table.
    bool isHashmap = false;
    {
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        const auto* varSym = semantic_.lookupVariableScoped(collectionName, currentFunc);
        if (varSym && varSym->typeDesc.baseType == BaseType::OBJECT &&
            varSym->typeDesc.objectTypeName == "HASHMAP") {
            isHashmap = true;
        }
    }

    // Slots MUST already be pre-allocated in the entry block via
    // preAllocateForEachSlots().  If they are missing we fall back to
    // inline allocs (works only when the init block is not in a loop).
    bool slotsPreAllocated = forLoopTempAddresses_.find(
        "__foreach_idx_" + stmt->variable) != forLoopTempAddresses_.end();

    if (isHashmap) {
        // =================================================================
        // HASHMAP iteration
        // =================================================================
        forEachIsHashmap_.insert(stmt->variable);

        builder_.emitComment("FOR EACH over HASHMAP: " + collectionName);

        // Both key and value variables are STRING for hashmaps
        forEachVarTypes_[stmt->variable] = BaseType::STRING;
        if (!stmt->indexVariable.empty()) {
            forEachVarTypes_[stmt->indexVariable] = BaseType::STRING;
        }

        // --- Load hashmap pointer ---
        std::string mapPtr = loadVariable(collectionName);

        // --- Call hashmap_keys(map) to get NULL-terminated char** array ---
        std::string keysArr = builder_.newTemp();
        builder_.emitCall(keysArr, "l", "hashmap_keys", "l " + mapPtr);

        // --- Call hashmap_size(map) to get entry count ---
        std::string count = builder_.newTemp();
        builder_.emitCall(count, "w", "hashmap_size", "l " + mapPtr);

        if (slotsPreAllocated) {
            // Use pre-allocated slots — only emit stores
            std::string idxAddr = forLoopTempAddresses_["__foreach_idx_" + stmt->variable];
            builder_.emitStore("w", "0", idxAddr);

            std::string ubAddr = forLoopTempAddresses_["__foreach_ub_" + stmt->variable];
            builder_.emitStore("w", count, ubAddr);

            std::string keysAddrSlot = forLoopTempAddresses_["__foreach_arr_" + stmt->variable];
            builder_.emitStore("l", keysArr, keysAddrSlot);

            std::string mapAddrSlot = forLoopTempAddresses_["__foreach_map_" + stmt->variable];
            builder_.emitStore("l", mapPtr, mapAddrSlot);

            // Key/value slots already initialized to 0 in entry block
        } else {
            // Fallback: inline allocs (only safe if init block not in a loop)
            std::string idxVar  = "__foreach_idx_" + stmt->variable;
            std::string idxAddr = builder_.newTemp();
            builder_.emitRaw("    " + idxAddr + " =l alloc4 4");
            builder_.emitStore("w", "0", idxAddr);
            forLoopTempAddresses_[idxVar] = idxAddr;

            std::string ubVar  = "__foreach_ub_" + stmt->variable;
            std::string ubAddr = builder_.newTemp();
            builder_.emitRaw("    " + ubAddr + " =l alloc4 4");
            builder_.emitStore("w", count, ubAddr);
            forLoopTempAddresses_[ubVar] = ubAddr;

            std::string keysVar = "__foreach_arr_" + stmt->variable;
            std::string keysAddrSlot = builder_.newTemp();
            builder_.emitRaw("    " + keysAddrSlot + " =l alloc8 8");
            builder_.emitStore("l", keysArr, keysAddrSlot);
            forLoopTempAddresses_[keysVar] = keysAddrSlot;

            std::string mapVar = "__foreach_map_" + stmt->variable;
            std::string mapAddrSlot = builder_.newTemp();
            builder_.emitRaw("    " + mapAddrSlot + " =l alloc8 8");
            builder_.emitStore("l", mapPtr, mapAddrSlot);
            forLoopTempAddresses_[mapVar] = mapAddrSlot;

            std::string varSlotKey = "__foreach_slot_" + stmt->variable;
            if (forLoopTempAddresses_.find(varSlotKey) == forLoopTempAddresses_.end()) {
                std::string slotAddr = builder_.newTemp();
                builder_.emitRaw("    " + slotAddr + " =l alloc8 8");
                builder_.emitStore("l", "0", slotAddr);
                forLoopTempAddresses_[varSlotKey] = slotAddr;
                globalVarAddresses_[stmt->variable] = slotAddr;
            }

            if (!stmt->indexVariable.empty()) {
                std::string valSlotKey = "__foreach_slot_" + stmt->indexVariable;
                if (forLoopTempAddresses_.find(valSlotKey) == forLoopTempAddresses_.end()) {
                    std::string valSlot = builder_.newTemp();
                    builder_.emitRaw("    " + valSlot + " =l alloc8 8");
                    builder_.emitStore("l", "0", valSlot);
                    forLoopTempAddresses_[valSlotKey] = valSlot;
                    globalVarAddresses_[stmt->indexVariable] = valSlot;
                }
            }
        }

    } else {
        // =================================================================
        // ARRAY iteration
        // =================================================================

        // --- Determine element type from array symbol and register it ---
        BaseType elemType = BaseType::DOUBLE; // default
        auto ait = symbolTable.arrays.find(collectionName);
        if (ait != symbolTable.arrays.end()) {
            elemType = ait->second.elementTypeDesc.baseType;
        }
        forEachVarTypes_[stmt->variable] = elemType;
        if (!stmt->indexVariable.empty()) {
            forEachVarTypes_[stmt->indexVariable] = BaseType::INTEGER;
        }

        // --- Load array descriptor pointer ---
        std::string descName = symbolMapper_.getArrayDescriptorName(collectionName);
        std::string currentFunc = symbolMapper_.getCurrentFunction();
        bool isGlobal = true;
        if (ait != symbolTable.arrays.end()) {
            isGlobal = ait->second.functionScope.empty();
        }
        if (isGlobal && descName[0] != '$') descName = "$" + descName;
        else if (!isGlobal && descName[0] != '%') descName = "%" + descName;

        std::string arrPtr = builder_.newTemp();
        builder_.emitLoad(arrPtr, "l", descName);

        // --- Call array_lbound / array_ubound ---
        std::string lb = builder_.newTemp();
        builder_.emitCall(lb, "w", "array_lbound", "l " + arrPtr + ", w 1");

        std::string ub = builder_.newTemp();
        builder_.emitCall(ub, "w", "array_ubound", "l " + arrPtr + ", w 1");

        if (slotsPreAllocated) {
            // Use pre-allocated slots — only emit stores
            std::string idxAddr = forLoopTempAddresses_["__foreach_idx_" + stmt->variable];
            builder_.emitStore("w", lb, idxAddr);

            std::string ubAddr = forLoopTempAddresses_["__foreach_ub_" + stmt->variable];
            builder_.emitStore("w", ub, ubAddr);

            std::string arrAddr = forLoopTempAddresses_["__foreach_arr_" + stmt->variable];
            builder_.emitStore("l", arrPtr, arrAddr);

            // Element/index slots already initialized to 0 in entry block
        } else {
            // Fallback: inline allocs (only safe if init block not in a loop)
            std::string idxVar  = "__foreach_idx_" + stmt->variable;
            std::string idxAddr = builder_.newTemp();
            builder_.emitRaw("    " + idxAddr + " =l alloc4 4");
            builder_.emitStore("w", lb, idxAddr);
            forLoopTempAddresses_[idxVar] = idxAddr;

            std::string ubVar  = "__foreach_ub_" + stmt->variable;
            std::string ubAddr = builder_.newTemp();
            builder_.emitRaw("    " + ubAddr + " =l alloc4 4");
            builder_.emitStore("w", ub, ubAddr);
            forLoopTempAddresses_[ubVar] = ubAddr;

            std::string arrVar = "__foreach_arr_" + stmt->variable;
            std::string arrAddr = builder_.newTemp();
            builder_.emitRaw("    " + arrAddr + " =l alloc8 8");
            builder_.emitStore("l", arrPtr, arrAddr);
            forLoopTempAddresses_[arrVar] = arrAddr;

            std::string qbeType = typeManager_.getQBEType(elemType);
            std::string varSlotKey = "__foreach_slot_" + stmt->variable;
            if (forLoopTempAddresses_.find(varSlotKey) == forLoopTempAddresses_.end()) {
                std::string slotAddr = builder_.newTemp();
                int slotSize = (qbeType == "l" || qbeType == "d") ? 8 : 4;
                std::string allocOp = (slotSize == 8) ? "alloc8" : "alloc4";
                builder_.emitRaw("    " + slotAddr + " =l " + allocOp + " " + std::to_string(slotSize));
                if (slotSize == 8) builder_.emitStore("l", "0", slotAddr);
                else               builder_.emitStore("w", "0", slotAddr);
                forLoopTempAddresses_[varSlotKey] = slotAddr;
                globalVarAddresses_[stmt->variable] = slotAddr;
            }

            if (!stmt->indexVariable.empty()) {
                std::string idxSlotKey = "__foreach_slot_" + stmt->indexVariable;
                if (forLoopTempAddresses_.find(idxSlotKey) == forLoopTempAddresses_.end()) {
                    std::string idxSlot = builder_.newTemp();
                    builder_.emitRaw("    " + idxSlot + " =l alloc4 4");
                    builder_.emitStore("w", "0", idxSlot);
                    forLoopTempAddresses_[idxSlotKey] = idxSlot;
                    globalVarAddresses_[stmt->indexVariable] = idxSlot;
                }
            }
        }
    }
}

std::string ASTEmitter::emitForEachCondition(const ForInStatement* stmt) {
    std::string idxVar  = "__foreach_idx_" + stmt->variable;
    std::string ubVar   = "__foreach_ub_"  + stmt->variable;

    std::string idxAddr = forLoopTempAddresses_[idxVar];
    std::string ubAddr  = forLoopTempAddresses_[ubVar];

    std::string idx = builder_.newTemp();
    builder_.emitRaw("    " + idx + " =w loadw " + idxAddr);

    std::string ub = builder_.newTemp();
    builder_.emitRaw("    " + ub + " =w loadw " + ubAddr);

    if (forEachIsHashmap_.count(stmt->variable)) {
        // Hashmap: 0-based index, condition is idx < count
        std::string cond = builder_.newTemp();
        builder_.emitRaw("    " + cond + " =w csltw " + idx + ", " + ub);
        return cond;
    } else {
        // Array: lbound-based index, condition is idx <= ubound
        std::string gt = builder_.newTemp();
        builder_.emitRaw("    " + gt + " =w csgtw " + idx + ", " + ub);
        std::string cond = builder_.newTemp();
        builder_.emitRaw("    " + cond + " =w xor " + gt + ", 1");
        return cond;
    }
}

void ASTEmitter::emitForEachIncrement(const ForInStatement* stmt) {
    clearArrayElementCache();
    std::string idxVar  = "__foreach_idx_" + stmt->variable;
    std::string idxAddr = forLoopTempAddresses_[idxVar];

    std::string idx = builder_.newTemp();
    builder_.emitRaw("    " + idx + " =w loadw " + idxAddr);

    std::string next = builder_.newTemp();
    builder_.emitRaw("    " + next + " =w add " + idx + ", 1");

    builder_.emitStore("w", next, idxAddr);
}

void ASTEmitter::emitForEachBodyPreamble(const ForInStatement* stmt) {
    clearArrayElementCache();

    // --- Load current index ---
    std::string idxVar  = "__foreach_idx_" + stmt->variable;
    std::string idxAddr = forLoopTempAddresses_[idxVar];
    std::string idx = builder_.newTemp();
    builder_.emitRaw("    " + idx + " =w loadw " + idxAddr);

    if (forEachIsHashmap_.count(stmt->variable)) {
        // =================================================================
        // HASHMAP body preamble
        // =================================================================
        builder_.emitComment("FOR EACH body (HASHMAP): load key into " + stmt->variable);

        // --- Load keys array pointer ---
        std::string keysVar = "__foreach_arr_" + stmt->variable;
        std::string keysAddrSlot = forLoopTempAddresses_[keysVar];
        std::string keysArr = builder_.newTemp();
        builder_.emitRaw("    " + keysArr + " =l loadl " + keysAddrSlot);

        // --- Compute keys[idx]: each pointer is 8 bytes ---
        std::string idxL = builder_.newTemp();
        builder_.emitRaw("    " + idxL + " =l extsw " + idx);
        std::string offset = builder_.newTemp();
        builder_.emitRaw("    " + offset + " =l mul " + idxL + ", 8");
        std::string keyPtrAddr = builder_.newTemp();
        builder_.emitRaw("    " + keyPtrAddr + " =l add " + keysArr + ", " + offset);
        std::string keyCStr = builder_.newTemp();
        builder_.emitRaw("    " + keyCStr + " =l loadl " + keyPtrAddr);

        // --- Wrap raw C string as a string descriptor ---
        std::string keyDesc = builder_.newTemp();
        builder_.emitCall(keyDesc, "l", "string_new_utf8", "l " + keyCStr);

        // --- Store key descriptor into key variable slot ---
        std::string varSlotKey = "__foreach_slot_" + stmt->variable;
        std::string keySlotAddr = forLoopTempAddresses_[varSlotKey];
        builder_.emitStore("l", keyDesc, keySlotAddr);

        // --- If value variable present, call hashmap_lookup ---
        if (!stmt->indexVariable.empty()) {
            builder_.emitComment("FOR EACH body (HASHMAP): load value into " + stmt->indexVariable);

            // Load hashmap pointer
            std::string mapVar = "__foreach_map_" + stmt->variable;
            std::string mapAddrSlot = forLoopTempAddresses_[mapVar];
            std::string mapPtr = builder_.newTemp();
            builder_.emitRaw("    " + mapPtr + " =l loadl " + mapAddrSlot);

            // Call hashmap_lookup — returns the stored value pointer
            // For HASHMAP, values are string descriptors (BasicString*)
            std::string valuePtr = builder_.newTemp();
            builder_.emitCall(valuePtr, "l", "hashmap_lookup",
                             "l " + mapPtr + ", l " + keyCStr);

            // Store value pointer into value variable slot
            std::string valSlotKey = "__foreach_slot_" + stmt->indexVariable;
            std::string valSlotAddr = forLoopTempAddresses_[valSlotKey];
            builder_.emitStore("l", valuePtr, valSlotAddr);
        }

    } else {
        // =================================================================
        // ARRAY body preamble (existing logic)
        // =================================================================
        builder_.emitComment("FOR EACH body: load element into " + stmt->variable);

        // --- Store index into user-visible index variable (slot allocated in init) ---
        if (!stmt->indexVariable.empty()) {
            std::string idxSlotKey = "__foreach_slot_" + stmt->indexVariable;
            auto isit = forLoopTempAddresses_.find(idxSlotKey);
            if (isit != forLoopTempAddresses_.end()) {
                builder_.emitStore("w", idx, isit->second);
            }
        }

        // --- Load array descriptor ---
        std::string arrVar  = "__foreach_arr_" + stmt->variable;
        std::string arrPtrAddr = forLoopTempAddresses_[arrVar];
        std::string arrPtr = builder_.newTemp();
        builder_.emitRaw("    " + arrPtr + " =l loadl " + arrPtrAddr);

        // --- Build single-element indices array (reuse shared buffer) ---
        std::string indicesPtr;
        if (!sharedIndicesBuffer_.empty()) {
            indicesPtr = sharedIndicesBuffer_;
        } else {
            indicesPtr = builder_.newTemp();
            builder_.emitRaw("    " + indicesPtr + " =l alloc4 4");
        }
        builder_.emitStore("w", idx, indicesPtr);

        // --- Call array_get_address ---
        std::string elemAddr = builder_.newTemp();
        builder_.emitCall(elemAddr, "l", "array_get_address",
                         "l " + arrPtr + ", l " + indicesPtr);

        // --- Determine element type from the type registered at init time ---
        BaseType elemType = BaseType::DOUBLE; // default
        auto feIt = forEachVarTypes_.find(stmt->variable);
        if (feIt != forEachVarTypes_.end()) {
            elemType = feIt->second;
        }

        // --- Load element value and store into loop variable slot ---
        std::string qbeType = typeManager_.getQBEType(elemType);
        std::string loadOp;
        if (qbeType == "w")      loadOp = "loadw";
        else if (qbeType == "l") loadOp = "loadl";
        else if (qbeType == "s") loadOp = "loads";
        else if (qbeType == "d") loadOp = "loadd";
        else                     loadOp = "loadl"; // pointer-sized fallback

        std::string elemVal = builder_.newTemp();
        builder_.emitRaw("    " + elemVal + " =" + qbeType + " " + loadOp + " " + elemAddr);

        // The loop variable slot was pre-allocated in emitForEachInit and
        // registered in forLoopTempAddresses_ / globalVarAddresses_.
        std::string varSlotKey = "__foreach_slot_" + stmt->variable;
        std::string slotAddr = forLoopTempAddresses_[varSlotKey];

        if (qbeType == "w")      builder_.emitStore("w", elemVal, slotAddr);
        else if (qbeType == "l") builder_.emitStore("l", elemVal, slotAddr);
        else if (qbeType == "s") builder_.emitRaw("    stores " + elemVal + ", " + slotAddr);
        else if (qbeType == "d") builder_.emitRaw("    stored " + elemVal + ", " + slotAddr);
        else                     builder_.emitStore("l", elemVal, slotAddr);
    }
}

void ASTEmitter::emitForEachCleanup(const ForInStatement* stmt) {
    // Only hashmap iteration needs cleanup (free the keys array)
    if (!forEachIsHashmap_.count(stmt->variable)) {
        return;
    }
    builder_.emitComment("FOR EACH cleanup: free hashmap keys array");

    // Load the keys-array pointer from the pre-allocated slot and free it.
    std::string keysVar = "__foreach_arr_" + stmt->variable;
    auto it = forLoopTempAddresses_.find(keysVar);
    if (it != forLoopTempAddresses_.end()) {
        std::string keysAddrSlot = it->second;
        std::string keysArr = builder_.newTemp();
        builder_.emitLoad(keysArr, "l", keysAddrSlot);
        // Call free() — returns void, so no result capture
        builder_.emitRaw("    call $free(l " + keysArr + ")");
    }
}

std::string ASTEmitter::emitIfCondition(const IfStatement* stmt) {
    return emitExpression(stmt->condition.get());
}

std::string ASTEmitter::emitWhileCondition(const WhileStatement* stmt) {
    return emitExpression(stmt->condition.get());
}

std::string ASTEmitter::emitDoPreCondition(const DoStatement* stmt) {
    if (stmt->preConditionType == DoStatement::ConditionType::NONE) {
        return "";  // No pre-condition
    }
    
    if (!stmt->preCondition) {
        return "";  // Shouldn't happen, but handle gracefully
    }
    
    // Just emit the condition - CFG has already set up edges correctly
    // For DO WHILE: true → body, false → exit
    // For DO UNTIL: true → exit, false → body (CFG reverses edges)
    return emitExpression(stmt->preCondition.get());
}

std::string ASTEmitter::emitLoopPostCondition(const LoopStatement* stmt) {
    if (stmt->conditionType == LoopStatement::ConditionType::NONE) {
        return "";  // No post-condition
    }
    
    if (!stmt->condition) {
        return "";  // Shouldn't happen, but handle gracefully
    }
    
    // Just emit the condition - CFG has already set up edges correctly
    // For LOOP WHILE: true → body, false → exit
    // For LOOP UNTIL: true → exit, false → body (CFG reverses edges)
    return emitExpression(stmt->condition.get());
}

void ASTEmitter::emitReadStatement(const ReadStatement* stmt) {
    // Invalidate array element cache - READ modifies a variable
    clearArrayElementCache();
    builder_.emitComment("READ statement");
    
    // For each variable in the READ list
    for (const auto& varName : stmt->variables) {
        // Determine variable type
        BaseType varType = getVariableType(varName);
        std::string qbeType = typeManager_.getQBEType(varType);
        
        // Generate inline READ with type checking
        // 1. Load current data pointer
        std::string ptrReg = builder_.getNextTemp();
        builder_.emitLoad(ptrReg, "l", "$__data_pointer");
        
        // 2. Check if exhausted
        std::string endReg = builder_.getNextTemp();
        builder_.emitLoad(endReg, "l", "$__data_end_const");
        std::string exhaustedReg = builder_.getNextTemp();
        builder_.emitCompare(exhaustedReg, "l", "eq", ptrReg, endReg);
        
        std::string errorLabel = "data_exhausted_" + std::to_string(builder_.getNextLabelId());
        std::string okLabel = "read_ok_" + std::to_string(builder_.getNextLabelId());
        builder_.emitBranch(exhaustedReg, errorLabel, okLabel);
        
        // Error block
        builder_.emitLabel(errorLabel);
        builder_.emitCall("", "", "fb_error_out_of_data", "");
        builder_.emitCall("", "", "exit", "w 1");
        
        // OK block
        builder_.emitLabel(okLabel);
        
        // 3. Calculate data index: (ptr - start) / 8
        std::string startReg = builder_.getNextTemp();
        builder_.emitLoad(startReg, "l", "$__data_start");
        std::string offsetReg = builder_.getNextTemp();
        builder_.emitBinary(offsetReg, "l", "sub", ptrReg, startReg);
        std::string indexReg = builder_.getNextTemp();
        builder_.emitBinary(indexReg, "l", "div", offsetReg, "8");
        
        // 4. Load type tag: __data_types[index]
        // Calculate address: $data_type_0 + index*4 (type tags are words)
        std::string typeBaseReg = builder_.getNextTemp();
        builder_.emitInstruction(typeBaseReg + " =l copy $data_type_0");
        std::string typeOffsetReg = builder_.getNextTemp();
        builder_.emitBinary(typeOffsetReg, "l", "mul", indexReg, "4");
        std::string typeAddrReg = builder_.getNextTemp();
        builder_.emitBinary(typeAddrReg, "l", "add", typeBaseReg, typeOffsetReg);
        std::string typeTagReg = builder_.getNextTemp();
        builder_.emitLoad(typeTagReg, "w", typeAddrReg);
        
        // 5. Load the data value (always as long first)
        std::string dataValueReg = builder_.getNextTemp();
        builder_.emitLoad(dataValueReg, "l", ptrReg);
        
        // 6. Generate type switch based on target variable type
        std::string finalValueReg = builder_.getNextTemp();
        
        if (qbeType == "w") {
            // Target is int (w) - check source type and convert
            // If type == 0 (int): truncate long to int
            // If type == 1 (double): reinterpret bits as double, convert to int
            // If type == 2 (string): error
            builder_.emitComment("Convert DATA to int");
            builder_.emitInstruction(finalValueReg + " =w copy " + dataValueReg);
            
        } else if (qbeType == "d") {
            // Target is double (d) - check source type and convert
            // If type == 0 (int): convert long to double
            // If type == 1 (double): reinterpret bits as double
            // If type == 2 (string): error
            builder_.emitComment("Convert DATA to double");
            builder_.emitInstruction(finalValueReg + " =d cast " + dataValueReg);
            
        } else if (qbeType == "s") {
            // Target is single (s) - similar to double
            builder_.emitComment("Convert DATA to single");
            builder_.emitInstruction(finalValueReg + " =s cast " + dataValueReg);
            
        } else if (qbeType == "l" && typeManager_.isString(varType)) {
            // Target is string (l) - convert C string pointer to StringDescriptor
            builder_.emitComment("Convert DATA C string to StringDescriptor");
            std::string strDescReg = builder_.getNextTemp();
            builder_.emitCall(strDescReg, "l", "string_new_utf8", "l " + dataValueReg);
            finalValueReg = strDescReg;
            
        } else if (qbeType == "l") {
            // Target is long (l) - just copy
            builder_.emitComment("Copy DATA as long");
            finalValueReg = dataValueReg;  // Already correct type
            
        } else {
            builder_.emitComment("ERROR: unsupported QBE type for READ: " + qbeType);
            continue;
        }
        
        // Store to variable
        storeVariable(varName, finalValueReg);
        
        // 7. Advance pointer by 8 bytes
        std::string newPtrReg = builder_.getNextTemp();
        builder_.emitBinary(newPtrReg, "l", "add", ptrReg, "8");
        builder_.emitStore("l", newPtrReg, "$__data_pointer");
    }
}

void ASTEmitter::emitRestoreStatement(const RestoreStatement* stmt) {
    if (stmt->isLabel) {
        // RESTORE label_name
        builder_.emitComment("RESTORE " + stmt->label);
        std::string labelPos = "$data_label_" + stmt->label;
        std::string posReg = builder_.getNextTemp();
        builder_.emitLoad(posReg, "l", labelPos);
        builder_.emitStore("l", posReg, "$__data_pointer");
        
    } else if (stmt->lineNumber > 0) {
        // RESTORE line_number
        builder_.emitComment("RESTORE " + std::to_string(stmt->lineNumber));
        std::string linePos = "$data_line_" + std::to_string(stmt->lineNumber);
        std::string posReg = builder_.getNextTemp();
        builder_.emitLoad(posReg, "l", linePos);
        builder_.emitStore("l", posReg, "$__data_pointer");
        
    } else {
        // RESTORE with no argument - reset to start
        builder_.emitComment("RESTORE to start");
        std::string startReg = builder_.getNextTemp();
        builder_.emitLoad(startReg, "l", "$__data_start");
        builder_.emitStore("l", startReg, "$__data_pointer");
    }
}

void ASTEmitter::emitSliceAssignStatement(const SliceAssignStatement* stmt) {
    // Invalidate array element cache - slice assignment modifies a string variable
    clearArrayElementCache();
    if (!stmt || !stmt->start || !stmt->end || !stmt->replacement) {
        builder_.emitComment("ERROR: invalid slice assignment");
        return;
    }
    
    builder_.emitComment("String slice assignment: " + stmt->variable + "$(start TO end) = value");
    
    // Get the variable address
    std::string varAddr = getVariableAddress(stmt->variable);
    
    // Load current string pointer
    std::string currentPtr = builder_.newTemp();
    builder_.emitLoad(currentPtr, "l", varAddr);
    
    // Evaluate start, end, and replacement expressions
    std::string startReg = emitExpression(stmt->start.get());
    std::string endReg = emitExpression(stmt->end.get());
    std::string replReg = emitExpression(stmt->replacement.get());
    
    // Convert start and end to long if needed
    BaseType startType = getExpressionType(stmt->start.get());
    BaseType endType = getExpressionType(stmt->end.get());
    
    if (typeManager_.isIntegral(startType) && typeManager_.getQBEType(startType) == "w") {
        std::string startLong = builder_.newTemp();
        builder_.emitExtend(startLong, "l", "extsw", startReg);
        startReg = startLong;
    } else if (typeManager_.isFloatingPoint(startType)) {
        startReg = emitTypeConversion(startReg, startType, BaseType::LONG);
    }
    
    if (typeManager_.isIntegral(endType) && typeManager_.getQBEType(endType) == "w") {
        std::string endLong = builder_.newTemp();
        builder_.emitExtend(endLong, "l", "extsw", endReg);
        endReg = endLong;
    } else if (typeManager_.isFloatingPoint(endType)) {
        endReg = emitTypeConversion(endReg, endType, BaseType::LONG);
    }
    
    // Call string_slice_assign - it handles copy-on-write and returns modified/new descriptor
    // IMPORTANT: string_slice_assign manages its own memory:
    //   - If refcount > 1: clones, decrements original
    //   - If same length: modifies in place
    //   - If different length: creates new, frees old
    // So we don't release the old pointer - the function handles it
    std::string resultPtr = builder_.newTemp();
    builder_.emitCall(resultPtr, "l", "string_slice_assign", 
                     "l " + currentPtr + ", l " + startReg + ", l " + endReg + ", l " + replReg);
    
    // Store the result back to the variable
    builder_.emitStore("l", resultPtr, varAddr);
    
    builder_.emitComment("End slice assignment");
}

// Helper: Convert BaseType to runtime type suffix character
char ASTEmitter::getTypeSuffixChar(BaseType type) {
    switch (type) {
        case BaseType::INTEGER:
        case BaseType::UINTEGER:
            return '%';  // INTEGER
        case BaseType::LONG:
        case BaseType::ULONG:
            return '&';  // LONG
        case BaseType::SINGLE:
            return '!';  // SINGLE
        case BaseType::DOUBLE:
            return '#';  // DOUBLE
        case BaseType::STRING:
            return '$';  // STRING
        default:
            return '#';  // Default to DOUBLE for unknown types
    }
}

std::string ASTEmitter::emitArrayElementAddress(const std::string& arrayName, 
                                                 const std::vector<ExpressionPtr>& indices) {
    // Get array element address for UDT arrays
    // Returns a pointer to the element at the given indices
    
    // --- Array element base address cache ---
    // Workaround for QBE ARM64 miscompilation (GH-XXX): when the same array
    // element is accessed repeatedly (e.g. Contacts(Idx).Name then
    // Contacts(Idx).Phone), QBE's ARM64 backend can incorrectly drop the
    // index*element_size multiplication on the second and subsequent accesses,
    // especially when the index originates from a float-to-int conversion
    // (dtosi, e.g. VAL()).  By caching the computed element base address in a
    // stack slot and reloading it for subsequent accesses within the same
    // statement group, we emit only one mul+add sequence and reuse the result,
    // completely avoiding the pattern that triggers the bug.
    
    // Build cache key from array name + serialized index expression
    std::string cacheKey;
    if (indices.size() == 1) {
        std::string indexKey = serializeIndexExpression(indices[0].get());
        if (!indexKey.empty()) {
            cacheKey = arrayName + ":" + indexKey;
        }
    }
    
    // Check cache: if we already computed this element address, reload it
    if (!cacheKey.empty()) {
        auto cacheIt = arrayElemBaseCache_.find(cacheKey);
        if (cacheIt != arrayElemBaseCache_.end()) {
            builder_.emitComment("Cached array element address for: " + arrayName);
            std::string cachedAddr = builder_.newTemp();
            builder_.emitLoad(cachedAddr, "l", cacheIt->second);
            return cachedAddr;
        }
    }
    
    builder_.emitComment("Get address of array element: " + arrayName);
    
    // Look up array symbol
    const auto& symbolTable = semantic_.getSymbolTable();
    auto arrIt = symbolTable.arrays.find(arrayName);
    if (arrIt == symbolTable.arrays.end()) {
        builder_.emitComment("ERROR: Array not found: " + arrayName);
        return "0";
    }
    
    const auto& arraySymbol = arrIt->second;
    BaseType elemType = arraySymbol.elementTypeDesc.baseType;
    
    // Get array descriptor
    std::string descName = symbolMapper_.getArrayDescriptorName(arrayName);
    bool isGlobal = arraySymbol.functionScope.empty();
    if (isGlobal && descName[0] != '$') {
        descName = "$" + descName;
    } else if (!isGlobal && descName[0] != '%') {
        descName = "%" + descName;
    }
    
    // Load array descriptor
    std::string arrayDescPtr = builder_.newTemp();
    builder_.emitLoad(arrayDescPtr, "l", descName);
    
    // Get data pointer from array descriptor (offset 0)
    std::string dataPtr = builder_.newTemp();
    builder_.emitLoad(dataPtr, "l", arrayDescPtr);
    
    // Calculate element size
    int64_t elemSize;
    if (elemType == BaseType::USER_DEFINED) {
        // Get UDT size (with recursive calculation for nested UDTs)
        const auto& udtMap = symbolTable.types;
        auto udtIt = udtMap.find(arraySymbol.elementTypeDesc.udtName);
        if (udtIt != udtMap.end()) {
            elemSize = typeManager_.getUDTSizeRecursive(udtIt->second, udtMap);
        } else {
            builder_.emitComment("ERROR: UDT not found: " + arraySymbol.elementTypeDesc.udtName);
            return "0";
        }
    } else {
        elemSize = typeManager_.getTypeSize(elemType);
    }
    
    // For multi-dimensional arrays, we need to calculate the linear index
    // For now, support 1D arrays (most common case)
    if (indices.size() != 1) {
        builder_.emitComment("ERROR: Multi-dimensional UDT arrays not yet supported");
        return "0";
    }
    
    // Evaluate index expression
    std::string indexValue = emitExpressionAs(indices[0].get(), BaseType::INTEGER);
    
    // Convert index to long
    std::string indexLong = builder_.newTemp();
    builder_.emitInstruction(indexLong + " =l extsw " + indexValue);
    
    // Calculate byte offset: index * element_size
    std::string byteOffset = builder_.newTemp();
    builder_.emitBinary(byteOffset, "l", "mul", indexLong, std::to_string(elemSize));
    
    // Calculate element address: data_ptr + byte_offset
    std::string elemAddr = builder_.newTemp();
    builder_.emitBinary(elemAddr, "l", "add", dataPtr, byteOffset);
    
    // Store the computed address into a stack slot for cache reuse.
    // This prevents QBE from re-emitting the mul+add pattern when the same
    // element is accessed again for a different field.
    if (!cacheKey.empty()) {
        std::string cacheSlot = builder_.newTemp();
        builder_.emitRaw("    " + cacheSlot + " =l alloc8 8");
        builder_.emitRaw("    storel " + elemAddr + ", " + cacheSlot);
        arrayElemBaseCache_[cacheKey] = cacheSlot;
    }
    
    return elemAddr;
}

// =============================================================================
// serializeIndexExpression - Generate a cache key from an index expression
// =============================================================================
std::string ASTEmitter::serializeIndexExpression(const Expression* expr) const {
    if (!expr) return "";
    
    switch (expr->getType()) {
        case ASTNodeType::EXPR_VARIABLE: {
            const auto* varExpr = static_cast<const VariableExpression*>(expr);
            return "var:" + varExpr->name;
        }
        case ASTNodeType::EXPR_NUMBER: {
            const auto* numExpr = static_cast<const NumberExpression*>(expr);
            // Use integer representation for cache key when possible
            if (numExpr->value == static_cast<int>(numExpr->value)) {
                return "num:" + std::to_string(static_cast<int>(numExpr->value));
            }
            return "num:" + std::to_string(numExpr->value);
        }
        default:
            // Complex expressions (function calls, binary ops, etc.) are not
            // safe to cache because they may have side effects or different
            // results on re-evaluation. Return empty to skip caching.
            return "";
    }
}

// =============================================================================
// clearArrayElementCache - Invalidate all cached element base addresses
// =============================================================================
void ASTEmitter::clearArrayElementCache() {
    arrayElemBaseCache_.clear();
}

// =============================================================================
// NEON Phase 2: Element-wise UDT arithmetic helpers
// =============================================================================

int ASTEmitter::simdArrangementCode(const FasterBASIC::TypeDeclarationStatement::SIMDInfo& info) {
    // Map SIMDInfo to the integer constant encoding used in NEON IL opcodes:
    //   0 = Kw  (.4s integer)
    //   1 = Kl  (.2d integer)
    //   2 = Ks  (.4s float)
    //   3 = Kd  (.2d float)
    using SIMDType = FasterBASIC::TypeDeclarationStatement::SIMDType;
    switch (info.type) {
        case SIMDType::V4S:
        case SIMDType::V4S_PAD1:
        case SIMDType::QUAD:
            return info.isFloatingPoint ? 2 : 0;  // .4s float or .4s int
        case SIMDType::V2D:
        case SIMDType::PAIR:
            return info.isFloatingPoint ? 3 : 1;  // .2d float or .2d int
        default:
            return info.isFloatingPoint ? 2 : 0;  // default to .4s
    }
}

std::string ASTEmitter::getUDTTypeNameForExpr(const FasterBASIC::Expression* expr) {
    if (!expr) return "";

    std::string currentFunc = symbolMapper_.getCurrentFunction();

    if (expr->getType() == ASTNodeType::EXPR_VARIABLE) {
        const auto* varExpr = static_cast<const VariableExpression*>(expr);
        const auto* varSym = semantic_.lookupVariableScoped(varExpr->name, currentFunc);
        if (varSym && varSym->typeDesc.baseType == BaseType::USER_DEFINED) {
            return varSym->typeName.empty() ? varSym->typeDesc.udtName : varSym->typeName;
        }
    } else if (expr->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        const auto* arrExpr = static_cast<const ArrayAccessExpression*>(expr);
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.arrays.find(arrExpr->name);
        if (it != symbolTable.arrays.end() &&
            it->second.elementTypeDesc.baseType == BaseType::USER_DEFINED) {
            return it->second.elementTypeDesc.udtName;
        }
    } else if (expr->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
        // For nested UDT member access like container.innerUDT
        // Walk the chain to find the terminal UDT type
        const auto* memberExpr = static_cast<const MemberAccessExpression*>(expr);

        // Find the root variable
        const Expression* root = memberExpr->object.get();
        std::vector<std::string> chain;
        chain.push_back(memberExpr->memberName);
        while (root->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
            const auto* ma = static_cast<const MemberAccessExpression*>(root);
            chain.push_back(ma->memberName);
            root = ma->object.get();
        }
        std::reverse(chain.begin(), chain.end());

        std::string rootUDTName;
        if (root->getType() == ASTNodeType::EXPR_VARIABLE) {
            const auto* rootVar = static_cast<const VariableExpression*>(root);
            const auto* rootSym = semantic_.lookupVariableScoped(rootVar->name, currentFunc);
            if (!rootSym || rootSym->typeDesc.baseType != BaseType::USER_DEFINED) return "";
            rootUDTName = rootSym->typeName.empty() ? rootSym->typeDesc.udtName : rootSym->typeName;
        } else {
            return "";
        }

        // Traverse the chain to find the terminal field's UDT type
        const auto& symbolTable = semantic_.getSymbolTable();
        std::string currentUDT = rootUDTName;
        for (const auto& name : chain) {
            auto udtIt = symbolTable.types.find(currentUDT);
            if (udtIt == symbolTable.types.end()) return "";
            const auto* fld = udtIt->second.findField(name);
            if (!fld) return "";
            if (fld->typeDesc.baseType == BaseType::USER_DEFINED) {
                currentUDT = fld->typeDesc.udtName;
            } else {
                return "";  // terminal field is not a UDT
            }
        }
        return currentUDT;
    }

    return "";
}

std::string ASTEmitter::getUDTAddressForExpr(const FasterBASIC::Expression* expr) {
    if (!expr) return "";

    if (expr->getType() == ASTNodeType::EXPR_VARIABLE) {
        const auto* varExpr = static_cast<const VariableExpression*>(expr);
        return getVariableAddress(varExpr->name);
    } else if (expr->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        const auto* arrExpr = static_cast<const ArrayAccessExpression*>(expr);
        return emitArrayElementAddress(arrExpr->name, arrExpr->indices);
    } else if (expr->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
        return emitMemberAccessExpression(static_cast<const MemberAccessExpression*>(expr));
    }

    return "";
}

bool ASTEmitter::tryEmitNEONArithmetic(
        const FasterBASIC::LetStatement* stmt,
        const std::string& targetAddr,
        const FasterBASIC::TypeSymbol& udtDef,
        const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap) {

    // Check kill-switch
    static int neonArithChecked = 0;
    static int neonArithEnabled = 1;
    if (!neonArithChecked) {
        const char *env = getenv("ENABLE_NEON_ARITH");
        if (env) {
            neonArithEnabled = (strcmp(env, "1") == 0 || strcmp(env, "true") == 0);
        }
        neonArithChecked = 1;
    }
    if (!neonArithEnabled) return false;

    // The UDT must be SIMD-eligible and contain no string fields
    auto simdInfo = typeManager_.getSIMDInfo(udtDef);
    if (!simdInfo.isValid() || !simdInfo.isFullQ) return false;
    if (typeManager_.hasStringFields(udtDef, udtMap)) return false;

    // The value expression must be a binary expression
    if (!stmt->value || stmt->value->getType() != ASTNodeType::EXPR_BINARY) return false;

    const auto* binExpr = static_cast<const BinaryExpression*>(stmt->value.get());

    // Only handle arithmetic operators: +, -, *, /
    std::string neonOp;
    switch (binExpr->op) {
        case TokenType::PLUS:    neonOp = "neonadd"; break;
        case TokenType::MINUS:   neonOp = "neonsub"; break;
        case TokenType::MULTIPLY: neonOp = "neonmul"; break;
        case TokenType::DIVIDE:  neonOp = "neondiv"; break;
        default: return false;
    }

    // Division is only supported for float arrangements
    if ((neonOp == "neondiv") && !simdInfo.isFloatingPoint) return false;

    // Both operands must be the same UDT type as the target
    std::string leftUDT = getUDTTypeNameForExpr(binExpr->left.get());
    std::string rightUDT = getUDTTypeNameForExpr(binExpr->right.get());

    if (leftUDT.empty() || rightUDT.empty()) return false;
    if (leftUDT != udtDef.name || rightUDT != udtDef.name) return false;

    // All checks passed — emit NEON arithmetic sequence
    int arrCode = simdArrangementCode(simdInfo);

    // Get addresses of left and right operands
    std::string leftAddr = getUDTAddressForExpr(binExpr->left.get());
    std::string rightAddr = getUDTAddressForExpr(binExpr->right.get());

    if (leftAddr.empty() || rightAddr.empty()) return false;

    builder_.emitComment("NEON arithmetic (" + udtDef.name + ", "
        + std::string(simdInfo.arrangement()) + "): "
        + neonOp + " → 4 instructions");

    // neonldr  leftAddr   → loads into q28
    // neonldr2 rightAddr  → loads into q29
    // neon<op> arrCode    → v28 = v28 op v29
    // neonstr  targetAddr → stores q28 to target
    builder_.emitRaw("    neonldr " + leftAddr);
    builder_.emitRaw("    neonldr2 " + rightAddr);
    builder_.emitRaw("    " + neonOp + " " + std::to_string(arrCode));
    builder_.emitRaw("    neonstr " + targetAddr);

    return true;
}

// =============================================================================
// emitUDTCopyFieldByField - Recursive UDT field-by-field copy
// =============================================================================
// Copies all fields from sourceAddr to targetAddr for the given UDT definition.
// Handles string fields with retain/release and nested UDTs recursively to
// any depth, ensuring proper memory management at every level.
//
// NEON fast path: if the UDT is SIMD-eligible (all same-type numeric fields,
// total ≤ 128 bits) and has no string fields, emit a single NEON 128-bit
// load/store pair instead of per-field scalar copies.  This is controlled by
// the ENABLE_NEON_COPY environment variable (default: enabled).

// =============================================================================
// emitScalarUDTArithmetic - Scalar fallback for UDT element-wise arithmetic
// =============================================================================
// When NEON arithmetic is disabled (kill-switch) or the UDT is not SIMD-eligible,
// this function provides a scalar fallback that performs field-by-field arithmetic.
// Handles +, -, *, / for UDTs whose fields are all numeric (no strings).
//
// Pattern: C = A op B  where A, B, C are the same UDT type.
// For each field: C.field = A.field op B.field

bool ASTEmitter::emitScalarUDTArithmetic(
        const FasterBASIC::LetStatement* stmt,
        const std::string& targetAddr,
        const FasterBASIC::TypeSymbol& udtDef,
        const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap) {

    // The value expression must be a binary expression
    if (!stmt->value || stmt->value->getType() != ASTNodeType::EXPR_BINARY) return false;

    const auto* binExpr = static_cast<const BinaryExpression*>(stmt->value.get());

    // Only handle arithmetic operators: +, -, *, /
    std::string qbeOp;
    switch (binExpr->op) {
        case TokenType::PLUS:     qbeOp = "add"; break;
        case TokenType::MINUS:    qbeOp = "sub"; break;
        case TokenType::MULTIPLY: qbeOp = "mul"; break;
        case TokenType::DIVIDE:   qbeOp = "div"; break;
        default: return false;
    }

    // UDT must not contain string fields (no arithmetic on strings)
    if (typeManager_.hasStringFields(udtDef, udtMap)) return false;

    // Both operands must be the same UDT type as the target
    std::string leftUDT = getUDTTypeNameForExpr(binExpr->left.get());
    std::string rightUDT = getUDTTypeNameForExpr(binExpr->right.get());

    if (leftUDT.empty() || rightUDT.empty()) return false;
    if (leftUDT != udtDef.name || rightUDT != udtDef.name) return false;

    // Get addresses of left and right operands
    std::string leftAddr = getUDTAddressForExpr(binExpr->left.get());
    std::string rightAddr = getUDTAddressForExpr(binExpr->right.get());

    if (leftAddr.empty() || rightAddr.empty()) return false;

    builder_.emitComment("Scalar UDT arithmetic (" + udtDef.name + "): field-by-field " + qbeOp);

    // Iterate over all fields and emit scalar arithmetic for each
    int64_t offset = 0;
    for (size_t i = 0; i < udtDef.fields.size(); ++i) {
        const auto& field = udtDef.fields[i];
        BaseType fieldType = field.typeDesc.baseType;

        // Skip non-numeric fields (nested UDTs handled recursively if needed)
        if (fieldType == BaseType::STRING) continue;

        if (fieldType == BaseType::USER_DEFINED) {
            // For nested UDTs, we would need to recurse — skip for now
            auto nestedIt = udtMap.find(field.typeDesc.udtName);
            if (nestedIt != udtMap.end()) {
                offset += typeManager_.getUDTSizeRecursive(nestedIt->second, udtMap);
            }
            continue;
        }

        std::string qbeType = typeManager_.getQBEType(fieldType);

        // Calculate field addresses
        std::string leftFieldAddr = builder_.newTemp();
        std::string rightFieldAddr = builder_.newTemp();
        std::string dstFieldAddr = builder_.newTemp();

        if (offset > 0) {
            builder_.emitBinary(leftFieldAddr, "l", "add", leftAddr, std::to_string(offset));
            builder_.emitBinary(rightFieldAddr, "l", "add", rightAddr, std::to_string(offset));
            builder_.emitBinary(dstFieldAddr, "l", "add", targetAddr, std::to_string(offset));
        } else {
            builder_.emitRaw("    " + leftFieldAddr + " =l copy " + leftAddr);
            builder_.emitRaw("    " + rightFieldAddr + " =l copy " + rightAddr);
            builder_.emitRaw("    " + dstFieldAddr + " =l copy " + targetAddr);
        }

        // Load left and right values
        std::string leftVal = builder_.newTemp();
        std::string rightVal = builder_.newTemp();
        builder_.emitLoad(leftVal, qbeType, leftFieldAddr);
        builder_.emitLoad(rightVal, qbeType, rightFieldAddr);

        // Perform the arithmetic operation
        std::string result = builder_.newTemp();
        builder_.emitBinary(result, qbeType, qbeOp, leftVal, rightVal);

        // Store result to target field
        builder_.emitStore(qbeType, result, dstFieldAddr);

        // Advance offset for next field
        offset += typeManager_.getTypeSize(fieldType);
    }

    return true;
}

void ASTEmitter::emitUDTCopyFieldByField(
        const std::string& sourceAddr,
        const std::string& targetAddr,
        const FasterBASIC::TypeSymbol& udtDef,
        const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap) {

    // ── NEON bulk copy fast path ──
    // Check: (1) UDT is SIMD-eligible, (2) no string fields, (3) kill-switch
    auto simdInfo = typeManager_.getSIMDInfo(udtDef);
    if (simdInfo.isValid() && !typeManager_.hasStringFields(udtDef, udtMap)) {
        // Check environment kill-switch (cached after first call)
        static int neonCopyChecked = 0;
        static int neonCopyEnabled = 1;
        if (!neonCopyChecked) {
            const char *env = getenv("ENABLE_NEON_COPY");
            if (env) {
                neonCopyEnabled = (strcmp(env, "1") == 0 || strcmp(env, "true") == 0);
            }
            neonCopyChecked = 1;
        }

        if (neonCopyEnabled && simdInfo.isFullQ) {
            // Full 128-bit Q register: emit neonldr + neonstr (2 instructions)
            builder_.emitComment("NEON bulk copy (" + udtDef.name + ", "
                + std::string(simdInfo.arrangement()) + "): "
                + std::to_string(simdInfo.laneCount) + "×"
                + std::to_string(simdInfo.laneBitWidth) + "b → 2 instructions");
            builder_.emitRaw("    neonldr " + sourceAddr);
            builder_.emitRaw("    neonstr " + targetAddr);
            return;
        }
        // Half-register (64-bit) SIMD types: fall through to scalar path
        // for now — could use D-register loads in a future phase.
    }

    // ── Scalar field-by-field copy path ──
    int64_t offset = 0;
    for (size_t i = 0; i < udtDef.fields.size(); ++i) {
        const auto& field = udtDef.fields[i];
        BaseType fieldType = field.typeDesc.baseType;

        builder_.emitComment("Copy field: " + field.name + " (offset " + std::to_string(offset) + ")");

        // Calculate field address in source and target
        std::string srcFieldAddr = builder_.newTemp();
        std::string dstFieldAddr = builder_.newTemp();

        if (offset > 0) {
            builder_.emitBinary(srcFieldAddr, "l", "add", sourceAddr, std::to_string(offset));
            builder_.emitBinary(dstFieldAddr, "l", "add", targetAddr, std::to_string(offset));
        } else {
            builder_.emitRaw("    " + srcFieldAddr + " =l copy " + sourceAddr);
            builder_.emitRaw("    " + dstFieldAddr + " =l copy " + targetAddr);
        }

        if (fieldType == BaseType::STRING) {
            // String field – load pointer, retain new, store, release old
            std::string srcPtr = builder_.newTemp();
            builder_.emitLoad(srcPtr, "l", srcFieldAddr);

            std::string oldPtr = builder_.newTemp();
            builder_.emitLoad(oldPtr, "l", dstFieldAddr);

            std::string retainedPtr = builder_.newTemp();
            builder_.emitCall(retainedPtr, "l", "string_retain", "l " + srcPtr);

            builder_.emitStore("l", retainedPtr, dstFieldAddr);
            builder_.emitCall("", "", "string_release", "l " + oldPtr);

        } else if (fieldType == BaseType::USER_DEFINED) {
            // Nested UDT – recurse
            auto nestedIt = udtMap.find(field.typeDesc.udtName);
            if (nestedIt != udtMap.end()) {
                builder_.emitComment("Nested UDT copy: " + field.name + " (type " + field.typeDesc.udtName + ")");
                emitUDTCopyFieldByField(srcFieldAddr, dstFieldAddr, nestedIt->second, udtMap);
            }
        } else {
            // Scalar field – simple load/store
            std::string qbeType = typeManager_.getQBEType(fieldType);
            std::string val = builder_.newTemp();
            builder_.emitLoad(val, qbeType, srcFieldAddr);
            builder_.emitStore(qbeType, val, dstFieldAddr);
        }

        // Advance offset for next field
        if (fieldType == BaseType::USER_DEFINED) {
            auto nestedIt = udtMap.find(field.typeDesc.udtName);
            if (nestedIt != udtMap.end()) {
                offset += typeManager_.getUDTSizeRecursive(nestedIt->second, udtMap);
            }
        } else {
            offset += typeManager_.getTypeSize(fieldType);
        }
    }
}

// =============================================================================
// NEON Phase 3: Array Loop Vectorization
// =============================================================================

// ---------------------------------------------------------------------------
// Helper: check if an expression is a simple variable reference to the loop
// index variable (handles normalized names like "i%", "i_INT", etc.)
// ---------------------------------------------------------------------------
bool ASTEmitter::isLoopIndexVar(const FasterBASIC::Expression* expr,
                                const std::string& indexVar) const {
    if (!expr || expr->getType() != ASTNodeType::EXPR_VARIABLE) return false;
    const auto* ve = static_cast<const FasterBASIC::VariableExpression*>(expr);
    if (ve->name == indexVar) return true;

    // Normalize both names by stripping type suffixes and comparing base names.
    // The semantic analyzer may normalize "i%" → "i_INT", "x#" → "x_DOUBLE", etc.
    // We need to handle all combinations.
    auto stripToBase = [](const std::string& s) -> std::string {
        std::string r = s;
        // Strip trailing BASIC type-suffix character ('%', '#', '!', '&', '$')
        if (!r.empty()) {
            char c = r.back();
            if (c == '%' || c == '#' || c == '!' || c == '&' || c == '$')
                r.pop_back();
        }
        // Strip trailing semantic-analyzer type suffix (_INT, _DOUBLE, _SINGLE, _LONG, _STRING)
        static const char* suffixes[] = {
            "_INT", "_DOUBLE", "_SINGLE", "_LONG", "_STRING", "_FLOAT",
            "_INTEGER", nullptr
        };
        for (const char** sp = suffixes; *sp; ++sp) {
            std::string suf(*sp);
            if (r.size() > suf.size() &&
                r.compare(r.size() - suf.size(), suf.size(), suf) == 0) {
                r.erase(r.size() - suf.size());
                break;
            }
        }
        return r;
    };

    std::string baseExpr = stripToBase(ve->name);
    std::string baseIdx  = stripToBase(indexVar);
    return baseExpr == baseIdx;
}

// ---------------------------------------------------------------------------
// Helper: try to evaluate an expression as a compile-time integer constant
// ---------------------------------------------------------------------------
bool ASTEmitter::tryEvalConstantInt(const FasterBASIC::Expression* expr,
                                     int& outVal) const {
    if (!expr) return false;
    if (expr->getType() == ASTNodeType::EXPR_NUMBER) {
        const auto* num = static_cast<const FasterBASIC::NumberExpression*>(expr);
        double v = num->value;
        if (v == (int)v) {
            outVal = (int)v;
            return true;
        }
    }
    // Negative constant: unary minus on a number literal
    if (expr->getType() == ASTNodeType::EXPR_UNARY) {
        const auto* un = static_cast<const FasterBASIC::UnaryExpression*>(expr);
        if (un->op == FasterBASIC::TokenType::MINUS) {
            int inner;
            if (tryEvalConstantInt(un->expr.get(), inner)) {
                outVal = -inner;
                return true;
            }
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Helper: get the QBE name for an array descriptor pointer (load-ready)
// ---------------------------------------------------------------------------
std::string ASTEmitter::getArrayDescriptorPtr(const std::string& arrayName) {
    const auto& symbolTable = semantic_.getSymbolTable();
    auto arrIt = symbolTable.arrays.find(arrayName);
    if (arrIt == symbolTable.arrays.end()) return "";
    const auto& arraySymbol = arrIt->second;
    std::string descName = symbolMapper_.getArrayDescriptorName(arrayName);
    bool isGlobal = arraySymbol.functionScope.empty();
    if (isGlobal && descName[0] != '$') descName = "$" + descName;
    else if (!isGlobal && descName[0] != '%') descName = "%" + descName;
    return descName;
}

// ---------------------------------------------------------------------------
// matchWholeUDTBinaryOp — detect: C(i) = A(i) OP B(i)
// ---------------------------------------------------------------------------
bool ASTEmitter::matchWholeUDTBinaryOp(const FasterBASIC::LetStatement* stmt,
                                        const std::string& indexVar,
                                        SIMDLoopInfo& info) {
    using namespace FasterBASIC;

    // Must be an array element assignment with no member chain
    if (stmt->indices.size() != 1 || !stmt->memberChain.empty()) return false;
    // Index must be the loop variable
    if (!isLoopIndexVar(stmt->indices[0].get(), indexVar)) return false;
    // Value must be a binary expression
    if (!stmt->value || stmt->value->getType() != ASTNodeType::EXPR_BINARY) return false;

    const auto* binExpr = static_cast<const BinaryExpression*>(stmt->value.get());

    // Determine operation
    std::string op;
    switch (binExpr->op) {
        case TokenType::PLUS:     op = "add"; break;
        case TokenType::MINUS:    op = "sub"; break;
        case TokenType::MULTIPLY: op = "mul"; break;
        case TokenType::DIVIDE:   op = "div"; break;
        default: return false;
    }

    // Both sides must be array accesses with the same loop index
    if (!binExpr->left || binExpr->left->getType() != ASTNodeType::EXPR_ARRAY_ACCESS) return false;
    if (!binExpr->right || binExpr->right->getType() != ASTNodeType::EXPR_ARRAY_ACCESS) return false;

    const auto* leftArr  = static_cast<const ArrayAccessExpression*>(binExpr->left.get());
    const auto* rightArr = static_cast<const ArrayAccessExpression*>(binExpr->right.get());

    if (leftArr->indices.size() != 1 || !isLoopIndexVar(leftArr->indices[0].get(), indexVar)) return false;
    if (rightArr->indices.size() != 1 || !isLoopIndexVar(rightArr->indices[0].get(), indexVar)) return false;

    // All three arrays must be arrays of the same SIMD-eligible UDT
    const auto& symbolTable = semantic_.getSymbolTable();
    auto destIt = symbolTable.arrays.find(stmt->variable);
    auto srcAIt = symbolTable.arrays.find(leftArr->name);
    auto srcBIt = symbolTable.arrays.find(rightArr->name);
    if (destIt == symbolTable.arrays.end() || srcAIt == symbolTable.arrays.end() || srcBIt == symbolTable.arrays.end())
        return false;

    const auto& destSym = destIt->second;
    const auto& srcASym = srcAIt->second;
    const auto& srcBSym = srcBIt->second;

    // Must be UDT element types
    if (destSym.elementTypeDesc.baseType != BaseType::USER_DEFINED) return false;
    if (srcASym.elementTypeDesc.baseType != BaseType::USER_DEFINED) return false;
    if (srcBSym.elementTypeDesc.baseType != BaseType::USER_DEFINED) return false;

    // Must be the same UDT type
    std::string udtName = destSym.elementTypeDesc.udtName;
    if (srcASym.elementTypeDesc.udtName != udtName || srcBSym.elementTypeDesc.udtName != udtName)
        return false;

    // Look up the UDT and check SIMD eligibility
    auto udtIt = symbolTable.types.find(udtName);
    if (udtIt == symbolTable.types.end()) return false;
    const auto& udtDef = udtIt->second;
    auto simdInfo = typeManager_.getSIMDInfo(udtDef);
    if (!simdInfo.isValid() || !simdInfo.isFullQ) return false;
    if (typeManager_.hasStringFields(udtDef, symbolTable.types)) return false;

    // Division is only supported for float arrangements
    if (op == "div" && !simdInfo.isFloatingPoint) return false;

    // Build the operand list
    auto findOrAdd = [&](const std::string& name, bool readOnly) -> int {
        for (size_t i = 0; i < info.operands.size(); ++i) {
            if (info.operands[i].arrayName == name) {
                if (!readOnly) info.operands[i].isReadOnly = false;
                return (int)i;
            }
        }
        SIMDLoopInfo::ArrayOperand ao;
        ao.arrayName   = name;
        ao.udtTypeName = udtName;
        ao.simdInfo    = simdInfo;
        ao.isReadOnly  = readOnly;
        info.operands.push_back(ao);
        return (int)(info.operands.size() - 1);
    };

    info.srcAArrayIndex = findOrAdd(leftArr->name, true);
    info.srcBArrayIndex = findOrAdd(rightArr->name, true);
    info.destArrayIndex = findOrAdd(stmt->variable, false);
    info.operation      = op;
    info.arrangementCode = simdArrangementCode(simdInfo);
    info.elemSizeBytes   = simdInfo.totalBytes;
    return true;
}

// ---------------------------------------------------------------------------
// matchWholeUDTCopy — detect: B(i) = A(i)
// ---------------------------------------------------------------------------
bool ASTEmitter::matchWholeUDTCopy(const FasterBASIC::LetStatement* stmt,
                                    const std::string& indexVar,
                                    SIMDLoopInfo& info) {
    using namespace FasterBASIC;

    if (stmt->indices.size() != 1 || !stmt->memberChain.empty()) return false;
    if (!isLoopIndexVar(stmt->indices[0].get(), indexVar)) return false;

    // Value must be an array access with the loop index
    if (!stmt->value || stmt->value->getType() != ASTNodeType::EXPR_ARRAY_ACCESS) return false;
    const auto* srcArr = static_cast<const ArrayAccessExpression*>(stmt->value.get());
    if (srcArr->indices.size() != 1 || !isLoopIndexVar(srcArr->indices[0].get(), indexVar)) return false;

    // Both arrays must be of the same SIMD-eligible UDT
    const auto& symbolTable = semantic_.getSymbolTable();
    auto destIt = symbolTable.arrays.find(stmt->variable);
    auto srcIt  = symbolTable.arrays.find(srcArr->name);
    if (destIt == symbolTable.arrays.end() || srcIt == symbolTable.arrays.end()) return false;

    if (destIt->second.elementTypeDesc.baseType != BaseType::USER_DEFINED) return false;
    if (srcIt->second.elementTypeDesc.baseType  != BaseType::USER_DEFINED) return false;
    std::string udtName = destIt->second.elementTypeDesc.udtName;
    if (srcIt->second.elementTypeDesc.udtName != udtName) return false;

    auto udtIt = symbolTable.types.find(udtName);
    if (udtIt == symbolTable.types.end()) return false;
    const auto& udtDef = udtIt->second;
    auto simdInfo = typeManager_.getSIMDInfo(udtDef);
    if (!simdInfo.isValid() || !simdInfo.isFullQ) return false;
    if (typeManager_.hasStringFields(udtDef, symbolTable.types)) return false;

    SIMDLoopInfo::ArrayOperand srcOp;
    srcOp.arrayName   = srcArr->name;
    srcOp.udtTypeName = udtName;
    srcOp.simdInfo    = simdInfo;
    srcOp.isReadOnly  = true;
    info.operands.push_back(srcOp);
    info.srcAArrayIndex = 0;
    info.srcBArrayIndex = -1;

    SIMDLoopInfo::ArrayOperand dstOp;
    dstOp.arrayName   = stmt->variable;
    dstOp.udtTypeName = udtName;
    dstOp.simdInfo    = simdInfo;
    dstOp.isReadOnly  = false;
    info.operands.push_back(dstOp);
    info.destArrayIndex = 1;

    info.operation       = "copy";
    info.arrangementCode = simdArrangementCode(simdInfo);
    info.elemSizeBytes   = simdInfo.totalBytes;
    return true;
}

// ---------------------------------------------------------------------------
// matchFieldByFieldOp — detect N LetStatements that cover all fields of a
// SIMD-eligible UDT with the same binary op:
//   C(i).X = A(i).X OP B(i).X
//   C(i).Y = A(i).Y OP B(i).Y
//   ...
// ---------------------------------------------------------------------------
bool ASTEmitter::matchFieldByFieldOp(
        const std::vector<FasterBASIC::StatementPtr>& body,
        const std::string& indexVar,
        SIMDLoopInfo& info) {
    using namespace FasterBASIC;

    if (body.empty()) return false;

    // All statements must be LetStatements
    for (const auto& s : body) {
        if (!s || s->getType() != ASTNodeType::STMT_LET) return false;
    }

    // Analyse the first statement to extract arrays, operation, and UDT type
    const auto* first = static_cast<const LetStatement*>(body[0].get());
    if (first->indices.size() != 1 || first->memberChain.size() != 1) return false;
    if (!isLoopIndexVar(first->indices[0].get(), indexVar)) return false;
    if (!first->value || first->value->getType() != ASTNodeType::EXPR_BINARY) return false;

    const auto* bin = static_cast<const BinaryExpression*>(first->value.get());
    std::string op;
    switch (bin->op) {
        case TokenType::PLUS:     op = "add"; break;
        case TokenType::MINUS:    op = "sub"; break;
        case TokenType::MULTIPLY: op = "mul"; break;
        case TokenType::DIVIDE:   op = "div"; break;
        default: return false;
    }
    FasterBASIC::TokenType expectedOp = bin->op;

    // Both operands must be member accesses on array elements
    auto extractArrayMember = [&](const Expression* expr, std::string& arrName,
                                   std::string& fieldName) -> bool {
        if (!expr || expr->getType() != ASTNodeType::EXPR_MEMBER_ACCESS) return false;
        const auto* mem = static_cast<const MemberAccessExpression*>(expr);
        fieldName = mem->memberName;
        if (!mem->object || mem->object->getType() != ASTNodeType::EXPR_ARRAY_ACCESS) return false;
        const auto* arr = static_cast<const ArrayAccessExpression*>(mem->object.get());
        arrName = arr->name;
        if (arr->indices.size() != 1 || !isLoopIndexVar(arr->indices[0].get(), indexVar)) return false;
        return true;
    };

    std::string destArrayName = first->variable;
    std::string srcAArrayName, srcBArrayName;
    std::string fieldA, fieldB;
    if (!extractArrayMember(bin->left.get(), srcAArrayName, fieldA)) return false;
    if (!extractArrayMember(bin->right.get(), srcBArrayName, fieldB)) return false;

    // The first statement's member chain field and the source fields must match
    if (first->memberChain[0] != fieldA || first->memberChain[0] != fieldB) return false;

    // Look up the UDT
    const auto& symbolTable = semantic_.getSymbolTable();
    auto destArrIt = symbolTable.arrays.find(destArrayName);
    auto srcAArrIt = symbolTable.arrays.find(srcAArrayName);
    auto srcBArrIt = symbolTable.arrays.find(srcBArrayName);
    if (destArrIt == symbolTable.arrays.end() || srcAArrIt == symbolTable.arrays.end() ||
        srcBArrIt == symbolTable.arrays.end()) return false;

    if (destArrIt->second.elementTypeDesc.baseType != BaseType::USER_DEFINED) return false;
    std::string udtName = destArrIt->second.elementTypeDesc.udtName;
    if (srcAArrIt->second.elementTypeDesc.udtName != udtName ||
        srcBArrIt->second.elementTypeDesc.udtName != udtName) return false;

    auto udtIt = symbolTable.types.find(udtName);
    if (udtIt == symbolTable.types.end()) return false;
    const auto& udtDef = udtIt->second;
    auto simdInfo = typeManager_.getSIMDInfo(udtDef);
    if (!simdInfo.isValid() || !simdInfo.isFullQ) return false;
    if (typeManager_.hasStringFields(udtDef, symbolTable.types)) return false;
    if (op == "div" && !simdInfo.isFloatingPoint) return false;

    // We need exactly as many statements as UDT fields
    if (body.size() != udtDef.fields.size()) return false;

    // Verify every statement matches the pattern with the same arrays and op
    std::set<std::string> coveredFields;
    for (const auto& s : body) {
        const auto* let = static_cast<const LetStatement*>(s.get());
        if (let->variable != destArrayName) return false;
        if (let->indices.size() != 1 || !isLoopIndexVar(let->indices[0].get(), indexVar)) return false;
        if (let->memberChain.size() != 1) return false;
        if (!let->value || let->value->getType() != ASTNodeType::EXPR_BINARY) return false;
        const auto* b = static_cast<const BinaryExpression*>(let->value.get());
        if (b->op != expectedOp) return false;
        std::string sA, sB, fA, fB;
        if (!extractArrayMember(b->left.get(), sA, fA)) return false;
        if (!extractArrayMember(b->right.get(), sB, fB)) return false;
        if (sA != srcAArrayName || sB != srcBArrayName) return false;
        if (let->memberChain[0] != fA || let->memberChain[0] != fB) return false;
        coveredFields.insert(let->memberChain[0]);
    }

    // All UDT fields must be covered
    for (const auto& f : udtDef.fields) {
        if (coveredFields.find(f.name) == coveredFields.end()) return false;
    }

    // Build the info
    auto findOrAdd = [&](const std::string& name, bool readOnly) -> int {
        for (size_t i = 0; i < info.operands.size(); ++i) {
            if (info.operands[i].arrayName == name) {
                if (!readOnly) info.operands[i].isReadOnly = false;
                return (int)i;
            }
        }
        SIMDLoopInfo::ArrayOperand ao;
        ao.arrayName   = name;
        ao.udtTypeName = udtName;
        ao.simdInfo    = simdInfo;
        ao.isReadOnly  = readOnly;
        info.operands.push_back(ao);
        return (int)(info.operands.size() - 1);
    };

    info.srcAArrayIndex  = findOrAdd(srcAArrayName, true);
    info.srcBArrayIndex  = findOrAdd(srcBArrayName, true);
    info.destArrayIndex  = findOrAdd(destArrayName, false);
    info.operation       = op;
    info.arrangementCode = simdArrangementCode(simdInfo);
    info.elemSizeBytes   = simdInfo.totalBytes;
    return true;
}

// ---------------------------------------------------------------------------
// analyzeSIMDLoop — main entry point for Phase 3 loop analysis
// ---------------------------------------------------------------------------
SIMDLoopInfo ASTEmitter::analyzeSIMDLoop(const FasterBASIC::ForStatement* forStmt) {
    using namespace FasterBASIC;
    SIMDLoopInfo info;
    info.isVectorizable = false;

    if (!forStmt) return info;

    // --- Kill-switch check ---
    static int neonLoopChecked  = 0;
    static int neonLoopEnabled  = 1;
    if (!neonLoopChecked) {
        const char* env = getenv("ENABLE_NEON_LOOP");
        if (env) {
            neonLoopEnabled = (strcmp(env, "1") == 0 || strcmp(env, "true") == 0);
        }
        neonLoopChecked = 1;
    }
    if (!neonLoopEnabled) return info;

    // --- Step must be 1 (or absent, which defaults to 1) ---
    info.stepVal = 1;
    if (forStmt->step) {
        int sv;
        if (!tryEvalConstantInt(forStmt->step.get(), sv) || sv != 1)
            return info;
    }

    // --- Index variable ---
    info.indexVar = forStmt->variable;

    // --- Start / end values (may be constants or runtime expressions) ---
    if (tryEvalConstantInt(forStmt->start.get(), info.startVal))
        info.startIsConstant = true;
    if (tryEvalConstantInt(forStmt->end.get(), info.endVal))
        info.endIsConstant = true;

    // --- Body pattern matching ---
    const auto& body = forStmt->body;
    if (body.empty()) return info;

    // Check for disqualifying statement types (function calls, branches, etc.)
    for (const auto& s : body) {
        if (!s) return info;
        ASTNodeType t = s->getType();
        if (t != ASTNodeType::STMT_LET) return info; // Only LET statements allowed
    }

    // Try Pattern A: single whole-UDT binary op — C(i) = A(i) OP B(i)
    if (body.size() == 1) {
        const auto* let = static_cast<const LetStatement*>(body[0].get());
        if (matchWholeUDTBinaryOp(let, info.indexVar, info)) {
            info.isVectorizable = true;
            return info;
        }
        // Try Pattern B: whole-UDT copy — B(i) = A(i)
        if (matchWholeUDTCopy(let, info.indexVar, info)) {
            info.isVectorizable = true;
            return info;
        }
    }

    // Try Pattern C: field-by-field op covering all fields
    if (matchFieldByFieldOp(body, info.indexVar, info)) {
        info.isVectorizable = true;
        return info;
    }

    return info;
}

// ---------------------------------------------------------------------------
// emitSIMDLoop — emit the NEON-vectorized loop
// ---------------------------------------------------------------------------
void ASTEmitter::emitSIMDLoop(const FasterBASIC::ForStatement* forStmt,
                               const SIMDLoopInfo& info,
                               const std::string& exitLabel) {
    using namespace FasterBASIC;

    builder_.emitComment("=== NEON Phase 3: Vectorized array loop ===");
    builder_.emitComment("Pattern: " + info.operation
        + " | arrays: " + std::to_string(info.operands.size())
        + " | elemSize: " + std::to_string(info.elemSizeBytes) + "B");

    // --- 1. Evaluate loop start/end into QBE word temporaries ---
    std::string startW = emitExpressionAs(forStmt->start.get(), BaseType::INTEGER);
    std::string endW   = emitExpressionAs(forStmt->end.get(),   BaseType::INTEGER);

    // --- 2. Bounds-check every array for the range [start, end] ---
    for (const auto& op : info.operands) {
        std::string descName = getArrayDescriptorPtr(op.arrayName);
        if (descName.empty()) {
            builder_.emitComment("ERROR: cannot find descriptor for array: " + op.arrayName);
            return;
        }
        std::string arrPtr = builder_.newTemp();
        builder_.emitLoad(arrPtr, "l", descName);
        builder_.emitComment("Bounds-check array: " + op.arrayName);
        builder_.emitCall("", "", "array_check_range",
                         "l " + arrPtr + ", w " + startW + ", w " + endW);
    }

    // --- 3. Get data pointers for all arrays ---
    std::vector<std::string> basePtrs;
    for (const auto& op : info.operands) {
        std::string descName = getArrayDescriptorPtr(op.arrayName);
        std::string arrPtr = builder_.newTemp();
        builder_.emitLoad(arrPtr, "l", descName);
        std::string dataPtr = builder_.newTemp();
        builder_.emitCall(dataPtr, "l", "array_get_data_ptr", "l " + arrPtr);
        basePtrs.push_back(dataPtr);
    }

    // --- 4. Compute byte offsets ---
    // startOffset = startVal * elemSize (in bytes)
    // count = endVal - startVal + 1
    // totalBytes = count * elemSize
    std::string startL = builder_.newTemp();
    builder_.emitInstruction(startL + " =l extsw " + startW);
    std::string endL = builder_.newTemp();
    builder_.emitInstruction(endL + " =l extsw " + endW);

    std::string elemSizeL = builder_.newTemp();
    builder_.emitRaw("    " + elemSizeL + " =l copy " + std::to_string(info.elemSizeBytes));

    std::string startOff = builder_.newTemp();
    builder_.emitBinary(startOff, "l", "mul", startL, elemSizeL);

    std::string count = builder_.newTemp();
    builder_.emitBinary(count, "l", "sub", endL, startL);
    std::string count1 = builder_.newTemp();
    builder_.emitBinary(count1, "l", "add", count, "1");
    std::string totalBytes = builder_.newTemp();
    builder_.emitBinary(totalBytes, "l", "mul", count1, elemSizeL);

    // --- 5. Compute cursor start and end pointers ---
    // We iterate using a pointer to the destination array and compute
    // corresponding source pointers from offsets.
    // Alloc stack slots for the current byte-offset cursor and end offset
    std::string curOff = builder_.newTemp();
    builder_.emitRaw("    " + curOff + " =l alloc8 8");
    builder_.emitRaw("    storel " + startOff + ", " + curOff);

    std::string endOff = builder_.newTemp();
    builder_.emitBinary(endOff, "l", "add", startOff, totalBytes);
    std::string endOffSlot = builder_.newTemp();
    builder_.emitRaw("    " + endOffSlot + " =l alloc8 8");
    builder_.emitRaw("    storel " + endOff + ", " + endOffSlot);

    // --- 6. Emit the loop ---
    int loopId = builder_.getNextLabelId();
    std::string headerLabel = "neon_loop_hdr_" + std::to_string(loopId);
    std::string bodyLabel   = "neon_loop_body_" + std::to_string(loopId);
    std::string doneLabel   = "neon_loop_done_" + std::to_string(loopId);

    builder_.emitJump(headerLabel);
    builder_.emitLabel(headerLabel);

    // Load current offset and end offset
    std::string curOffVal = builder_.newTemp();
    builder_.emitRaw("    " + curOffVal + " =l loadl " + curOff);
    std::string endOffVal = builder_.newTemp();
    builder_.emitRaw("    " + endOffVal + " =l loadl " + endOffSlot);
    std::string done = builder_.newTemp();
    builder_.emitRaw("    " + done + " =w cugel " + curOffVal + ", " + endOffVal);
    builder_.emitBranch(done, doneLabel, bodyLabel);

    builder_.emitLabel(bodyLabel);

    // Reload current offset (SSA)
    std::string off = builder_.newTemp();
    builder_.emitRaw("    " + off + " =l loadl " + curOff);

    if (info.operation == "copy") {
        // --- Copy pattern: ldr q28 from srcA, str q28 to dest ---
        std::string srcAddr = builder_.newTemp();
        builder_.emitBinary(srcAddr, "l", "add", basePtrs[info.srcAArrayIndex], off);
        std::string dstAddr = builder_.newTemp();
        builder_.emitBinary(dstAddr, "l", "add", basePtrs[info.destArrayIndex], off);

        builder_.emitRaw("    neonldr " + srcAddr);
        builder_.emitRaw("    neonstr " + dstAddr);
    } else {
        // --- Arithmetic pattern: ldr q28, ldr2 q29, op, str q28 ---
        std::string srcAAddr = builder_.newTemp();
        builder_.emitBinary(srcAAddr, "l", "add", basePtrs[info.srcAArrayIndex], off);
        std::string srcBAddr = builder_.newTemp();
        builder_.emitBinary(srcBAddr, "l", "add", basePtrs[info.srcBArrayIndex], off);
        std::string dstAddr = builder_.newTemp();
        builder_.emitBinary(dstAddr, "l", "add", basePtrs[info.destArrayIndex], off);

        builder_.emitRaw("    neonldr " + srcAAddr);
        builder_.emitRaw("    neonldr2 " + srcBAddr);

        // Map operation name to NEON opcode
        std::string neonOp = "neon" + info.operation; // neonadd, neonsub, etc.
        builder_.emitRaw("    " + neonOp + " " + std::to_string(info.arrangementCode));
        builder_.emitRaw("    neonstr " + dstAddr);
    }

    // Advance offset by element size
    std::string nextOff = builder_.newTemp();
    builder_.emitBinary(nextOff, "l", "add", off, std::to_string(info.elemSizeBytes));
    builder_.emitRaw("    storel " + nextOff + ", " + curOff);
    builder_.emitJump(headerLabel);

    // --- 7. Loop done ---
    builder_.emitLabel(doneLabel);

    // Set loop variable to endVal + 1 (BASIC FOR semantics: variable is
    // one step past end after loop completes)
    std::string finalVal = builder_.newTemp();
    builder_.emitBinary(finalVal, "w", "add", endW, "1");
    storeVariable(forStmt->variable, finalVal);

    builder_.emitComment("=== End NEON vectorized loop ===");

    // Jump to the exit block (skipping the scalar loop body/condition/increment)
    if (!exitLabel.empty()) {
        builder_.emitJump(exitLabel);
    }
}

// =============================================================================
// Direct control-flow emission for METHOD/CONSTRUCTOR/DESTRUCTOR bodies
// =============================================================================
// Method bodies are emitted sequentially via emitMethodBody() without the
// CFG infrastructure.  Compound statements (IF, FOR, WHILE) therefore need
// self-contained inline emission that generates all labels, branches, and
// body code in one pass.

void ASTEmitter::emitIfDirect(const FasterBASIC::IfStatement* stmt) {
    if (!stmt) return;

    int id = builder_.getNextLabelId();
    std::string prefix = "mif_" + std::to_string(id);

    // We build label names for: then, each elseif, else, end
    std::string thenLabel  = prefix + "_then";
    std::string elseLabel  = prefix + "_else";
    std::string endLabel   = prefix + "_end";

    // How many ELSEIF clauses?
    size_t numElseIf = stmt->elseIfClauses.size();
    bool hasElse = !stmt->elseStatements.empty();

    // Determine the label to jump to when the IF condition is false
    std::string falseTarget;
    if (numElseIf > 0) {
        falseTarget = prefix + "_elseif_0";
    } else if (hasElse) {
        falseTarget = elseLabel;
    } else {
        falseTarget = endLabel;
    }

    // --- Evaluate IF condition ---
    builder_.emitComment("IF (direct, method body)");
    std::string condVal = emitExpression(stmt->condition.get());
    FasterBASIC::BaseType condType = getExpressionType(stmt->condition.get());

    // Convert to word-sized integer for branch
    std::string condW;
    if (condType == FasterBASIC::BaseType::DOUBLE || condType == FasterBASIC::BaseType::SINGLE) {
        condW = builder_.newTemp();
        std::string zero = builder_.newTemp();
        if (condType == FasterBASIC::BaseType::DOUBLE) {
            builder_.emitRaw("    " + zero + " =d copy d_0.0\n");
            builder_.emitRaw("    " + condW + " =w cned " + condVal + ", " + zero + "\n");
        } else {
            builder_.emitRaw("    " + zero + " =s copy s_0.0\n");
            builder_.emitRaw("    " + condW + " =w cnes " + condVal + ", " + zero + "\n");
        }
    } else if (condType == FasterBASIC::BaseType::LONG || condType == FasterBASIC::BaseType::STRING) {
        condW = builder_.newTemp();
        builder_.emitRaw("    " + condW + " =w cnel " + condVal + ", 0\n");
    } else {
        condW = condVal; // already w
    }

    builder_.emitRaw("    jnz " + condW + ", @" + thenLabel + ", @" + falseTarget + "\n");

    // Helper lambda: check if the last statement in a list is a RETURN or END
    // (which emits `ret` and terminates the block — no jump needed after).
    auto endsWithReturn = [](const std::vector<FasterBASIC::StatementPtr>& stmts) -> bool {
        if (stmts.empty()) return false;
        auto t = stmts.back()->getType();
        return t == FasterBASIC::ASTNodeType::STMT_RETURN ||
               t == FasterBASIC::ASTNodeType::STMT_END;
    };

    // --- THEN block ---
    builder_.emitLabel(thenLabel);
    for (const auto& s : stmt->thenStatements) {
        if (s) emitStatement(s.get());
    }
    if (!endsWithReturn(stmt->thenStatements)) {
        builder_.emitJump(endLabel);
    }

    // --- ELSEIF blocks ---
    for (size_t i = 0; i < numElseIf; i++) {
        std::string eifLabel = prefix + "_elseif_" + std::to_string(i);
        std::string eifBodyLabel = prefix + "_elseif_body_" + std::to_string(i);

        // Where to jump if this ELSEIF is false
        std::string nextTarget;
        if (i + 1 < numElseIf) {
            nextTarget = prefix + "_elseif_" + std::to_string(i + 1);
        } else if (hasElse) {
            nextTarget = elseLabel;
        } else {
            nextTarget = endLabel;
        }

        builder_.emitLabel(eifLabel);
        builder_.emitComment("ELSEIF");
        std::string eifCond = emitExpression(stmt->elseIfClauses[i].condition.get());
        FasterBASIC::BaseType eifType = getExpressionType(stmt->elseIfClauses[i].condition.get());

        std::string eifW;
        if (eifType == FasterBASIC::BaseType::DOUBLE || eifType == FasterBASIC::BaseType::SINGLE) {
            eifW = builder_.newTemp();
            std::string zero = builder_.newTemp();
            if (eifType == FasterBASIC::BaseType::DOUBLE) {
                builder_.emitRaw("    " + zero + " =d copy d_0.0\n");
                builder_.emitRaw("    " + eifW + " =w cned " + eifCond + ", " + zero + "\n");
            } else {
                builder_.emitRaw("    " + zero + " =s copy s_0.0\n");
                builder_.emitRaw("    " + eifW + " =w cnes " + eifCond + ", " + zero + "\n");
            }
        } else if (eifType == FasterBASIC::BaseType::LONG || eifType == FasterBASIC::BaseType::STRING) {
            eifW = builder_.newTemp();
            builder_.emitRaw("    " + eifW + " =w cnel " + eifCond + ", 0\n");
        } else {
            eifW = eifCond;
        }

        builder_.emitRaw("    jnz " + eifW + ", @" + eifBodyLabel + ", @" + nextTarget + "\n");

        builder_.emitLabel(eifBodyLabel);
        for (const auto& s : stmt->elseIfClauses[i].statements) {
            if (s) emitStatement(s.get());
        }
        if (!endsWithReturn(stmt->elseIfClauses[i].statements)) {
            builder_.emitJump(endLabel);
        }
    }

    // --- ELSE block ---
    if (hasElse) {
        builder_.emitLabel(elseLabel);
        builder_.emitComment("ELSE");
        for (const auto& s : stmt->elseStatements) {
            if (s) emitStatement(s.get());
        }
        if (!endsWithReturn(stmt->elseStatements)) {
            builder_.emitJump(endLabel);
        }
    }

    // --- END IF ---
    builder_.emitLabel(endLabel);
}

// ---------------------------------------------------------------------------
// bodyContainsDim — recursively check whether a statement list contains any
// DIM statement or string-producing operation (at any nesting depth inside
// FOR/IF/WHILE/DO bodies).
// Used to gate SAMM loop-iteration scope emission: we only pay the cost of
// samm_enter_scope / samm_exit_scope when the loop actually allocates.
// With SAMM string tracking, string operations (assignments to $ variables,
// PRINT of strings, etc.) also allocate and should trigger loop scopes.
// ---------------------------------------------------------------------------
bool ASTEmitter::bodyContainsDim(const std::vector<FasterBASIC::StatementPtr>& body) {
    for (const auto& s : body) {
        if (!s) continue;
        switch (s->getType()) {
            case FasterBASIC::ASTNodeType::STMT_DIM:
                return true;
            // LET assignment to a string variable (name ends with '$')
            // creates a new string descriptor that should be scope-tracked.
            case FasterBASIC::ASTNodeType::STMT_LET: {
                const auto* let = static_cast<const FasterBASIC::LetStatement*>(s.get());
                if (!let->variable.empty() && let->variable.back() == '$') return true;
                break;
            }
            // PRINT statements frequently concatenate strings, creating
            // temporaries that benefit from per-iteration cleanup.
            case FasterBASIC::ASTNodeType::STMT_PRINT:
                return true;
            case FasterBASIC::ASTNodeType::STMT_FOR: {
                const auto* f = static_cast<const FasterBASIC::ForStatement*>(s.get());
                if (bodyContainsDim(f->body)) return true;
                break;
            }
            case FasterBASIC::ASTNodeType::STMT_FOR_IN: {
                const auto* f = static_cast<const FasterBASIC::ForInStatement*>(s.get());
                if (bodyContainsDim(f->body)) return true;
                break;
            }
            case FasterBASIC::ASTNodeType::STMT_IF: {
                const auto* i = static_cast<const FasterBASIC::IfStatement*>(s.get());
                if (bodyContainsDim(i->thenStatements)) return true;
                for (const auto& c : i->elseIfClauses) {
                    if (bodyContainsDim(c.statements)) return true;
                }
                if (bodyContainsDim(i->elseStatements)) return true;
                break;
            }
            case FasterBASIC::ASTNodeType::STMT_WHILE: {
                const auto* w = static_cast<const FasterBASIC::WhileStatement*>(s.get());
                if (bodyContainsDim(w->body)) return true;
                break;
            }
            case FasterBASIC::ASTNodeType::STMT_DO: {
                const auto* d = static_cast<const FasterBASIC::DoStatement*>(s.get());
                if (bodyContainsDim(d->body)) return true;
                break;
            }
            default:
                break;
        }
    }
    return false;
}

void ASTEmitter::emitForDirect(const FasterBASIC::ForStatement* stmt) {
    if (!stmt) return;

    int id = builder_.getNextLabelId();
    std::string prefix   = "mfor_" + std::to_string(id);
    std::string condLabel = prefix + "_cond";
    std::string bodyLabel = prefix + "_body";
    std::string incrLabel = prefix + "_incr";
    std::string endLabel  = prefix + "_end";

    builder_.emitComment("FOR (direct, method body): " + stmt->variable);

    // Allocate loop variable as a method-local if not already registered
    std::string loopVarName = stmt->variable;
    if (methodParamAddresses_.find(loopVarName) == methodParamAddresses_.end()) {
        // Not registered yet — allocate a local slot
        std::string varSlot = "%var_" + loopVarName;
        builder_.emitRaw("    " + varSlot + " =l alloc8 8\n");
        builder_.emitRaw("    storel 0, " + varSlot + "\n");
        registerMethodParam(loopVarName, varSlot, FasterBASIC::BaseType::LONG);
    }

    // Initialise loop variable with start value (widened to LONG for 8-byte slot)
    std::string startVal = emitExpressionAs(stmt->start.get(), FasterBASIC::BaseType::LONG);
    storeVariable(loopVarName, startVal);

    // Evaluate end value and step, store in temp slots (widened to LONG)
    std::string endVal = emitExpressionAs(stmt->end.get(), FasterBASIC::BaseType::LONG);
    std::string endSlot = "%mfor_end_" + std::to_string(id);
    builder_.emitRaw("    " + endSlot + " =l alloc8 8\n");
    builder_.emitRaw("    storel " + endVal + ", " + endSlot + "\n");

    std::string stepVal;
    std::string stepSlot = "%mfor_step_" + std::to_string(id);
    builder_.emitRaw("    " + stepSlot + " =l alloc8 8\n");
    if (stmt->step) {
        stepVal = emitExpressionAs(stmt->step.get(), FasterBASIC::BaseType::LONG);
    } else {
        stepVal = "1";
    }
    builder_.emitRaw("    storel " + stepVal + ", " + stepSlot + "\n");

    // --- Condition check ---
    builder_.emitJump(condLabel);
    builder_.emitLabel(condLabel);

    std::string curVal  = loadVariable(loopVarName);
    std::string limVal  = builder_.newTemp();
    builder_.emitRaw("    " + limVal + " =l loadl " + endSlot + "\n");
    std::string stpVal  = builder_.newTemp();
    builder_.emitRaw("    " + stpVal + " =l loadl " + stepSlot + "\n");

    // If step > 0: continue while curVal <= limVal
    // If step < 0: continue while curVal >= limVal
    std::string stepNeg = builder_.newTemp();
    builder_.emitRaw("    " + stepNeg + " =w csltl " + stpVal + ", 0\n");

    std::string cmpGt = builder_.newTemp();
    builder_.emitRaw("    " + cmpGt + " =w csgtl " + curVal + ", " + limVal + "\n");
    std::string posCond = builder_.newTemp();
    // For positive step: NOT (cur > lim)  →  cur <= lim
    builder_.emitRaw("    " + posCond + " =w ceqw " + cmpGt + ", 0\n");

    std::string cmpLt = builder_.newTemp();
    builder_.emitRaw("    " + cmpLt + " =w csltl " + curVal + ", " + limVal + "\n");
    std::string negCond = builder_.newTemp();
    // For negative step: NOT (cur < lim)  →  cur >= lim
    builder_.emitRaw("    " + negCond + " =w ceqw " + cmpLt + ", 0\n");

    // Select condition based on step sign
    // cond = stepNeg ? negCond : posCond
    std::string selLabel1 = prefix + "_stepsel_neg";
    std::string selLabel2 = prefix + "_stepsel_pos";
    std::string selLabel3 = prefix + "_stepsel_done";
    std::string condSlot  = "%mfor_cond_" + std::to_string(id);
    builder_.emitRaw("    " + condSlot + " =l alloc4 4\n");
    builder_.emitRaw("    jnz " + stepNeg + ", @" + selLabel1 + ", @" + selLabel2 + "\n");

    builder_.emitLabel(selLabel1);
    builder_.emitRaw("    storew " + negCond + ", " + condSlot + "\n");
    builder_.emitJump(selLabel3);

    builder_.emitLabel(selLabel2);
    builder_.emitRaw("    storew " + posCond + ", " + condSlot + "\n");
    builder_.emitJump(selLabel3);

    builder_.emitLabel(selLabel3);
    std::string finalCond = builder_.newTemp();
    builder_.emitRaw("    " + finalCond + " =w loadw " + condSlot + "\n");

    builder_.emitRaw("    jnz " + finalCond + ", @" + bodyLabel + ", @" + endLabel + "\n");

    // --- Body ---
    builder_.emitLabel(bodyLabel);
    // SAMM: Only emit loop-iteration scope if the body contains DIM
    // statements — avoids overhead on simple loops that don't allocate.
    bool forNeedsSammScope = bodyContainsDim(stmt->body);
    if (forNeedsSammScope && isSAMMEnabled()) {
        builder_.emitComment("SAMM: Enter FOR loop-iteration scope");
        builder_.emitCall("", "", "samm_enter_scope", "");
    }
    for (const auto& s : stmt->body) {
        if (s) emitStatement(s.get());
    }
    if (forNeedsSammScope && isSAMMEnabled()) {
        builder_.emitComment("SAMM: Exit FOR loop-iteration scope");
        builder_.emitCall("", "", "samm_exit_scope", "");
    }
    builder_.emitJump(incrLabel);

    // --- Increment ---
    builder_.emitLabel(incrLabel);
    std::string cur2 = loadVariable(loopVarName);
    std::string stp2 = builder_.newTemp();
    builder_.emitRaw("    " + stp2 + " =l loadl " + stepSlot + "\n");
    std::string next = builder_.newTemp();
    builder_.emitRaw("    " + next + " =l add " + cur2 + ", " + stp2 + "\n");
    storeVariable(loopVarName, next);
    builder_.emitJump(condLabel);

    // --- End ---
    builder_.emitLabel(endLabel);
}

void ASTEmitter::emitWhileDirect(const FasterBASIC::WhileStatement* stmt) {
    if (!stmt) return;

    int id = builder_.getNextLabelId();
    std::string prefix    = "mwhile_" + std::to_string(id);
    std::string condLabel = prefix + "_cond";
    std::string bodyLabel = prefix + "_body";
    std::string endLabel  = prefix + "_end";

    builder_.emitComment("WHILE (direct, method body)");

    // --- Condition ---
    builder_.emitJump(condLabel);
    builder_.emitLabel(condLabel);
    std::string condVal = emitExpression(stmt->condition.get());
    FasterBASIC::BaseType condType = getExpressionType(stmt->condition.get());

    std::string condW;
    if (condType == FasterBASIC::BaseType::DOUBLE || condType == FasterBASIC::BaseType::SINGLE) {
        condW = builder_.newTemp();
        std::string zero = builder_.newTemp();
        if (condType == FasterBASIC::BaseType::DOUBLE) {
            builder_.emitRaw("    " + zero + " =d copy d_0.0\n");
            builder_.emitRaw("    " + condW + " =w cned " + condVal + ", " + zero + "\n");
        } else {
            builder_.emitRaw("    " + zero + " =s copy s_0.0\n");
            builder_.emitRaw("    " + condW + " =w cnes " + condVal + ", " + zero + "\n");
        }
    } else if (condType == FasterBASIC::BaseType::LONG || condType == FasterBASIC::BaseType::STRING) {
        condW = builder_.newTemp();
        builder_.emitRaw("    " + condW + " =w cnel " + condVal + ", 0\n");
    } else {
        condW = condVal;
    }

    builder_.emitRaw("    jnz " + condW + ", @" + bodyLabel + ", @" + endLabel + "\n");

    // --- Body ---
    builder_.emitLabel(bodyLabel);
    // SAMM: Only emit loop-iteration scope if the body contains DIM
    // statements — avoids overhead on simple loops that don't allocate.
    bool whileNeedsSammScope = bodyContainsDim(stmt->body);
    if (whileNeedsSammScope && isSAMMEnabled()) {
        builder_.emitComment("SAMM: Enter WHILE loop-iteration scope");
        builder_.emitCall("", "", "samm_enter_scope", "");
    }
    for (const auto& s : stmt->body) {
        if (s) emitStatement(s.get());
    }
    if (whileNeedsSammScope && isSAMMEnabled()) {
        builder_.emitComment("SAMM: Exit WHILE loop-iteration scope");
        builder_.emitCall("", "", "samm_exit_scope", "");
    }
    builder_.emitJump(condLabel);

    // --- End ---
    builder_.emitLabel(endLabel);
}

} // namespace fbc