//
// fbc_qbe.cpp
// FasterBASIC QBE Compiler
// Compiles BASIC source code to native executables via QBE backend
//

#include "fasterbasic_lexer.h"
#include "fasterbasic_parser.h"
#include "fasterbasic_semantic.h"
#include "fasterbasic_cfg.h"
#include "fasterbasic_qbe_codegen.h"
#include "fasterbasic_data_preprocessor.h"
#include "fasterbasic_ast_dump.h"
#include "modular_commands.h"
#include "command_registry_core.h"
#include "runtime_objects.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <cstring>
#include <chrono>
#include <cstdlib>
#include <unistd.h>
#include <sys/wait.h>
#include <libgen.h>
#include <iomanip>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

using namespace FasterBASIC;
using namespace FasterBASIC::ModularCommands;

void initializeFBCCommandRegistry() {
    // Initialize global registry with core commands for compiler use
    CommandRegistry& registry = getGlobalCommandRegistry();
    
    // Add core BASIC commands and functions
    CoreCommandRegistry::registerCoreCommands(registry);
    CoreCommandRegistry::registerCoreFunctions(registry);
    
    // Mark registry as initialized to prevent clearing
    markGlobalRegistryInitialized();
}

void printUsage(const char* programName) {
    std::cerr << "FasterBASIC QBE Compiler - Compiles BASIC to native code\n\n";
    std::cerr << "Usage: " << programName << " [options] <input.bas>\n\n";
    std::cerr << "Options:\n";
    std::cerr << "  -o <file>      Output executable file (default: a.out)\n";
    std::cerr << "  -c             Compile only, don't link (generates .o file)\n";
    std::cerr << "  --run          Compile and run the program immediately\n";
    std::cerr << "  --emit-qbe     Emit QBE IL (.qbe) file only and exit\n";
    std::cerr << "  --emit-asm     Emit assembly (.s) file and exit\n";
    std::cerr << "  -v, --verbose  Verbose output (compilation stats)\n";
    std::cerr << "  --trace-ast    Dump AST structure after parsing\n";
    std::cerr << "  --trace-cfg    Dump CFG structure after building\n";
    std::cerr << "  -h, --help     Show this help message\n";
    std::cerr << "  --profile      Show detailed timing for each compilation phase\n";
    std::cerr << "  --keep-temps   Keep intermediate files (.qbe, .s)\n";
    std::cerr << "  --enable-madd-fusion   Enable MADD/MSUB fusion optimization (default)\n";
    std::cerr << "  --disable-madd-fusion  Disable MADD/MSUB fusion optimization\n";
    std::cerr << "\nTarget Options:\n";
    std::cerr << "  --target=<t>   Target architecture (default: auto-detect)\n";
    std::cerr << "                 amd64_apple, amd64_sysv, arm64_apple, arm64, rv64\n";
    std::cerr << "\nExamples:\n";
    std::cerr << "  " << programName << " program.bas              # Compile to a.out\n";
    std::cerr << "  " << programName << " -o myprogram prog.bas    # Compile to myprogram\n";
    std::cerr << "  " << programName << " --run prog.bas           # Compile and run immediately\n";
    std::cerr << "  " << programName << " --emit-qbe prog.bas      # Generate prog.qbe only\n";
    std::cerr << "  " << programName << " --profile prog.bas       # Show compilation phase timings\n";
    std::cerr << "  " << programName << " -c -o prog.o prog.bas    # Compile to object file\n";
}

// Get the directory where the compiler executable is located
std::string getCompilerDirectory() {
    char path[1024];
    ssize_t len = readlink("/proc/self/exe", path, sizeof(path) - 1);
    if (len == -1) {
        // Try macOS approach
        uint32_t size = sizeof(path);
        if (_NSGetExecutablePath(path, &size) == 0) {
            len = strlen(path);
        }
    }
    if (len != -1) {
        path[len] = '\0';
        char* dir = dirname(path);
        return std::string(dir);
    }
    return ".";
}

// Execute external command and return exit code
int executeCommand(const std::string& cmd, bool verbose) {
    if (verbose) {
        std::cerr << "Executing: " << cmd << "\n";
    }
    int result = system(cmd.c_str());
    if (WIFEXITED(result)) {
        return WEXITSTATUS(result);
    }
    return -1;
}

