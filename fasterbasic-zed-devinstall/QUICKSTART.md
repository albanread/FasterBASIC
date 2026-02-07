# FasterBASIC Zed Extension - Quick Start

## Installation (2 minutes)

### Step 1: Open Zed
Launch the Zed editor.

### Step 2: Install Dev Extension
1. Press `Cmd+Shift+P` (macOS) to open the command palette
2. Type: `zed: install dev extension`
3. Press Enter

### Step 3: Select Extension Directory
Navigate to and select:
```
/Users/oberon/compact_repo/fasterbasic-zed-devinstall
```

### Step 4: Wait for Compilation
Zed will:
- Clone the grammar from GitHub (takes ~5 seconds)
- Compile the Tree-sitter parser (takes ~20-30 seconds)
- Show a success notification when done

### Step 5: Test It
1. Create a test file: `test.bas`
2. Add some FasterBASIC code:

```basic
CLASS Player
    FIELD name AS STRING
    FIELD score AS INTEGER
    
    CONSTRUCTOR(n AS STRING)
        name = n
        score = 0
    END CONSTRUCTOR
    
    METHOD addPoints(points AS INTEGER)
        score = score + points
        PRINT "Score: "; score
    END METHOD
END CLASS

SUB main()
    DIM p AS Player
    p = NEW Player("Alice")
    p.addPoints(100)
END SUB
```

3. You should see:
   - ✅ Syntax highlighting (keywords, types, strings colored)
   - ✅ Code outline (`Cmd+Shift+O` to see classes/methods)
   - ✅ Auto-indentation (press Enter after CLASS, SUB, etc.)
   - ✅ Bracket matching

## Troubleshooting

### "Failed to compile grammar"
**Problem:** Zed can't fetch or compile the grammar.

**Solutions:**
1. Check internet connection (Zed needs to fetch from GitHub)
2. Make sure you selected `fasterbasic-zed-devinstall` (NOT `fasterbasic-zed`)
3. Check Zed logs: `~/Library/Logs/Zed/Zed.log`

### No syntax highlighting
1. Make sure file ends with `.bas`, `.bi`, or `.bm`
2. Try manually setting language: `Cmd+K` then `M`, type "FasterBASIC"
3. Reload extensions: Command Palette → `zed: reload extensions`

### Extension not showing up
1. Go to Zed Settings (`Cmd+,`)
2. Click "Extensions"
3. Look for "FasterBASIC" in the list
4. If not there, try reinstalling

## Features

Once installed, you get:

| Feature | Description | Shortcut |
|---------|-------------|----------|
| **Syntax Highlighting** | Full Tree-sitter grammar | Automatic |
| **Code Outline** | Navigate classes, methods, subs | `Cmd+Shift+O` |
| **Auto-Indent** | Smart block indentation | Press `Enter` |
| **Bracket Matching** | Highlights matching pairs | Automatic |
| **Symbol Search** | Find symbols in file | `Cmd+Shift+O` |

## Updating the Extension

After pulling new changes from the repository:

1. Uninstall: Command Palette → `zed: uninstall dev extension` → Select "FasterBASIC"
2. Reinstall: Follow Steps 1-4 above

## Why Two Extension Directories?

- `fasterbasic-zed` - Full extension with grammar source (for development)
- `fasterbasic-zed-devinstall` - Extension without grammar (for Zed to fetch)

Zed requires an empty `grammars` directory so it can clone and compile the grammar itself. That's why we use the separate `devinstall` folder.

## Need Help?

- Check the full guide: `INSTALL_ZED_EXTENSION.md`
- View Zed logs: `tail -f ~/Library/Logs/Zed/Zed.log`
- Open an issue on GitHub: https://github.com/albanread/FasterBASIC

Happy coding! 🚀