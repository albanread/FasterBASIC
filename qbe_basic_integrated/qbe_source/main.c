#include "all.h"
#include "config.h"
#include <ctype.h>
#include <dirent.h>
#include <unistd.h>
#include <libgen.h>
#include <sys/stat.h>
#include <string.h>

/* FasterBASIC frontend integration */
extern FILE* compile_basic_to_il(const char *basic_path);
extern int is_basic_file(const char *filename);
extern int is_qbe_file(const char *filename);
extern void set_trace_cfg(int enable);
extern void set_trace_ast(int enable);
extern void set_trace_symbols(int enable);
extern void set_show_il(int enable);

/* Global flag for MADD fusion control */
static int enable_madd_fusion = 1;  /* Enabled by default */

/* Get the directory where this executable is located */
static char*
get_exe_dir(void)
{
	static char buf[1024];
	ssize_t len = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
	if (len == -1) {
		/* macOS doesn't have /proc/self/exe, try _NSGetExecutablePath */
		uint32_t size = sizeof(buf);
		if (_NSGetExecutablePath(buf, &size) == 0) {
			len = strlen(buf);
		} else {
			return ".";
		}
	}
	buf[len] = '\0';
	return dirname(buf);
}

/* Execute a shell command and return exit status */
static int
run_command(const char *cmd)
{
	int ret = system(cmd);
	return WIFEXITED(ret) ? WEXITSTATUS(ret) : -1;
}

Target T;

char debug['Z'+1] = {
	['P'] = 0, /* parsing */
	['M'] = 0, /* memory optimization */
	['N'] = 0, /* ssa construction */
	['C'] = 0, /* copy elimination */
	['F'] = 0, /* constant folding */
	['K'] = 0, /* if-conversion */
	['A'] = 0, /* abi lowering */
	['I'] = 0, /* instruction selection */
	['L'] = 0, /* liveness */
	['S'] = 0, /* spilling */
	['R'] = 0, /* reg. allocation */
};

extern Target T_amd64_sysv;
extern Target T_amd64_apple;
extern Target T_arm64;
extern Target T_arm64_apple;
extern Target T_rv64;

static Target *tlist[] = {
	&T_amd64_sysv,
	&T_amd64_apple,
	&T_arm64,
	&T_arm64_apple,
	&T_rv64,
	0
};
static FILE *outf;
static int dbg;

static void
data(Dat *d)
{
	if (dbg)
		return;
	emitdat(d, outf);
	if (d->type == DEnd) {
		fputs("/* end data */\n\n", outf);
		freeall();
	}
}

static void
func(Fn *fn)
{
	uint n;

	if (dbg)
		fprintf(stderr, "**** Function %s ****", fn->name);
	if (debug['P']) {
		fprintf(stderr, "\n> After parsing:\n");
		printfn(fn, stderr);
	}
	T.abi0(fn);
	fillcfg(fn);
	filluse(fn);
	promote(fn);
	filluse(fn);
	ssa(fn);
	filluse(fn);
	ssacheck(fn);
	fillalias(fn);
	loadopt(fn);
	filluse(fn);
	fillalias(fn);
	coalesce(fn);
	filluse(fn);
	filldom(fn);
	ssacheck(fn);
	gvn(fn);
	fillcfg(fn);
	simplcfg(fn);
	filluse(fn);
	filldom(fn);
	gcm(fn);
	filluse(fn);
	ssacheck(fn);
	if (T.cansel) {
		ifconvert(fn);
		fillcfg(fn);
		filluse(fn);
		filldom(fn);
		ssacheck(fn);
	}
	T.abi1(fn);
	simpl(fn);
	fillcfg(fn);
	filluse(fn);
	T.isel(fn);
	fillcfg(fn);
	filllive(fn);
	fillloop(fn);
	fillcost(fn);
	spill(fn);
	rega(fn);
	fillcfg(fn);
	simpljmp(fn);
	fillcfg(fn);
	filllive(fn); /* re-run after regalloc so b->out has physical regs for emitter */
	assert(fn->rpo[0] == fn->start);
	for (n=0;; n++)
		if (n == fn->nblk-1) {
			fn->rpo[n]->link = 0;
			break;
		} else
			fn->rpo[n]->link = fn->rpo[n+1];
	if (!dbg) {
		T.emitfn(fn, outf);
		fprintf(outf, "/* end function %s */\n\n", fn->name);
	} else
		fprintf(stderr, "\n");
	freeall();
}

