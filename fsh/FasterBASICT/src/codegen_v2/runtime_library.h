#ifndef RUNTIME_LIBRARY_H
#define RUNTIME_LIBRARY_H

#include <string>
#include <vector>
#include "qbe_builder.h"
#include "type_manager.h"

namespace fbc {

/**
 * RuntimeLibrary - Runtime function call wrappers
 * 
 * Responsible for:
 * - Intrinsic function calls (PRINT, CHR$, LEN, MID$, etc.)
 * - Array operations (bounds checking, descriptor access)
 * - String operations (concat, slice, assignment)
 * - Math and I/O functions
 * 
 * This component knows how to emit QBE IL to call FasterBASIC runtime
 * functions (implemented in C in runtime_c/).
 */
class RuntimeLibrary {
public:
    RuntimeLibrary(QBEBuilder& builder, TypeManager& typeManager);
    ~RuntimeLibrary() = default;

    // === Print/Output ===
    
    /**
     * Emit a PRINT call for an integer
     * @param value Value to print (temporary or constant)
     * @param valueType Type of the value (to determine if sign-extension needed)
     */
    void emitPrintInt(const std::string& value, BasicType valueType);
    
    /**
     * Emit a PRINT call for a float (SINGLE)
     * @param value Value to print
     */
    void emitPrintFloat(const std::string& value);
    
    /**
     * Emit a PRINT call for a double
     * @param value Value to print
     */
    void emitPrintDouble(const std::string& value);
    
    /**
     * Emit a PRINT call for a string
     * @param stringPtr String descriptor pointer
     */
    void emitPrintString(const std::string& stringPtr);
    
    /**
     * Emit a newline
     */
    void emitPrintNewline();
    
    /**
     * Emit a tab
     */
    void emitPrintTab();

    // === String Operations ===
    
    /**
     * Emit a string concatenation call
     * @param dest Destination temporary (receives new string descriptor)
     * @param left Left string descriptor
     * @param right Right string descriptor
     * @return Temporary holding result
     */
    std::string emitStringConcat(const std::string& left, const std::string& right);
    
    /**
     * Emit a LEN() call
     * @param stringPtr String descriptor pointer
     * @return Temporary holding length (w)
     */
    std::string emitStringLen(const std::string& stringPtr);
    
    /**
     * Emit a CHR$() call
     * @param charCode Character code (w)
     * @return Temporary holding string descriptor (l)
     */
    std::string emitChr(const std::string& charCode);
    
    /**
     * Emit an ASC() call
     * @param stringPtr String descriptor pointer
     * @return Temporary holding character code (w)
     */
    std::string emitAsc(const std::string& stringPtr);
    
    /**
     * Emit a MID$() call
     * @param stringPtr String descriptor pointer
     * @param start Start position (1-based)
     * @param length Length (optional, empty for "to end")
     * @return Temporary holding substring descriptor
     */
    std::string emitMid(const std::string& stringPtr, const std::string& start, 
                       const std::string& length = "");
    
    /**
     * Emit a LEFT$() call
     * @param stringPtr String descriptor pointer
     * @param count Number of characters
     * @return Temporary holding substring descriptor
     */
    std::string emitLeft(const std::string& stringPtr, const std::string& count);
    
    /**
     * Emit a RIGHT$() call
     * @param stringPtr String descriptor pointer
     * @param count Number of characters
     * @return Temporary holding substring descriptor
     */
    std::string emitRight(const std::string& stringPtr, const std::string& count);
    
    /**
     * Emit an UCASE$() call (convert to uppercase)
     * @param stringPtr String descriptor pointer
     * @return Temporary holding uppercase string descriptor
     */
    std::string emitUCase(const std::string& stringPtr);
    
    /**
     * Emit an LCASE$() call (convert to lowercase)
     * @param stringPtr String descriptor pointer
     * @return Temporary holding lowercase string descriptor
     */
    std::string emitLCase(const std::string& stringPtr);
    
    /**
     * Emit a string comparison call
     * @param left Left string descriptor
     * @param right Right string descriptor
     * @return Temporary holding comparison result (w): -1, 0, or 1
     */
    std::string emitStringCompare(const std::string& left, const std::string& right);
    
    /**
     * Emit a string assignment (copies string)
     * @param dest Destination string descriptor pointer
     * @param src Source string descriptor pointer
     */
    void emitStringAssign(const std::string& dest, const std::string& src);
    
    /**
     * Emit a string literal load
     * @param stringConstant String constant name (e.g., "$str_0")
     * @return Temporary holding string descriptor (l)
     */
    std::string emitStringLiteral(const std::string& stringConstant);
    
    // === String Lifecycle Management ===
    
