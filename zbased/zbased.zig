//! zbased - A simple terminal text editor in Zig
//! Uses the FasterBASIC runtime libraries for terminal I/O and file operations

const std = @import("std");
const Allocator = std.mem.Allocator;

// External runtime functions from FasterBASIC runtime
extern fn basic_cls() void;
extern fn basic_locate(row: i32, col: i32) void;
extern fn basic_color(fg: i32, bg: i32) void;
extern fn basic_kbraw(enable: i32) void;
extern fn basic_kbget() i32;
extern fn basic_cursor_show() void;
extern fn basic_cursor_hide() void;
extern fn basic_slurp(filename: ?*anyopaque) ?*anyopaque;
extern fn basic_spit(filename: ?*anyopaque, content: ?*anyopaque) void;
extern fn string_new_utf8(s: ?[*:0]const u8) ?*anyopaque;
extern fn string_to_utf8(desc: ?*anyopaque) [*:0]const u8;
extern fn string_release(desc: ?*anyopaque) void;

// Special key codes (must match terminal_io.zig)
const KEY_UP = 256;
const KEY_DOWN = 257;
const KEY_LEFT = 258;
const KEY_RIGHT = 259;
const KEY_HOME = 260;
const KEY_END = 261;
const KEY_PGUP = 262;
const KEY_PGDN = 263;
const KEY_DELETE = 264;

// Control key codes
const CTRL_Q = 17;
const CTRL_S = 19;
const CTRL_L = 12;
const CTRL_K = 11;

// ASCII codes
const KEY_ENTER = 13;
const KEY_BACKSPACE = 8;
const KEY_ESC = 27;

const MAX_LINES = 10000;
const SCREEN_WIDTH = 80;
const SCREEN_HEIGHT = 24;
const HEADER_LINES = 2;
const FOOTER_LINES = 2;

