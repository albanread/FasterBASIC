# Installing the FasterBASIC Zed Extension

This guide will help you install the FasterBASIC extension for Zed editor.

## Prerequisites

- [Zed Editor](https://zed.dev) installed on your Mac
- The FasterBASIC repository cloned or available locally

## Installation Methods

### Method 1: Install from Local Directory (Recommended for Development)

This is the easiest method for testing and development.

1. **Open Zed**

2. **Open the Command Palette**
   - Press `Cmd+Shift+P` (macOS) or `Ctrl+Shift+P` (Linux/Windows)

3. **Install Dev Extension**
   - Type: `zed: install dev extension`
   - Press Enter

4. **Select the Extension Directory**
   - Navigate to your FasterBASIC repository
   - Select the `fasterbasic-zed` folder
   - Click "Open"

5. **Wait for Compilation**
   - Zed will clone the grammar repository from GitHub
   - It will compile the Tree-sitter parser (this may take 10-30 seconds)
   - You should see a notification when it's complete

6. **Verify Installation**
   - Open a `.bas` file in Zed
   - You should see syntax highlighting
   - Open the outline panel (`Cmd+Shift+O`) to see code structure

### Method 2: Using the Standalone Extension (No GitHub Required)

If you want to avoid GitHub fetching or are having issues with Method 1:

1. **Copy the standalone extension to Zed's extensions directory**

   ```bash
   mkdir -p ~/.local/share/zed/extensions
   cp -r ~/compact_repo/fasterbasic-zed-standalone ~/.local/share/zed/extensions/fasterbasic
   ```

2. **Restart Zed**
   - Close and reopen Zed
   - The extension should load automatically

3. **Check Installed Extensions**
   - Open Zed Settings (`Cmd+,`)
   - Go to Extensions
   - You should see "FasterBASIC" listed

## Troubleshooting

### "Grammar Error" or "Failed to Compile Grammar"

This usually means Zed couldn't fetch or compile the Tree-sitter parser.

**Solution 1: Check your internet connection**
- Zed needs to fetch the grammar from GitHub
- Make sure you have internet access

**Solution 2: Verify the commit exists on GitHub**
- Open: https://github.com/albanread/FasterBASIC/commit/045b3e4
- If you see a 404, the extension needs to be updated with the latest commit

**Solution 3: Use the standalone extension**
- Follow Method 2 above instead

**Solution 4: Check Zed logs**
```bash
# Open Zed with logging
zed --foreground
```
Look for error messages related to "grammar" or "fasterbasic"

### Extension Installed but No Syntax Highlighting

1. **Check file extension**
   - Make sure your file ends in `.bas`, `.bi`, or `.bm`
   - Zed only applies the grammar to recognized file types

2. **Manually set the language**
   - Open a BASIC file
   - Press `Cmd+K` then `M` (or use Command Palette: "Change Language Mode")
   - Type "FasterBASIC" and select it

3. **Reload the extension**
   - Command Palette → `zed: reload extensions`

### Need to Update the Extension

After pulling new changes from the repository:

1. **Uninstall the dev extension**
   - Command Palette → `zed: uninstall dev extension`
   - Select "FasterBASIC"

2. **Reinstall it**
   - Follow Method 1 steps again

## Verifying the Extension Works

Create a test file `test.bas`:

```basic
CLASS Player EXTENDS GameObject
    FIELD name AS STRING
    FIELD score AS INTEGER
    
    CONSTRUCTOR(playerName AS STRING)
        name = playerName
        score = 0
    END CONSTRUCTOR
    
    METHOD updateScore(points AS INTEGER)
        score = score + points
        PRINT "Score: "; score
    END METHOD
END CLASS

SUB main()
    DIM p AS Player
    p = NEW Player("Alice")
    p.updateScore(100)
END SUB
```

You should see:
- Keywords (`CLASS`, `SUB`, `DIM`, etc.) highlighted
- Types (`STRING`, `INTEGER`) in a different color
- Methods and fields visible in the outline panel
- Proper indentation when pressing Enter after `CLASS`, `SUB`, etc.

## Features

Once installed, you'll have:

✅ **Syntax Highlighting** - All FasterBASIC keywords, types, and constructs  
✅ **Code Outline** - Navigate classes, methods, functions, and subs  
✅ **Auto-Indentation** - Smart indent/outdent for blocks  
✅ **Bracket Matching** - Highlights matching `()`, `[]`, and keyword pairs  
✅ **Tree-sitter Grammar** - Proper structural understanding of your code

## Uninstalling

To remove the extension:

1. **For Dev Extensions**
   - Command Palette → `zed: uninstall dev extension`
   - Select "FasterBASIC"

2. **For Manual Installation**
   ```bash
   rm -rf ~/.local/share/zed/extensions/fasterbasic
   ```

3. **Restart Zed**

## Getting Help

If you encounter issues:

1. Check the Zed logs: `~/.local/share/zed/logs/Zed.log`
2. Verify the grammar compiles locally:
   ```bash
   cd ~/compact_repo/fasterbasic-zed/grammars/fasterbasic
   tree-sitter generate
   tree-sitter test
   ```
3. Open an issue on the FasterBASIC GitHub repository

## Development

To modify the extension:

### Editing Syntax Highlighting

Edit `fasterbasic-zed/languages/fasterbasic/highlights.scm`

No recompilation needed - just reload:
- Command Palette → `zed: reload extensions`

### Editing the Grammar

1. Edit `fasterbasic-zed/grammars/fasterbasic/grammar.js`
2. Regenerate:
   ```bash
   cd fasterbasic-zed/grammars/fasterbasic
   tree-sitter generate
   ```
3. Commit the changes
4. Update `extension.toml` with the new commit SHA
5. Reinstall the dev extension in Zed

## Next Steps

- Try opening some of your FasterBASIC projects in Zed
- Experiment with the outline view for navigation
- Report any highlighting issues or grammar bugs
- Customize your Zed theme to suit your preferences

Happy coding! 🚀