    /**
     * Emit a string clone call (deep copy with new refcount)
     * @param stringPtr String descriptor pointer to clone
     * @return Temporary holding new cloned string descriptor (l)
     */
    std::string emitStringClone(const std::string& stringPtr);
    
    /**
     * Emit a string retain call (increment refcount)
     * @param stringPtr String descriptor pointer to retain
     * @return Same pointer (for chaining)
     */
    std::string emitStringRetain(const std::string& stringPtr);
    
    /**
     * Emit a string release call (decrement refcount, free if 0)
     * @param stringPtr String descriptor pointer to release
     */
    void emitStringRelease(const std::string& stringPtr);

    // === Array Operations ===
    
    /**
     * Emit array element access
     * @param arrayBase Base pointer to array data
     * @param index Index temporary
     * @param elementType Type of array elements
     * @return Temporary holding element address
     */
    std::string emitArrayAccess(const std::string& arrayBase, const std::string& index,
                                BasicType elementType);
    
    /**
     * Emit array bounds check
     * @param index Index to check
     * @param lowerBound Lower bound (inclusive)
     * @param upperBound Upper bound (inclusive)
     */
    void emitArrayBoundsCheck(const std::string& index, const std::string& lowerBound,
                             const std::string& upperBound);
    
    /**
     * Emit array allocation
     * @param elementType Type of elements
     * @param totalSize Total number of elements
     * @return Temporary holding pointer to allocated array
     */
    std::string emitArrayAlloc(BasicType elementType, const std::string& totalSize);

    // === Math Functions ===
    
    /**
     * Emit ABS() call
     * @param value Value (integer or float)
     * @param valueType Type of value
     * @return Temporary holding absolute value
     */
    std::string emitAbs(const std::string& value, BasicType valueType);
    
    /**
     * Emit SQR() call (square root)
     * @param value Value (float or double)
     * @return Temporary holding square root
     */
    std::string emitSqr(const std::string& value, BasicType valueType);
    
    /**
     * Emit SIN() call
     * @param value Angle in radians (float or double)
     * @return Temporary holding sine
     */
    std::string emitSin(const std::string& value, BasicType valueType);
    
    /**
     * Emit COS() call
     * @param value Angle in radians (float or double)
     * @return Temporary holding cosine
     */
    std::string emitCos(const std::string& value, BasicType valueType);
    
    /**
     * Emit TAN() call
     * @param value Angle in radians (float or double)
     * @return Temporary holding tangent
     */
    std::string emitTan(const std::string& value, BasicType valueType);
    
    /**
     * Emit INT() call (truncate to integer)
     * @param value Value (float or double)
     * @return Temporary holding truncated integer
     */
    std::string emitInt(const std::string& value, BasicType valueType);
    
    /**
     * Emit RND() call (random number 0.0 to 1.0)
     * @return Temporary holding random float
     */
    std::string emitRnd();
    
    /**
     * Emit TIMER call (get current time in seconds)
     * @return Temporary holding time value (double)
     */
    std::string emitTimer();

    // === Input ===
    
    /**
     * Emit INPUT for integer
     * @param dest Destination variable pointer
     */
    void emitInputInt(const std::string& dest);
    
    /**
     * Emit INPUT for float
     * @param dest Destination variable pointer
     */
    void emitInputFloat(const std::string& dest);
    
    /**
     * Emit INPUT for double
     * @param dest Destination variable pointer
     */
    void emitInputDouble(const std::string& dest);
    
    /**
     * Emit INPUT for string
     * @param dest Destination string descriptor pointer
     */
    void emitInputString(const std::string& dest);

    // === Memory/Conversion ===
    
    /**
     * Emit STR$() call (convert number to string)
     * @param value Value to convert
     * @param valueType Type of value
     * @return Temporary holding string descriptor
     */
    std::string emitStr(const std::string& value, BasicType valueType);
    
    /**
     * Emit VAL() call (convert string to number)
     * @param stringPtr String descriptor pointer
     * @return Temporary holding numeric value (double)
     */
    std::string emitVal(const std::string& stringPtr);

    // === Control Flow Helpers ===
    
    /**
     * Emit END statement (program termination)
     */
    void emitEnd();
    
    /**
     * Emit runtime error call
     * @param errorCode Error code
     * @param errorMsg Error message (string constant)
     */
    void emitRuntimeError(int errorCode, const std::string& errorMsg);

private:
    QBEBuilder& builder_;
    TypeManager& typeManager_;
    
    // Helper: emit a runtime call and return result temporary
    std::string emitRuntimeCall(const std::string& funcName, 
                               const std::string& returnType,
                               const std::string& args);
    
    // Helper: emit a runtime call with no return
    void emitRuntimeCallVoid(const std::string& funcName, const std::string& args);
};

} // namespace fbc

#endif // RUNTIME_LIBRARY_H