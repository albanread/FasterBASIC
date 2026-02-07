#!/bin/bash

# FasterBASIC Zed Extension Installation Script
# This script helps install the FasterBASIC extension for Zed editor

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTENSION_DIR="$REPO_DIR/fasterbasic-zed"
ZED_EXTENSIONS_DIR="$HOME/.local/share/zed/extensions"
INSTALLED_EXTENSION_DIR="$ZED_EXTENSIONS_DIR/fasterbasic"

echo "======================================"
echo "FasterBASIC Zed Extension Installer"
echo "======================================"
echo ""

# Check if Zed is installed
if ! command -v zed &> /dev/null; then
    echo "❌ Zed editor not found!"
    echo "Please install Zed from https://zed.dev"
    exit 1
fi

echo "✅ Zed editor found"

# Check if extension directory exists
if [ ! -d "$EXTENSION_DIR" ]; then
    echo "❌ Extension directory not found at: $EXTENSION_DIR"
    exit 1
fi

echo "✅ Extension directory found"

# Check for tree-sitter CLI
if ! command -v tree-sitter &> /dev/null; then
    echo "⚠️  tree-sitter CLI not found (optional for development)"
else
    echo "✅ tree-sitter CLI found"
fi

echo ""
echo "Installation Options:"
echo ""
echo "1) Install as Dev Extension (recommended for development)"
echo "   - Use Zed's built-in dev extension installer"
echo "   - Fetches grammar from GitHub"
echo "   - Easy to update"
echo ""
echo "2) Copy to Zed Extensions Directory"
echo "   - Direct copy to ~/.local/share/zed/extensions"
echo "   - No GitHub required"
echo "   - Manual updates"
echo ""
echo "3) Show Manual Installation Instructions"
echo ""
echo "4) Exit"
echo ""

read -p "Choose an option (1-4): " choice

case $choice in
    1)
        echo ""
        echo "📦 Installing as Dev Extension..."
        echo ""
        echo "Please follow these steps:"
        echo ""
        echo "1. Open Zed editor"
        echo "2. Press Cmd+Shift+P (macOS) or Ctrl+Shift+P (Linux)"
        echo "3. Type: 'zed: install dev extension'"
        echo "4. Press Enter"
        echo "5. Navigate to and select: $EXTENSION_DIR"
        echo "6. Wait for Zed to compile the grammar (~30 seconds)"
        echo ""
        echo "The extension should now be active!"
        ;;

    2)
        echo ""
        echo "📦 Copying extension to Zed extensions directory..."

        # Create extensions directory if it doesn't exist
        mkdir -p "$ZED_EXTENSIONS_DIR"

        # Remove old installation if exists
        if [ -d "$INSTALLED_EXTENSION_DIR" ]; then
            echo "🗑️  Removing old installation..."
            rm -rf "$INSTALLED_EXTENSION_DIR"
        fi

        # Copy extension
        echo "📁 Copying files..."
        cp -r "$EXTENSION_DIR" "$INSTALLED_EXTENSION_DIR"

        echo ""
        echo "✅ Extension copied successfully!"
        echo ""
        echo "⚠️  Note: This method may not work properly because Zed expects"
        echo "to fetch and compile the grammar itself. If you see errors,"
        echo "please use Option 1 instead."
        echo ""
        echo "Next steps:"
        echo "1. Restart Zed"
        echo "2. Open a .bas file"
        echo "3. Check if syntax highlighting works"
        ;;

    3)
        echo ""
        echo "📖 Manual Installation Instructions"
        echo "===================================="
        echo ""
        echo "Method 1: Dev Extension (Recommended)"
        echo "--------------------------------------"
        echo "1. Open Zed"
        echo "2. Press Cmd+Shift+P (or Ctrl+Shift+P)"
        echo "3. Type: 'zed: install dev extension'"
        echo "4. Select: $EXTENSION_DIR"
        echo "5. Wait for compilation"
        echo ""
        echo "Method 2: Check Installation"
        echo "----------------------------"
        echo "1. Open Zed"
        echo "2. Go to Settings (Cmd+,)"
        echo "3. Click 'Extensions'"
        echo "4. Look for 'FasterBASIC'"
        echo ""
        echo "Method 3: Test the Extension"
        echo "----------------------------"
        echo "1. Create a test file: test.bas"
        echo "2. Add some FasterBASIC code"
        echo "3. Check for syntax highlighting"
        echo "4. Press Cmd+Shift+O for code outline"
        echo ""
        echo "Troubleshooting:"
        echo "----------------"
        echo "- If you see 'grammar error', check internet connection"
        echo "- Make sure GitHub repo is accessible"
        echo "- Check Zed logs: ~/.local/share/zed/logs/Zed.log"
        echo "- Try: zed --foreground (to see live logs)"
        echo ""
        echo "More help: See INSTALL_ZED_EXTENSION.md"
        ;;

    4)
        echo "Exiting..."
        exit 0
        ;;

    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

echo ""
echo "======================================"
echo "For more information, see:"
echo "  $REPO_DIR/INSTALL_ZED_EXTENSION.md"
echo "======================================"