const Editor = struct {
    allocator: Allocator,
    lines: std.ArrayList([]u8),
    cursor_x: usize,
    cursor_y: usize,
    view_top: usize,
    modified: bool,
    filename: []const u8,
    quit_flag: bool,
    status_msg: []const u8,
    edit_height: usize,

    fn init(allocator: Allocator, filename: []const u8) !Editor {
        var editor = Editor{
            .allocator = allocator,
            .lines = .{},
            .cursor_x = 0,
            .cursor_y = 0,
            .view_top = 0,
            .modified = false,
            .filename = filename,
            .quit_flag = false,
            .status_msg = "zbased - Press Ctrl+Q to quit, Ctrl+S to save",
            .edit_height = SCREEN_HEIGHT - HEADER_LINES - FOOTER_LINES,
        };

        // Start with one empty line
        try editor.lines.append(allocator, try allocator.dupe(u8, ""));

        return editor;
    }

    fn deinit(self: *Editor) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit(self.allocator);
    }

    fn loadFile(self: *Editor, filename: []const u8) !void {
        // Create null-terminated filename for C API
        const filename_z = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(filename_z);

        // Create string descriptor for filename
        const filename_desc = string_new_utf8(filename_z.ptr);
        defer if (filename_desc != null) string_release(filename_desc);

        // Load file content
        const content_desc = basic_slurp(filename_desc);
        defer if (content_desc != null) string_release(content_desc);

        if (content_desc == null) {
            return; // File doesn't exist or can't be read
        }

        const content = string_to_utf8(content_desc);
        const content_slice = std.mem.span(content);

        // Clear existing lines
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();

        // Parse content into lines
        var line_start: usize = 0;
        var i: usize = 0;
        while (i < content_slice.len) : (i += 1) {
            if (content_slice[i] == '\n') {
                const line = try self.allocator.dupe(u8, content_slice[line_start..i]);
                try self.lines.append(self.allocator, line);
                line_start = i + 1;
            }
        }

        // Handle last line if no trailing newline
        if (line_start < content_slice.len) {
            const line = try self.allocator.dupe(u8, content_slice[line_start..]);
            try self.lines.append(self.allocator, line);
        }

        // Ensure at least one line
        if (self.lines.items.len == 0) {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, ""));
        }

        self.cursor_x = 0;
        self.cursor_y = 0;
        self.view_top = 0;
        self.modified = false;
    }

    fn saveFile(self: *Editor) !void {
        // Build content string
        var content: std.ArrayList(u8) = .{};
        defer content.deinit(self.allocator);

        for (self.lines.items, 0..) |line, idx| {
            try content.appendSlice(self.allocator, line);
            if (idx < self.lines.items.len - 1) {
                try content.append(self.allocator, '\n');
            }
        }

        // Add null terminator for C string
        try content.append(self.allocator, 0);

        // Create null-terminated filename for C API
        const filename_z = try self.allocator.dupeZ(u8, self.filename);
        defer self.allocator.free(filename_z);

        // Create string descriptors
        const filename_desc = string_new_utf8(filename_z.ptr);
        defer if (filename_desc != null) string_release(filename_desc);

        const content_desc = string_new_utf8(content.items.ptr);
        defer if (content_desc != null) string_release(content_desc);

        // Write file
        basic_spit(filename_desc, content_desc);

        self.modified = false;
        self.status_msg = "File saved";
    }

    fn drawHeader(self: *Editor) void {
        // Draw title bar
        basic_locate(0, 0);
        basic_color(15, 1); // White on blue

        const title = " zbased - Zig Text Editor ";
        const mod_indicator = if (self.modified) "[modified] " else "           ";

        // Print title
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(title) catch {};

        // Print spaces
        var spaces: usize = SCREEN_WIDTH - title.len - mod_indicator.len - self.filename.len - 1;
        while (spaces > 0) : (spaces -= 1) {
            stdout.writeByte(' ') catch {};
        }

        // Print filename
        stdout.writeAll(mod_indicator) catch {};
        stdout.writeAll(self.filename) catch {};
        stdout.writeByte(' ') catch {};

        // Draw separator
        basic_locate(0, 1);
        basic_color(7, 0); // White on black
        var i: usize = 0;
        while (i < SCREEN_WIDTH) : (i += 1) {
            stdout.writeByte('=') catch {};
        }
    }

    fn drawLine(self: *Editor, line_num: usize, screen_row: usize) void {
        const stdout = std.io.getStdOut().writer();

        basic_locate(0, @intCast(screen_row));
        basic_color(6, 0); // Cyan for line numbers

        // Line number (5 digits)
        var buf: [16]u8 = undefined;
        const line_str = std.fmt.bufPrint(&buf, "{d:5}: ", .{line_num + 1}) catch "    ?: ";
        stdout.writeAll(line_str) catch {};

        // Code content
        basic_color(7, 0); // White on black

        if (line_num < self.lines.items.len) {
            const line = self.lines.items[line_num];
            const visible_len = @min(line.len, SCREEN_WIDTH - 8);
            stdout.writeAll(line[0..visible_len]) catch {};

            // Pad with spaces
            var spaces = SCREEN_WIDTH - 8 - visible_len;
            while (spaces > 0) : (spaces -= 1) {
                stdout.writeByte(' ') catch {};
            }
        } else {
            // Empty line - fill with spaces
            var spaces = SCREEN_WIDTH - 8;
            while (spaces > 0) : (spaces -= 1) {
                stdout.writeByte(' ') catch {};
            }
        }
    }

    fn drawEditor(self: *Editor) void {
        var i: usize = 0;
        while (i < self.edit_height) : (i += 1) {
            const line_num = self.view_top + i;
            const screen_row = HEADER_LINES + i;
            self.drawLine(line_num, screen_row);
        }
    }

    fn drawStatus(_: *Editor) void {
        const stdout = std.io.getStdOut().writer();
        const status_row = SCREEN_HEIGHT - 2;

        // Draw separator
        basic_locate(0, @intCast(status_row));
        basic_color(7, 0);
        var i: usize = 0;
        while (i < SCREEN_WIDTH) : (i += 1) {
            stdout.writeByte('=') catch {};
        }

        // Draw help line
        basic_locate(0, @intCast(status_row + 1));
        basic_color(0, 7); // Black on white

        const help = " ^S=Save ^Q=Quit ^K=Delete Line  Arrow keys=Navigate ";
        stdout.writeAll(help) catch {};

        var spaces = SCREEN_WIDTH - help.len;
        while (spaces > 0) : (spaces -= 1) {
            stdout.writeByte(' ') catch {};
        }

        basic_color(7, 0);
    }

    fn positionCursor(self: *Editor) void {
        const screen_row = HEADER_LINES + (self.cursor_y - self.view_top);
        const screen_col = 8 + self.cursor_x;
        basic_cursor_show();
        basic_locate(@intCast(screen_col), @intCast(screen_row));
    }

    fn refreshScreen(self: *Editor) void {
        self.drawHeader();
        self.drawEditor();
        self.drawStatus();
        self.positionCursor();
    }

    fn adjustViewport(self: *Editor) void {
        if (self.cursor_y < self.view_top) {
            self.view_top = self.cursor_y;
        } else if (self.cursor_y >= self.view_top + self.edit_height) {
            self.view_top = self.cursor_y - self.edit_height + 1;
        }
    }

    fn clampCursor(self: *Editor) void {
        if (self.cursor_y >= self.lines.items.len) {
            self.cursor_y = self.lines.items.len - 1;
        }

        const line_len = self.lines.items[self.cursor_y].len;
        if (self.cursor_x > line_len) {
            self.cursor_x = line_len;
        }
    }

    fn moveCursorUp(self: *Editor) void {
        if (self.cursor_y > 0) {
            self.cursor_y -= 1;
            self.clampCursor();
            self.adjustViewport();
        }
    }

    fn moveCursorDown(self: *Editor) void {
        if (self.cursor_y < self.lines.items.len - 1) {
            self.cursor_y += 1;
            self.clampCursor();
            self.adjustViewport();
        }
    }

    fn moveCursorLeft(self: *Editor) void {
        if (self.cursor_x > 0) {
            self.cursor_x -= 1;
        } else if (self.cursor_y > 0) {
            self.cursor_y -= 1;
            self.cursor_x = self.lines.items[self.cursor_y].len;
            self.adjustViewport();
        }
    }

    fn moveCursorRight(self: *Editor) void {
        const line_len = self.lines.items[self.cursor_y].len;
        if (self.cursor_x < line_len) {
            self.cursor_x += 1;
        } else if (self.cursor_y < self.lines.items.len - 1) {
            self.cursor_y += 1;
            self.cursor_x = 0;
            self.adjustViewport();
        }
    }

    fn moveCursorHome(self: *Editor) void {
        self.cursor_x = 0;
    }

    fn moveCursorEnd(self: *Editor) void {
        self.cursor_x = self.lines.items[self.cursor_y].len;
    }

    fn insertChar(self: *Editor, ch: u8) !void {
        var line = self.lines.items[self.cursor_y];

        // Create new line with inserted character
        var new_line = try self.allocator.alloc(u8, line.len + 1);
        if (self.cursor_x > 0) {
            @memcpy(new_line[0..self.cursor_x], line[0..self.cursor_x]);
        }
        new_line[self.cursor_x] = ch;
        if (self.cursor_x < line.len) {
            @memcpy(new_line[self.cursor_x + 1 ..], line[self.cursor_x..]);
        }

        self.allocator.free(line);
        self.lines.items[self.cursor_y] = new_line;

        self.cursor_x += 1;
        self.modified = true;
    }

    fn deleteChar(self: *Editor) !void {
        var line = self.lines.items[self.cursor_y];

        if (self.cursor_x > 0) {
            // Delete character before cursor
            var new_line = try self.allocator.alloc(u8, line.len - 1);
            if (self.cursor_x > 1) {
                @memcpy(new_line[0 .. self.cursor_x - 1], line[0 .. self.cursor_x - 1]);
            }
            if (self.cursor_x < line.len) {
                @memcpy(new_line[self.cursor_x - 1 ..], line[self.cursor_x..]);
            }

            self.allocator.free(line);
            self.lines.items[self.cursor_y] = new_line;
            self.cursor_x -= 1;
            self.modified = true;
        } else if (self.cursor_y > 0) {
            // Join with previous line
            const prev_len = self.lines.items[self.cursor_y - 1].len;
            var new_line = try self.allocator.alloc(u8, prev_len + line.len);
            @memcpy(new_line[0..prev_len], self.lines.items[self.cursor_y - 1]);
            @memcpy(new_line[prev_len..], line);

            self.allocator.free(self.lines.items[self.cursor_y - 1]);
            self.allocator.free(line);
            self.lines.items[self.cursor_y - 1] = new_line;

            _ = self.lines.orderedRemove(self.allocator, self.cursor_y);
            self.cursor_y -= 1;
            self.cursor_x = prev_len;
            self.adjustViewport();
            self.modified = true;
        }
    }

    fn insertNewLine(self: *Editor) !void {
        const line = self.lines.items[self.cursor_y];

        // Split line at cursor
        const left = try self.allocator.dupe(u8, line[0..self.cursor_x]);
        const right = try self.allocator.dupe(u8, line[self.cursor_x..]);

        self.allocator.free(line);
        self.lines.items[self.cursor_y] = left;

        try self.lines.insert(self.allocator, self.cursor_y + 1, right);

        self.cursor_y += 1;
        self.cursor_x = 0;
        self.adjustViewport();
        self.modified = true;
    }

    fn deleteLine(self: *Editor) !void {
        if (self.lines.items.len > 1) {
            self.allocator.free(self.lines.items[self.cursor_y]);
            _ = self.lines.orderedRemove(self.allocator, self.cursor_y);

            if (self.cursor_y >= self.lines.items.len) {
                self.cursor_y = self.lines.items.len - 1;
            }
            self.cursor_x = 0;
            self.modified = true;
        }
    }

    fn handleKey(self: *Editor, key: i32) !void {
        switch (key) {
            CTRL_Q => {
                self.quit_flag = true;
            },
            CTRL_S => {
                try self.saveFile();
            },
            CTRL_K => {
                try self.deleteLine();
            },
            KEY_UP => self.moveCursorUp(),
            KEY_DOWN => self.moveCursorDown(),
            KEY_LEFT => self.moveCursorLeft(),
            KEY_RIGHT => self.moveCursorRight(),
            KEY_HOME => self.moveCursorHome(),
            KEY_END => self.moveCursorEnd(),
            KEY_ENTER => try self.insertNewLine(),
            KEY_BACKSPACE => try self.deleteChar(),
            32...126 => try self.insertChar(@intCast(key)),
            else => {},
        }
    }

    fn run(self: *Editor) !void {
        // Enter raw mode
        basic_kbraw(1);
        defer basic_kbraw(0);

        // Initial draw
        basic_cls();
        basic_cursor_hide();
        self.refreshScreen();

        // Main loop
        while (!self.quit_flag) {
            const key = basic_kbget();
            try self.handleKey(key);
            self.refreshScreen();
        }

        // Cleanup
        basic_cursor_show();
        basic_cls();
        basic_locate(0, 0);
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll("Thanks for using zbased!\n") catch {};
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command-line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip program name

    const filename = args.next() orelse "untitled.txt";
    const filename_owned = try allocator.dupe(u8, filename);
    defer allocator.free(filename_owned);

    var editor = try Editor.init(allocator, filename_owned);
    defer editor.deinit();

    // Try to load file if it exists
    editor.loadFile(filename_owned) catch |err| {
        if (err != error.FileNotFound) {
            std.debug.print("Error loading file: {}\n", .{err});
        }
    };

    try editor.run();
}
