/* FasterBASIC Frontend Integration for QBE
 * Compiles BASIC source to QBE IL in memory using embedded compiler
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Forward declare the C++ function from fasterbasic_wrapper.cpp */
extern "C" char* compile_basic_to_qbe_string(const char *basic_path);
extern "C" void set_trace_cfg_impl(int enable);
extern "C" void set_trace_ast_impl(int enable);
extern "C" void set_trace_symbols_impl(int enable);
extern "C" void set_show_il_impl(int enable);

extern "C" {

/* Compile BASIC source file to QBE IL in memory
 * Returns: FILE* to memory buffer containing QBE IL, or NULL on error
 */
FILE* compile_basic_to_il(const char *basic_path) {
    /* Call embedded FasterBASIC compiler */
    char *qbe_il = compile_basic_to_qbe_string(basic_path);
    
    if (!qbe_il) {
        return NULL;
    }
    
    size_t len = strlen(qbe_il);
    
    /* Create a FILE* backed by its own internal buffer (buf=NULL).
     * fmemopen with a NULL buffer allocates and owns its own memory,
     * which is freed automatically when fclose() is called.
     * We write the compiled IL into it, rewind, then free the original. */
    FILE *mem_file = fmemopen(NULL, len + 1, "w+");
    if (!mem_file) {
        free(qbe_il);
        return NULL;
    }
    
    /* Write the compiled IL into the fmemopen-managed buffer */
    size_t written = fwrite(qbe_il, 1, len, mem_file);
    
    /* Free the original compiler output – mem_file has its own copy now */
    free(qbe_il);
    
    if (written != len) {
        fclose(mem_file);
        return NULL;
    }
    
    /* Rewind so the caller reads from the beginning */
    rewind(mem_file);
    
    return mem_file;
}

/* Check if filename ends with .bas or .BAS */
int is_basic_file(const char *filename) {
    size_t len = strlen(filename);
    if (len < 4) return 0;
    
    const char *ext = filename + len - 4;
    return (strcmp(ext, ".bas") == 0 || strcmp(ext, ".BAS") == 0);
}

/* Check if filename ends with .qbe or .QBE */
int is_qbe_file(const char *filename) {
    size_t len = strlen(filename);
    if (len < 4) return 0;
    
    const char *ext = filename + len - 4;
    return (strcmp(ext, ".qbe") == 0 || strcmp(ext, ".QBE") == 0);
}

/* Enable CFG tracing in the compiler */
void set_trace_cfg(int enable) {
    set_trace_cfg_impl(enable);
}

/* Enable AST tracing in the compiler */
void set_trace_ast(int enable) {
    set_trace_ast_impl(enable);
}

void set_trace_symbols(int enable) {
    set_trace_symbols_impl(enable);
}

/* Enable IL output in the compiler */
void set_show_il(int enable) {
    set_show_il_impl(enable);
}

}  // extern "C"