int main(int argc, char** argv) {
    // Initialize modular commands registry
    initializeFBCCommandRegistry();
    
    // Initialize runtime object registry (for HASHMAP, FILE, etc.)
    FasterBASIC::initializeRuntimeObjectRegistry();
    
    std::string inputFile;
    std::string outputFile = "a.out";
    std::string targetArch;
    bool verbose = false;
    bool emitQBE = false;
    bool emitASM = false;
    bool compileOnly = false;
    bool keepTemps = false;
    bool showProfile = false;
    bool runAfterCompile = false;
    bool traceAST = false;
    bool traceCFG = false;
    bool enableMaddFusion = true;  // Enable MADD fusion by default
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printUsage(argv[0]);
            return 0;
        } else if (strcmp(argv[i], "--version") == 0) {
            std::cerr << "BASIC Compiler v1.0.0\n";
            std::cerr << "QBE-based BASIC to native code compiler\n";
            return 0;
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = true;
        } else if (strcmp(argv[i], "-c") == 0) {
            compileOnly = true;
        } else if (strcmp(argv[i], "--run") == 0) {
            runAfterCompile = true;
        } else if (strcmp(argv[i], "--emit-qbe") == 0) {
            emitQBE = true;
        } else if (strcmp(argv[i], "--emit-asm") == 0) {
            emitASM = true;
        } else if (strcmp(argv[i], "--keep-temps") == 0) {
            keepTemps = true;
        } else if (strcmp(argv[i], "--profile") == 0) {
            showProfile = true;
            verbose = true;  // Auto-enable verbose for profiling
        } else if (strcmp(argv[i], "--trace-ast") == 0) {
            traceAST = true;
        } else if (strcmp(argv[i], "--trace-cfg") == 0) {
            traceCFG = true;
        } else if (strcmp(argv[i], "--enable-madd-fusion") == 0) {
            enableMaddFusion = true;
        } else if (strcmp(argv[i], "--disable-madd-fusion") == 0) {
            enableMaddFusion = false;
        } else if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 < argc) {
                outputFile = argv[++i];
            } else {
                std::cerr << "Error: -o requires an output filename\n";
                return 1;
            }
        } else if (strncmp(argv[i], "--target=", 9) == 0) {
            targetArch = argv[i] + 9;
        } else if (argv[i][0] == '-') {
            std::cerr << "Error: Unknown option: " << argv[i] << "\n";
            printUsage(argv[0]);
            return 1;
        } else {
            if (inputFile.empty()) {
                inputFile = argv[i];
            } else {
                std::cerr << "Error: Multiple input files specified\n";
                return 1;
            }
        }
    }
    
    if (inputFile.empty()) {
        std::cerr << "Error: No input file specified\n\n";
        printUsage(argv[0]);
        return 1;
    }
    
    try {
        auto compileStartTime = std::chrono::high_resolution_clock::now();
        auto phaseStartTime = compileStartTime;
        
        // Get compiler directory early for finding tools
        std::string compilerDir = getCompilerDirectory();
        
        // Read source file
        if (verbose) {
            std::cerr << "Reading: " << inputFile << "\n";
        }
        
        std::ifstream file(inputFile);
        if (!file.is_open()) {
            std::cerr << "Error: Cannot open file: " << inputFile << "\n";
            return 1;
        }
        
        std::string source((std::istreambuf_iterator<char>(file)), 
                          std::istreambuf_iterator<char>());
        file.close();
        
        if (verbose) {
            std::cerr << "Source size: " << source.length() << " bytes\n";
        }
        
        auto readEndTime = std::chrono::high_resolution_clock::now();
        double readMs = std::chrono::duration<double, std::milli>(readEndTime - phaseStartTime).count();
        
        // Data preprocessing
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Preprocessing DATA statements...\n";
        }
        
        DataPreprocessor dataPreprocessor;
        DataPreprocessorResult dataResult = dataPreprocessor.process(source);
        source = dataResult.cleanedSource;
        
        if (verbose && !dataResult.values.empty()) {
            std::cerr << "DATA values extracted: " << dataResult.values.size() << "\n";
        }
        
        auto dataEndTime = std::chrono::high_resolution_clock::now();
        double dataMs = std::chrono::duration<double, std::milli>(dataEndTime - phaseStartTime).count();
        
        // Lexical analysis
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Lexing...\n";
        }
        
        Lexer lexer;
        lexer.tokenize(source);
        auto tokens = lexer.getTokens();
        
        auto lexEndTime = std::chrono::high_resolution_clock::now();
        double lexMs = std::chrono::duration<double, std::milli>(lexEndTime - phaseStartTime).count();
        
        if (verbose) {
            std::cerr << "Tokens: " << tokens.size() << "\n";
        }
        
        // Parsing
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Parsing...\n";
        }
        
        // Create semantic analyzer early to get ConstantsManager
        SemanticAnalyzer semantic;
        
        // Ensure constants are loaded before parsing (for fast constant lookup)
        semantic.ensureConstantsLoaded();
        
        Parser parser;
        parser.setConstantsManager(&semantic.getConstantsManager());
        auto ast = parser.parse(tokens, inputFile);
        
        auto parseEndTime = std::chrono::high_resolution_clock::now();
        
        // Dump AST if requested
        if (traceAST && ast) {
            dumpAST(*ast, std::cerr);
        }
        double parseMs = std::chrono::duration<double, std::milli>(parseEndTime - phaseStartTime).count();
        
        // Check for parser errors - if parsing failed, don't continue
        if (!ast || parser.hasErrors()) {
            std::cerr << "\nParsing failed with errors:\n";
            for (const auto& error : parser.getErrors()) {
                std::cerr << "  " << error.toString() << "\n";
            }
            std::cerr << "Compilation aborted.\n";
            return 1;
        }
        
        // Get compiler options from OPTION statements (collected during parsing)
        const auto& compilerOptions = parser.getOptions();
        
        if (verbose) {
            std::cerr << "Program lines: " << ast->lines.size() << "\n";
            std::cerr << "Compiler options: arrayBase=" << compilerOptions.arrayBase 
                      << " stringMode=" << static_cast<int>(compilerOptions.stringMode) << "\n";
        }
        
        // Semantic analysis
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Semantic analysis...\n";
        }
        
        semantic.analyze(*ast, compilerOptions);
        
        auto semanticEndTime = std::chrono::high_resolution_clock::now();
        double semanticMs = std::chrono::duration<double, std::milli>(semanticEndTime - phaseStartTime).count();
        
        if (verbose) {
            const auto& symTable = semantic.getSymbolTable();
            size_t varCount = symTable.variables.size();
            size_t funcCount = symTable.functions.size();
            size_t labelCount = symTable.lineNumbers.size();
            std::cerr << "Symbols: " << varCount << " variables, " 
                     << funcCount << " functions, " << labelCount << " labels\n";
        }
        
        // Control flow graph
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Building CFG...\n";
        }
        
        CFGBuilder cfgBuilder;
        auto cfg = cfgBuilder.build(*ast, semantic.getSymbolTable());
        
        auto cfgEndTime = std::chrono::high_resolution_clock::now();
        
        // Dump CFG if requested
        if (traceCFG && cfg && cfg->mainCFG) {
            std::cerr << cfg->mainCFG->toString();
            
            // Also dump function CFGs if any
            for (const auto& funcName : cfg->getFunctionNames()) {
                const auto* funcCFG = cfg->getFunctionCFG(funcName);
                if (funcCFG) {
                    std::cerr << "\n=== Function: " << funcName << " ===\n";
                    std::cerr << funcCFG->toString();
                }
            }
        }
        
        double cfgMs = std::chrono::duration<double, std::milli>(cfgEndTime - phaseStartTime).count();
        
        if (verbose) {
            std::cerr << "CFG blocks: " << cfg->getBlockCount() << "\n";
        }
        
        // QBE code generation
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Generating QBE IL...\n";
        }
        
        QBECodeGenerator qbeGen;
        qbeGen.setDataValues(dataResult);  // Pass DATA values to code generator
        std::string qbeIL = qbeGen.generate(*cfg, semantic.getSymbolTable(), compilerOptions);
        
        auto qbeGenEndTime = std::chrono::high_resolution_clock::now();
        double qbeGenMs = std::chrono::duration<double, std::milli>(qbeGenEndTime - phaseStartTime).count();
        
        if (verbose) {
            std::cerr << "Generated QBE IL size: " << qbeIL.length() << " bytes\n";
        }
        
        auto compileEndTime = std::chrono::high_resolution_clock::now();
        double totalCompileMs = std::chrono::duration<double, std::milli>(compileEndTime - compileStartTime).count();
        
        // Show detailed profiling if requested
        if (showProfile) {
            std::cerr << "\n=== Compilation Phase Timing ===\n";
            std::cerr << "  File I/O:          " << std::fixed << std::setprecision(3) << readMs << " ms\n";
            std::cerr << "  Data Preprocess:   " << std::fixed << std::setprecision(3) << dataMs << " ms\n";
            std::cerr << "  Lexer:             " << std::fixed << std::setprecision(3) << lexMs << " ms\n";
            std::cerr << "  Parser:            " << std::fixed << std::setprecision(3) << parseMs << " ms\n";
            std::cerr << "  Semantic:          " << std::fixed << std::setprecision(3) << semanticMs << " ms\n";
            std::cerr << "  CFG Builder:       " << std::fixed << std::setprecision(3) << cfgMs << " ms\n";
            std::cerr << "  QBE CodeGen:       " << std::fixed << std::setprecision(3) << qbeGenMs << " ms\n";
            std::cerr << "  --------------------------------\n";
            std::cerr << "  Total Compile:     " << std::fixed << std::setprecision(3) << totalCompileMs << " ms\n";
        }
        
        // Determine base name for intermediate files
        std::string baseName = inputFile.substr(0, inputFile.find_last_of('.'));
        if (baseName.empty()) baseName = inputFile;
        
        std::string qbeFile = baseName + ".qbe";
        std::string asmFile = baseName + ".s";
        std::string objFile = compileOnly ? (outputFile.empty() ? baseName + ".o" : outputFile) : baseName + ".o";
        
        // Write QBE IL file
        if (verbose) {
            std::cerr << "\nWriting QBE IL to: " << qbeFile << "\n";
        }
        
        std::ofstream qbeOut(qbeFile);
        if (!qbeOut) {
            std::cerr << "Error: Cannot write to file: " << qbeFile << "\n";
            return 1;
        }
        qbeOut << qbeIL;
        qbeOut.close();
        
        if (emitQBE) {
            if (verbose) {
                std::cerr << "✓ QBE IL generated\n";
            }
            return 0;  // Stop here if only emitting QBE
        }
        
        // Run QBE to generate assembly
        phaseStartTime = std::chrono::high_resolution_clock::now();
        if (verbose) {
            std::cerr << "Running QBE compiler...\n";
        }
        
        // Find QBE executable - try multiple locations
        std::string qbePath;
        // First try: relative to compiler (package structure)
        std::string pkgQbe = compilerDir + "/qbe/qbe";
        if (access(pkgQbe.c_str(), X_OK) == 0) {
            qbePath = pkgQbe;
        } else if (access("qbe/qbe", X_OK) == 0) {
            qbePath = "qbe/qbe";
        } else if (access("./qbe", X_OK) == 0) {
            qbePath = "./qbe";
        } else {
            qbePath = "qbe";  // Try PATH as last resort
        }
        
        // Set environment variable to control MADD fusion in QBE backend
        if (enableMaddFusion) {
            setenv("ENABLE_MADD_FUSION", "1", 1);
        } else {
            setenv("ENABLE_MADD_FUSION", "0", 1);
        }
        
        std::string qbeCmd = qbePath + " " + qbeFile + " > " + asmFile;
        int qbeResult = executeCommand(qbeCmd, verbose);
        if (qbeResult != 0) {
            std::cerr << "Error: QBE compilation failed\n";
            std::cerr << "       Make sure QBE is installed or in the qbe/ subdirectory\n";
            return 1;
        }
        
        auto qbeEndTime = std::chrono::high_resolution_clock::now();
        double qbeMs = std::chrono::duration<double, std::milli>(qbeEndTime - phaseStartTime).count();
        
        if (showProfile) {
            std::cerr << "  QBE Compile:       " << std::fixed << std::setprecision(3) << qbeMs << " ms\n";
        }
        
        if (emitASM) {
            if (verbose) {
                std::cerr << "✓ Assembly generated\n";
            }
            if (!keepTemps) {
                unlink(qbeFile.c_str());
            }
            return 0;  // Stop here if only emitting assembly
        }
        
        // Get runtime library path - try archive first, fall back to source files
        std::string runtimeLib = compilerDir + "/runtime/basic_runtime.a";  // Package structure
        std::string runtimeSrc = compilerDir + "/runtime";  // Package structure
        bool useArchive = false;
        
        // Check if runtime library exists
        if (access(runtimeLib.c_str(), F_OK) == 0) {
            useArchive = true;
        } else {
            // Try development/build locations
            std::string altPaths[] = {
                compilerDir + "/FasterBASICT/runtime_c/basic_runtime.a",
                "FasterBASICT/runtime_c/basic_runtime.a",
                "runtime/basic_runtime.a",
                "runtime_c/basic_runtime.a"
            };
            for (const auto& path : altPaths) {
                if (access(path.c_str(), F_OK) == 0) {
                    runtimeLib = path;
                    useArchive = true;
                    break;
                }
            }
        }
        
        // If no archive, check for source files
        if (!useArchive) {
            std::string testFile = runtimeSrc + "/basic_runtime.c";
            if (access(testFile.c_str(), F_OK) != 0) {
                // Try development/build locations for source
                std::string altSrcPaths[] = {
                    compilerDir + "/FasterBASICT/runtime_c",
                    "FasterBASICT/runtime_c",
                    "runtime"
                };
                bool found = false;
                for (const auto& path : altSrcPaths) {
                    std::string test = path + std::string("/basic_runtime.c");
                    if (access(test.c_str(), F_OK) == 0) {
                        runtimeSrc = path;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    std::cerr << "Error: Runtime library not found!\n";
                    std::cerr << "       Expected archive at: " << runtimeLib << "\n";
                    std::cerr << "       Or source files at: " << runtimeSrc << "\n";
                    return 1;
                }
            }
        }
        
        // Assemble and link with clang
        phaseStartTime = std::chrono::high_resolution_clock::now();
        
        if (compileOnly) {
            // Just create object file
            if (verbose) {
                std::cerr << "Assembling to object file...\n";
            }
            std::string clangCmd = "clang -c " + asmFile + " -o " + objFile;
            int clangResult = executeCommand(clangCmd, verbose);
            if (clangResult != 0) {
                std::cerr << "Error: Assembly failed\n";
                return 1;
            }
            if (verbose) {
                std::cerr << "✓ Object file: " << objFile << "\n";
            }
        } else {
            // Link executable
            if (verbose) {
                std::cerr << "Linking executable...\n";
            }
            std::string clangCmd;
            if (useArchive) {
                clangCmd = "clang " + asmFile + " " + runtimeLib + " -lpthread -o " + outputFile;
            } else {
                // Compile runtime source files directly
                std::string runtimeFiles = 
                    runtimeSrc + "/array_ops.c " +
                    runtimeSrc + "/array_descriptor_runtime.c " +
                    runtimeSrc + "/basic_data.c " +
                    runtimeSrc + "/basic_runtime.c " +
                    runtimeSrc + "/class_runtime.c " +
                    runtimeSrc + "/conversion_ops.c " +
                    runtimeSrc + "/io_ops.c " +
                    runtimeSrc + "/io_ops_format.c " +
                    runtimeSrc + "/math_ops.c " +
                    runtimeSrc + "/memory_mgmt.c " +
                    runtimeSrc + "/plugin_context_runtime.c " +
                    runtimeSrc + "/samm_core.c " +
                    runtimeSrc + "/string_ops.c " +
                    runtimeSrc + "/string_pool.c " +
                    runtimeSrc + "/string_utf32.c";
                // Link with -lpthread for SAMM background cleanup worker thread
                clangCmd = "clang " + asmFile + " " + runtimeFiles + " -I" + runtimeSrc + " -lpthread -o " + outputFile;
            }
            int clangResult = executeCommand(clangCmd, verbose);
            if (clangResult != 0) {
                std::cerr << "Error: Linking failed\n";
                return 1;
            }
            if (verbose) {
                std::cerr << "✓ Executable: " << outputFile << "\n";
            }
        }
        
        auto linkEndTime = std::chrono::high_resolution_clock::now();
        double linkMs = std::chrono::duration<double, std::milli>(linkEndTime - phaseStartTime).count();
        
        if (showProfile) {
            std::cerr << "  Link:              " << std::fixed << std::setprecision(3) << linkMs << " ms\n";
            std::cerr << "  ================================\n";
            double totalMs = totalCompileMs + qbeMs + linkMs;
            std::cerr << "  Total Build:       " << std::fixed << std::setprecision(3) << totalMs << " ms\n";
        }
        
        // Clean up intermediate files unless --keep-temps
        if (!keepTemps) {
            if (!emitQBE) unlink(qbeFile.c_str());
            if (!emitASM) unlink(asmFile.c_str());
            if (!compileOnly) unlink(objFile.c_str());
        }
        
        if (verbose) {
            std::cerr << "\n✓ Compilation successful!\n";
        }
        
        // Run the program if --run was specified
        if (runAfterCompile && !compileOnly) {
            if (verbose) {
                std::cerr << "\nRunning: " << outputFile << "\n";
                std::cerr << "=== Program Output ===\n";
            }
            // Ensure we can execute relative paths
            std::string execCmd = outputFile;
            if (outputFile[0] != '/' && outputFile[0] != '.') {
                execCmd = "./" + outputFile;
            }
            int exitCode = system(execCmd.c_str());
            if (verbose) {
                std::cerr << "\n=== Program exited with code " << WEXITSTATUS(exitCode) << " ===\n";
            }
            return WEXITSTATUS(exitCode);
        }
        
        return 0;
        
    } catch (const std::exception& e) {
        std::cerr << "Compilation error: " << e.what() << "\n";
        return 1;
    }
}