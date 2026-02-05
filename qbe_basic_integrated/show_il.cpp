/* Simple utility to show QBE IL from BASIC source
 * Usage: ./show_il input.bas
 */

#include <iostream>
#include <cstdlib>

extern "C" char* compile_basic_to_qbe_string(const char *basic_path);

int main(int argc, char *argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " input.bas\n";
        return 1;
    }
    
    char *qbe_il = compile_basic_to_qbe_string(argv[1]);
    
    if (!qbe_il) {
        std::cerr << "Compilation failed\n";
        return 1;
    }
    
    std::cout << qbe_il;
    
    free(qbe_il);
    return 0;
}