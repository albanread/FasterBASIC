# Zed Extension Fix - Summary

## The Problem

When trying to install the FasterBASIC Zed extension as a dev extension, you encountered:
```
failed to compile grammar 'fasterbasic'

Caused by:
    grammar directory '/Users/oberon/compact_repo/fasterbasic-zed/grammars/fasterbasic' 
    already exists, but is not a git clone of 'https://github.com/albanread/FasterBASIC'
```

## Root Cause

Zed's extension builder has a specific workflow:

1. When you install a dev extension, Zed reads `extension.toml`
2. It sees the `[grammars.fasterbasic]` section pointing to a GitHub repository
3. Zed attempts to **clone** that repository into `extension_dir/grammars/fasterbasic`
4. It then compiles the Tree-sitter parser from the cloned code

**The conflict:** The `fasterbasic-zed/grammars/fasterbasic` directory already existed with 
grammar files tracked in your main repo. Zed refused to overwrite it because it wasn't a 
git clone of the specified repository.

## The Solution

Created a separate installation directory: `fasterbasic-zed-devinstall/`

This directory contains:
- ✅ `extension.toml` (with GitHub grammar reference)
- ✅ `languages/` directory (with .scm query files)
- ✅ `README.md` and `QUICKSTART.md`
- ❌ **NO** `grammars/` directory

By removing the `grammars/` directory from the extension folder, Zed can now:
1. Clone the grammar from GitHub into that location
2. Compile the parser successfully
3. Load the extension

## Installation Instructions

### Quick Start (Use This!)

1. Open Zed
2. Press `Cmd+Shift+P`
3. Type: `zed: install dev extension`
4. Select: `/Users/oberon/compact_repo/fasterbasic-zed-devinstall`
5. Wait ~30 seconds for compilation
6. Open a `.bas` file to test!

See `fasterbasic-zed-devinstall/QUICKSTART.md` for full details.

## Directory Structure

```
compact_repo/
├── fasterbasic-zed/              # Original extension (for repo)
│   ├── extension.toml
│   ├── grammars/                 # Grammar source files
│   │   └── fasterbasic/
│   │       ├── grammar.js        # Tree-sitter grammar definition
│   │       ├── src/parser.c      # Generated parser (1.5 MB)
│   │       └── ...
│   └── languages/                # Query files
│       └── fasterbasic/
│           ├── highlights.scm
│           ├── outline.scm
│           ├── indents.scm
│           └── brackets.scm
│
└── fasterbasic-zed-devinstall/   # For Zed installation (USE THIS!)
    ├── extension.toml            # Points to GitHub for grammar
    ├── languages/                # Same as above
    ├── README.md
    └── QUICKSTART.md
    └── (no grammars/ directory)  # Zed will create this
```

## How It Works

### During Installation

1. Zed reads `fasterbasic-zed-devinstall/extension.toml`
2. Sees: 
   ```toml
   [grammars.fasterbasic]
   repository = "https://github.com/albanread/FasterBASIC"
   rev = "b96430afb71f4b9da80421edbdba3484068df0e3"
   path = "fasterbasic-zed/grammars/fasterbasic"
   ```
3. Clones the repo at that commit into `fasterbasic-zed-devinstall/grammars/fasterbasic/`
4. Compiles `src/parser.c` using WASI-SDK
5. Loads the extension with the compiled parser

### After Installation

The directory structure becomes:
```
fasterbasic-zed-devinstall/
├── extension.toml
├── grammars/                     # Created by Zed
│   └── fasterbasic/              # Git clone from GitHub
│       ├── grammar.js
│       ├── src/parser.c
│       └── ...
└── languages/
    └── fasterbasic/
        ├── highlights.scm
        └── ...
```

## Why Two Extension Directories?

| Directory | Purpose | Contains Grammar? | Use For |
|-----------|---------|-------------------|---------|
| `fasterbasic-zed` | Source of truth | ✅ Yes (committed to repo) | Development, Git tracking |
| `fasterbasic-zed-devinstall` | Installation target | ❌ No (Zed creates it) | Installing in Zed |

## Key Insights

1. **Zed manages the grammar directory:** When using a remote grammar repository reference, 
   Zed expects to control that directory completely.

2. **Git-in-Git conflict:** You can't have a grammar directory that's part of your main 
   repo when Zed wants to clone a separate repo there.

3. **Separation of concerns:** 
   - Main repo (`fasterbasic-zed/`) = source files for version control
   - Install directory (`fasterbasic-zed-devinstall/`) = what Zed builds from

## Alternative: Separate Grammar Repository

For publishing the extension, the recommended approach is:

1. Create a separate repo: `tree-sitter-fasterbasic`
2. Move grammar files there
3. Update `extension.toml` to point to that repo
4. Publish to Zed extensions registry

This follows the pattern used by most Zed extensions.

## Testing

After installation, verify these features work:

- [ ] Syntax highlighting on `.bas` files
- [ ] Code outline (`Cmd+Shift+O`) shows classes/methods/subs
- [ ] Auto-indentation after `CLASS`, `SUB`, `IF`, etc.
- [ ] Bracket matching for `()`, `[]`, and keyword pairs (IF↔ENDIF)

## Troubleshooting

Check the Zed log for errors:
```bash
tail -f ~/Library/Logs/Zed/Zed.log
```

Common issues:
- **"grammar directory already exists"** → Use `fasterbasic-zed-devinstall`, not `fasterbasic-zed`
- **"failed to clone repository"** → Check internet connection
- **No syntax highlighting** → File must end in `.bas`, `.bi`, or `.bm`

## Files Created

1. `fasterbasic-zed-devinstall/` - Installation directory (use this!)
2. `INSTALL_ZED_EXTENSION.md` - Comprehensive installation guide
3. `install_zed_extension.sh` - Interactive installation script
4. `ZED_EXTENSION_FIX.md` - This document

## Next Steps

✅ Extension is ready to install  
✅ GitHub repository is configured correctly  
✅ Documentation is complete  

**Action Required:** Install the extension using `fasterbasic-zed-devinstall/` directory!

---

**TL;DR:** Use `fasterbasic-zed-devinstall/` to install in Zed, not `fasterbasic-zed/`. 
The difference? One has the grammar directory (won't work), the other doesn't (will work).