static void
dbgfile(char *fn)
{
	emitdbgfile(fn, outf);
}

int
main(int ac, char *av[])
{
	Target **t;
	FILE *inf;
	char *f = NULL, *sep, *output_file = NULL;
	char *runtime_dir = NULL;
	char temp_asm[256] = {0};
	char cmd[4096];
	int compile_only = 0, is_basic = 0, is_qbe = 0, il_only = 0;
	int need_linking = 0;
	int trace_cfg = 0;
	int trace_ast = 0;
	int trace_symbols = 0;
	int debug_mode = 0;
	int i;
	char *target_name = NULL;
	char *debug_flags = NULL;
	char default_output[256];

	T = Deftgt;
	outf = stdout;
	
	/* Custom argument parser - handles options in any position */
	for (i = 1; i < ac; i++) {
		char *arg = av[i];
		
		/* Long options */
		if (strcmp(arg, "--enable-madd-fusion") == 0) {
			enable_madd_fusion = 1;
		} else if (strcmp(arg, "--disable-madd-fusion") == 0) {
			enable_madd_fusion = 0;
		} else if (strcmp(arg, "--debug") == 0 || strcmp(arg, "-D") == 0) {
			debug_mode = 1;
		}
		/* Short options */
		else if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
			fprintf(stderr, "%s [OPTIONS] {file.ssa, file.qbe, file.bas, -}\n", av[0]);
			fprintf(stderr, "Options can appear in any position.\n\n");
			fprintf(stderr, "Input files:\n");
			fprintf(stderr, "  %-20s FasterBASIC source (compiles to executable)\n", "file.bas");
			fprintf(stderr, "  %-20s QBE IL source (compiles to .o object file)\n", "file.qbe");
			fprintf(stderr, "  %-20s QBE IL or SSA (compiles to assembly)\n", "file.ssa");
			fprintf(stderr, "  %-20s standard input\n", "-");
			fprintf(stderr, "\nOptions:\n");
			fprintf(stderr, "  %-20s prints this help\n", "-h, --help");
			fprintf(stderr, "  %-20s output to file\n", "-o <file>");
			fprintf(stderr, "  %-20s output IL only (stop before assembly)\n", "-i");
			fprintf(stderr, "  %-20s compile only (stop at assembly)\n", "-c");
			fprintf(stderr, "  %-20s trace CFG and exit (BASIC files only)\n", "-G");
			fprintf(stderr, "  %-20s trace AST and exit (BASIC files only)\n", "-A");
			fprintf(stderr, "  %-20s trace symbols and exit (BASIC files only)\n", "-S");
			fprintf(stderr, "  %-20s enable debug output\n", "-D, --debug");
			fprintf(stderr, "  %-20s enable MADD/MSUB fusion (default)\n", "--enable-madd-fusion");
			fprintf(stderr, "  %-20s disable MADD/MSUB fusion\n", "--disable-madd-fusion");
			fprintf(stderr, "  %-20s generate for target\n", "-t <target>");
			fprintf(stderr, "  %-20s dump debug information\n", "-d <flags>");
			fprintf(stderr, "\nExamples:\n");
			fprintf(stderr, "  %s program.bas              # Compile BASIC to executable 'program'\n", av[0]);
			fprintf(stderr, "  %s program.bas -o myapp     # Compile BASIC to executable 'myapp'\n", av[0]);
			fprintf(stderr, "  %s hashmap.qbe              # Compile QBE IL to 'hashmap.o'\n", av[0]);
			fprintf(stderr, "  %s hashmap.qbe -c -o out.s  # Compile QBE IL to assembly 'out.s'\n", av[0]);
			fprintf(stderr, "  %s program.bas -i           # Output QBE IL to stdout\n", av[0]);
			fprintf(stderr, "\nAvailable targets: ");
			for (t=tlist, sep=""; *t; t++, sep=", ") {
				fprintf(stderr, "%s%s", sep, (*t)->name);
				if (*t == &Deftgt)
					fputs(" (default)", stderr);
			}
			fprintf(stderr, "\n");
			exit(0);
		}
		else if (strcmp(arg, "-i") == 0) {
			il_only = 1;
		}
		else if (strcmp(arg, "-c") == 0) {
			compile_only = 1;
		}
		else if (strcmp(arg, "-G") == 0) {
			trace_cfg = 1;
		}
		else if (strcmp(arg, "-A") == 0) {
			trace_ast = 1;
		}
		else if (strcmp(arg, "-S") == 0) {
			trace_symbols = 1;
		}
		else if (strcmp(arg, "-o") == 0) {
			if (i + 1 >= ac) {
				fprintf(stderr, "error: -o requires an argument\n");
				exit(1);
			}
			output_file = av[++i];
		}
		else if (strcmp(arg, "-t") == 0) {
			if (i + 1 >= ac) {
				fprintf(stderr, "error: -t requires an argument\n");
				exit(1);
			}
			target_name = av[++i];
			if (strcmp(target_name, "?") == 0) {
				puts(T.name);
				exit(0);
			}
		}
		else if (strcmp(arg, "-d") == 0) {
			if (i + 1 >= ac) {
				fprintf(stderr, "error: -d requires an argument\n");
				exit(1);
			}
			debug_flags = av[++i];
		}
		else if (arg[0] == '-' && arg[1] != '\0') {
			fprintf(stderr, "error: unknown option '%s'\n", arg);
			fprintf(stderr, "Use -h for help\n");
			exit(1);
		}
		else {
			/* Non-option argument - the input file */
			if (f) {
				fprintf(stderr, "error: multiple input files specified\n");
				exit(1);
			}
			f = arg;
		}
	}
	
	/* Process target selection */
	if (target_name) {
		for (t=tlist;; t++) {
			if (!*t) {
				fprintf(stderr, "unknown target '%s'\n", target_name);
				exit(1);
			}
			if (strcmp(target_name, (*t)->name) == 0) {
				T = **t;
				break;
			}
		}
	}
	
	/* Process debug flags */
	if (debug_flags) {
		for (char *p = debug_flags; *p; p++) {
			if (isalpha(*p)) {
				debug[toupper(*p)] = 1;
				dbg = 1;
			}
		}
	}
	
	/* Check for input file */
	if (!f) {
		fprintf(stderr, "error: no input file specified\n");
		fprintf(stderr, "Use -h for help\n");
		exit(1);
	}
	
	/* Set trace-cfg flag before compilation */
	if (trace_cfg) {
		set_trace_cfg(1);
	}
	if (trace_ast) {
		set_trace_ast(1);
	}
	if (trace_symbols) {
		set_trace_symbols(1);
	}
	
	/* Set show-il flag if -i was specified */
	if (il_only) {
		set_show_il(1);
	}
	
	/* Set debug mode environment variable for parser/semantic analyzer */
	if (debug_mode) {
		setenv("FASTERBASIC_DEBUG", "1", 1);
	}
	
	/* Set MADD fusion environment variable for ARM64 backend */
	if (enable_madd_fusion) {
		setenv("ENABLE_MADD_FUSION", "1", 1);
	} else {
		setenv("ENABLE_MADD_FUSION", "0", 1);
	}

	/* Process the input file */
	if (strcmp(f, "-") == 0) {
		inf = stdin;
		f = "-";
		is_basic = 0;
		is_qbe = 0;
	} else {
		is_basic = is_basic_file(f);
		is_qbe = is_qbe_file(f);
		
		if (is_basic) {
			inf = compile_basic_to_il(f);
			if (!inf) {
				fprintf(stderr, "failed to compile BASIC file '%s'\n", f);
				exit(1);
			}
			
			/* If trace-cfg was enabled, compilation stops after CFG dump */
			if (trace_cfg) {
				fclose(inf);
				exit(0);
			}
		} else {
			/* Regular QBE IL file or SSA file */
			inf = fopen(f, "r");
			if (!inf) {
				fprintf(stderr, "cannot open '%s'\n", f);
				exit(1);
			}
		}
	}
	
	/* Decide output strategy:
	 * -i: Output IL only to -o or stdout
	 * -c: Output assembly to -o or stdout
	 * BASIC + -o (no flags): Create executable (temp asm, then link)
	 * Otherwise: Output assembly to stdout
	 */
	
	if (il_only) {
		/* Output IL only - just copy through */
		if (output_file && strcmp(output_file, "-") != 0) {
			outf = fopen(output_file, "w");
			if (!outf) {
				fprintf(stderr, "cannot open '%s'\n", output_file);
				exit(1);
			}
		} else {
			outf = stdout;
		}
		
		char buf[4096];
		size_t n;
		while ((n = fread(buf, 1, sizeof(buf), inf)) > 0) {
			fwrite(buf, 1, n, outf);
		}
		fclose(inf);
		
		if (outf != stdout)
			fclose(outf);
			
	} else if (is_basic && !il_only) {
		/* BASIC file: compile to assembly and link to executable */
		/* Generate a default output name if not specified */
		if (!output_file) {
			/* Strip .bas extension and use as executable name */
			const char *base = strrchr(f, '/');
			base = base ? base + 1 : f;
			char *dot = strrchr(base, '.');
			if (dot && (strcmp(dot, ".bas") == 0 || strcmp(dot, ".BAS") == 0)) {
				snprintf(default_output, sizeof(default_output), "%.*s", (int)(dot - base), base);
			} else {
				snprintf(default_output, sizeof(default_output), "%s.out", base);
			}
			output_file = default_output;
		}
		
		snprintf(temp_asm, sizeof(temp_asm), "/tmp/qbe_basic_%d.s", getpid());
		outf = fopen(temp_asm, "w");
		if (!outf) {
			fprintf(stderr, "cannot create temp file '%s'\n", temp_asm);
			exit(1);
		}
		need_linking = !compile_only;
		
		parse(inf, f, dbgfile, data, func);
		fclose(inf);
		
		if (!dbg)
			T.emitfin(outf);
		fclose(outf);
		
		/* If -c was specified, copy temp asm to output file instead of linking */
		if (compile_only) {
			if (output_file && strcmp(output_file, "-") != 0) {
				/* Copy temp asm to specified output */
				snprintf(cmd, sizeof(cmd), "cp %s %s", temp_asm, output_file);
				run_command(cmd);
				unlink(temp_asm);
			} else {
				/* Output to stdout */
				FILE *asm_file = fopen(temp_asm, "r");
				if (asm_file) {
					char buf[4096];
					size_t n;
					while ((n = fread(buf, 1, sizeof(buf), asm_file)) > 0) {
						fwrite(buf, 1, n, stdout);
					}
					fclose(asm_file);
				}
				unlink(temp_asm);
			}
		}
		
	} else if (is_qbe && !il_only) {
		/* QBE file: compile to assembly or object */
		/* Generate a default output name if not specified */
		if (!output_file) {
			/* Strip .qbe extension and use .o or .s */
			const char *base = strrchr(f, '/');
			base = base ? base + 1 : f;
			char *dot = strrchr(base, '.');
			if (dot && (strcmp(dot, ".qbe") == 0 || strcmp(dot, ".QBE") == 0)) {
				if (compile_only) {
					snprintf(default_output, sizeof(default_output), "%.*s.s", (int)(dot - base), base);
				} else {
					snprintf(default_output, sizeof(default_output), "%.*s.o", (int)(dot - base), base);
				}
			} else {
				snprintf(default_output, sizeof(default_output), "%s.o", base);
			}
			output_file = default_output;
		}
		
		if (compile_only) {
			/* Generate assembly only */
			if (strcmp(output_file, "-") != 0) {
				outf = fopen(output_file, "w");
				if (!outf) {
					fprintf(stderr, "cannot open '%s'\n", output_file);
					exit(1);
				}
			} else {
				outf = stdout;
			}
			
			parse(inf, f, dbgfile, data, func);
			fclose(inf);
			
			if (!dbg)
				T.emitfin(outf);
				
			if (outf != stdout)
				fclose(outf);
		} else {
			/* Generate assembly and then assemble to object */
			snprintf(temp_asm, sizeof(temp_asm), "/tmp/qbe_%d.s", getpid());
			outf = fopen(temp_asm, "w");
			if (!outf) {
				fprintf(stderr, "cannot create temp file '%s'\n", temp_asm);
				exit(1);
			}
			
			parse(inf, f, dbgfile, data, func);
			fclose(inf);
			
			if (!dbg)
				T.emitfin(outf);
			fclose(outf);
			
			/* Assemble to object file */
			snprintf(cmd, sizeof(cmd), "cc -c -o %s %s", output_file, temp_asm);
			int ret = run_command(cmd);
			unlink(temp_asm);
			
			if (ret != 0) {
				fprintf(stderr, "assembly failed\n");
				exit(1);
			}
		}
		
	} else {
		/* Regular QBE processing - output assembly */
		if (output_file && strcmp(output_file, "-") != 0) {
			outf = fopen(output_file, "w");
			if (!outf) {
				fprintf(stderr, "cannot open '%s'\n", output_file);
				exit(1);
			}
		} else {
			outf = stdout;
		}
		
		parse(inf, f, dbgfile, data, func);
		fclose(inf);
		
		if (!dbg)
			T.emitfin(outf);
			
		if (outf != stdout)
			fclose(outf);
	}

	/* If we need to link (BASIC + -o without -i or -c) */
	if (need_linking && temp_asm[0]) {
		/* Find runtime library - try multiple locations */
		char runtime_path[1024];
		char *search_paths[] = {
			"runtime",                         /* Local runtime directory (preferred) */
			"qbe_basic_integrated/runtime",    /* From project root */
			"../runtime",                      /* From qbe_basic_integrated/ when in project root */
			"fsh/FasterBASICT/runtime_c",      /* Development location from project root */
			"../fsh/FasterBASICT/runtime_c",   /* Development location from qbe_basic_integrated/ */
			NULL
		};
		
		/* Find runtime directory */
		for (char **search = search_paths; *search; search++) {
			if (access(*search, R_OK) == 0) {
				runtime_dir = *search;
				break;
			}
		}
		
		if (!runtime_dir) {
			fprintf(stderr, "Error: runtime library not found\n");
			fprintf(stderr, "Searched:\n");
			for (char **search = search_paths; *search; search++) {
				fprintf(stderr, "  %s\n", *search);
			}
			unlink(temp_asm);
			exit(1);
		}
		
		/* Find qbe_modules directory (for hashmap.o and other runtime objects) */
		char *qbe_modules_dir = NULL;
		char *qbe_modules_search_paths[] = {
			"qbe_modules",                         /* From executable directory */
			"qbe_basic_integrated/qbe_modules",    /* From project root */
			"../qbe_modules",                      /* From qbe_basic_integrated/ */
			NULL
		};
		
		for (char **search = qbe_modules_search_paths; *search; search++) {
			if (access(*search, R_OK) == 0) {
				qbe_modules_dir = *search;
				break;
			}
		}
		
		if (!qbe_modules_dir && !dbg) {
			fprintf(stderr, "Warning: qbe_modules directory not found (runtime objects like hashmap.o will not be linked)\n");
		}
		
		/* Runtime source files */
		char *runtime_files[] = {
			"basic_runtime.c",
			"io_ops.c",
			"io_ops_format.c",
			"math_ops.c",
			"string_ops.c",
			"string_pool.c",
			"string_utf32.c",
			"conversion_ops.c",
			"array_ops.c",
			"array_descriptor_runtime.c",
			"memory_mgmt.c",
			"basic_data.c",
			"plugin_context_runtime.c",
			"class_runtime.c",
			"samm_core.c",
			"list_ops.c",
			NULL
		};
		
		/* Check if we have precompiled runtime objects */
		char obj_dir[1024];
		snprintf(obj_dir, sizeof(obj_dir), "%s/.obj", runtime_dir);
		
		int need_rebuild = 0;
		if (access(obj_dir, R_OK) != 0) {
			/* Create object directory if it doesn't exist */
			snprintf(cmd, sizeof(cmd), "mkdir -p %s", obj_dir);
			run_command(cmd);
			need_rebuild = 1;
		} else {
			/* Check if any source is newer than its object */
			for (char **src = runtime_files; *src; src++) {
				char src_path[1024], obj_path[1024];
				snprintf(src_path, sizeof(src_path), "%s/%s", runtime_dir, *src);
				snprintf(obj_path, sizeof(obj_path), "%s/.obj/%s.o", runtime_dir, *src);
				
				/* If object doesn't exist or source is newer, rebuild */
				struct stat src_stat, obj_stat;
				if (stat(obj_path, &obj_stat) != 0 ||
				    (stat(src_path, &src_stat) == 0 && src_stat.st_mtime > obj_stat.st_mtime)) {
					need_rebuild = 1;
					break;
				}
			}
		}
		
		/* Build runtime objects if needed */
		if (need_rebuild) {
			if (!dbg) {
				fprintf(stderr, "Building runtime library...\n");
			}
			
			for (char **src = runtime_files; *src; src++) {
				char src_path[1024], obj_path[1024];
				snprintf(src_path, sizeof(src_path), "%s/%s", runtime_dir, *src);
				snprintf(obj_path, sizeof(obj_path), "%s/.obj/%s.o", runtime_dir, *src);
				
				/* Compile source to object */
				snprintf(cmd, sizeof(cmd), "cc -O2 -c %s -o %s 2>&1 | grep -v warning || true", 
					src_path, obj_path);
				
				int ret = run_command(cmd);
				if (ret != 0) {
					fprintf(stderr, "Failed to compile %s\n", *src);
					unlink(temp_asm);
					exit(1);
				}
			}
		}
		
		/* Build link command with precompiled runtime objects */
		char obj_list[4096] = "";
		for (char **src = runtime_files; *src; src++) {
			char obj_path[256];
			snprintf(obj_path, sizeof(obj_path), "%s/.obj/%s.o ", runtime_dir, *src);
			size_t current_len = strlen(obj_list);
			size_t path_len = strlen(obj_path);
			if (current_len + path_len + 1 < sizeof(obj_list)) {
				strcat(obj_list, obj_path);
			} else {
				fprintf(stderr, "Error: runtime object list too long\n");
				unlink(temp_asm);
				exit(1);
			}
		}
		
		/* Add all .o files from qbe_modules if directory was found */
		char qbe_modules_objs[2048] = "";
		if (qbe_modules_dir) {
			/* Build list of all .o files in qbe_modules directory */
			char find_cmd[1024];
			snprintf(find_cmd, sizeof(find_cmd), "find %s -maxdepth 1 -name '*.o' 2>/dev/null", qbe_modules_dir);
			
			FILE *find_pipe = popen(find_cmd, "r");
			if (find_pipe) {
				char obj_path[512];
				while (fgets(obj_path, sizeof(obj_path), find_pipe)) {
					/* Remove newline */
					obj_path[strcspn(obj_path, "\n")] = 0;
					
					/* Add to list if there's space */
					size_t current_len = strlen(qbe_modules_objs);
					size_t path_len = strlen(obj_path);
					if (current_len + path_len + 2 < sizeof(qbe_modules_objs)) {
						if (current_len > 0) {
							strcat(qbe_modules_objs, " ");
						}
						strcat(qbe_modules_objs, obj_path);
					}
				}
				pclose(find_pipe);
				
				if (!dbg && qbe_modules_objs[0]) {
					fprintf(stderr, "Linking with runtime objects: %s\n", qbe_modules_objs);
				}
			}
		}
		
		/* Find and link plugin libraries from plugins/enabled directory */
		char plugin_libs[2048] = "";
		char *plugin_search_paths[] = {
			"plugins/enabled",
			"../plugins/enabled",
			NULL
		};
		
		for (char **plugin_path = plugin_search_paths; *plugin_path; plugin_path++) {
			if (access(*plugin_path, R_OK) == 0) {
				/* Scan for .so, .dylib, or .dll files */
				DIR *dir = opendir(*plugin_path);
				if (dir) {
					struct dirent *entry;
					while ((entry = readdir(dir)) != NULL) {
						if (entry->d_type == DT_REG || entry->d_type == DT_LNK) {
							char *name = entry->d_name;
							size_t len = strlen(name);
							
							/* Check for plugin extension */
							int is_plugin = 0;
							if (len > 3 && strcmp(name + len - 3, ".so") == 0) is_plugin = 1;
							if (len > 6 && strcmp(name + len - 6, ".dylib") == 0) is_plugin = 1;
							if (len > 4 && strcmp(name + len - 4, ".dll") == 0) is_plugin = 1;
							
							if (is_plugin) {
								char full_path[1024];
								snprintf(full_path, sizeof(full_path), "%s/%s", *plugin_path, name);
								
								/* Add to plugin libs string */
								size_t current_len = strlen(plugin_libs);
								size_t path_len = strlen(full_path);
								if (current_len + path_len + 2 < sizeof(plugin_libs)) {
									if (current_len > 0) strcat(plugin_libs, " ");
									strcat(plugin_libs, full_path);
									
									if (!dbg) {
										fprintf(stderr, "Linking plugin: %s\n", name);
									}
								}
							}
						}
					}
					closedir(dir);
				}
				break;  /* Found plugins directory, stop searching */
			}
		}
		
		/* Build final link command */
		/* Link with -lpthread for SAMM background cleanup worker thread */
		if (plugin_libs[0] && qbe_modules_objs[0]) {
			snprintf(cmd, sizeof(cmd), "cc -O2 %s %s %s %s -lpthread -o %s", temp_asm, obj_list, qbe_modules_objs, plugin_libs, output_file);
		} else if (plugin_libs[0]) {
			snprintf(cmd, sizeof(cmd), "cc -O2 %s %s %s -lpthread -o %s", temp_asm, obj_list, plugin_libs, output_file);
		} else if (qbe_modules_objs[0]) {
			snprintf(cmd, sizeof(cmd), "cc -O2 %s %s %s -lpthread -o %s", temp_asm, obj_list, qbe_modules_objs, output_file);
		} else {
			snprintf(cmd, sizeof(cmd), "cc -O2 %s %s -lpthread -o %s", temp_asm, obj_list, output_file);
		}
		
		int ret = run_command(cmd);
		unlink(temp_asm);
		
		if (ret != 0) {
			fprintf(stderr, "assembly/linking failed\n");
			exit(1);
		}
		
		if (!dbg) {
			fprintf(stderr, "Compiled %s -> %s\n", f, output_file);
		}
	}

	exit(0);
}