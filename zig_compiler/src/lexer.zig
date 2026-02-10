//! Lexer (Tokenizer) for the FasterBASIC compiler.
//!
//! Converts BASIC source code into a stream of tokens. Handles line numbers,
//! keywords, identifiers, literals, operators, type suffixes, and comments.
//!
//! Design differences from the C++ version:
//! - Tokens store slices into the original source buffer (zero-copy).
//! - No dynamic allocation needed for tokenization itself.
//! - Errors are collected as a slice rather than thrown as exceptions.
//! - The keyword map is built at comptime via `token.Tag.fromKeyword`.

const std = @import("std");
const token = @import("token.zig");
const Token = token.Token;
const Tag = token.Tag;
const SourceLocation = token.SourceLocation;

/// A lexer error with location information.
pub const LexerError = struct {
    message: []const u8,
    location: SourceLocation,

    pub fn format(self: LexerError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Lexer Error at {}: {s}", .{ self.location, self.message });
    }
};

/// Lexer — converts source text into a sequence of Tokens.
///
/// Usage:
/// ```
/// var lexer = Lexer.init(source, allocator);
/// try lexer.tokenize();
/// const tokens = lexer.tokens.items;
/// ```
pub const Lexer = struct {
    /// The full source text being tokenized.
    source: []const u8,
    /// Current byte position in the source.
    pos: usize,
    /// Current line number (1-based).
    line: u32,
    /// Current column number (1-based).
    column: u32,
    /// Accumulated tokens.
    tokens: std.ArrayList(Token),
    /// Accumulated errors.
    errors: std.ArrayList(LexerError),
    /// Allocator for dynamic arrays.
    allocator: std.mem.Allocator,

    /// Initialize a new Lexer over the given source text.
    pub fn init(source: []const u8, allocator: std.mem.Allocator) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
            .tokens = .empty,
            .errors = .empty,
            .allocator = allocator,
        };
    }

    /// Release all memory owned by the lexer (token and error lists).
    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit(self.allocator);
        // Error messages are string literals or slices into source — no freeing needed.
        self.errors.deinit(self.allocator);
    }

    /// Tokenize the entire source. After calling this, `tokens.items` contains
    /// the complete token stream (terminated by `end_of_file`).
    pub fn tokenize(self: *Lexer) !void {
        while (!self.isAtEnd()) {
            try self.scanToken();
        }

        // Always append an end-of-file sentinel.
        try self.addSimpleToken(.end_of_file);
    }

    /// Whether tokenization produced any errors.
    pub fn hasErrors(self: *const Lexer) bool {
        return self.errors.items.len > 0;
    }

    // ─── Character inspection ───────────────────────────────────────────

    fn currentChar(self: *const Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.pos];
    }

    fn peekChar(self: *const Lexer, offset: usize) u8 {
        const p = self.pos + offset;
        if (p >= self.source.len) return 0;
        return self.source[p];
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.pos >= self.source.len;
    }

    // ─── Character consumption ──────────────────────────────────────────

    fn advance(self: *Lexer) u8 {
        if (self.isAtEnd()) return 0;
        const c = self.source[self.pos];
        self.pos += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.pos] != expected) return false;
        _ = self.advance();
        return true;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (!self.isAtEnd()) {
            const c = self.currentChar();
            if (c == ' ' or c == '\t' or c == '\r') {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    fn skipToEndOfLine(self: *Lexer) void {
        while (!self.isAtEnd() and self.currentChar() != '\n') {
            _ = self.advance();
        }
    }

    // ─── Location helpers ───────────────────────────────────────────────

    fn currentLocation(self: *const Lexer) SourceLocation {
        return .{ .line = self.line, .column = self.column };
    }

    // ─── Token creation ─────────────────────────────────────────────────

    fn addToken(self: *Lexer, tag: Tag, lexeme: []const u8, loc: SourceLocation) !void {
        try self.tokens.append(self.allocator, .{
            .tag = tag,
            .lexeme = lexeme,
            .location = loc,
        });
    }

    fn addTokenNumber(self: *Lexer, tag: Tag, lexeme: []const u8, loc: SourceLocation, value: f64) !void {
        try self.tokens.append(self.allocator, .{
            .tag = tag,
            .lexeme = lexeme,
            .location = loc,
            .number_value = value,
        });
    }

    fn addTokenString(self: *Lexer, tag: Tag, lexeme: []const u8, loc: SourceLocation, has_non_ascii: bool) !void {
        try self.tokens.append(self.allocator, .{
            .tag = tag,
            .lexeme = lexeme,
            .location = loc,
            .has_non_ascii = has_non_ascii,
        });
    }

    fn addSimpleToken(self: *Lexer, tag: Tag) !void {
        try self.tokens.append(self.allocator, .{
            .tag = tag,
            .lexeme = "",
            .location = self.currentLocation(),
        });
    }

    // ─── Error reporting ────────────────────────────────────────────────

    fn addError(self: *Lexer, message: []const u8) !void {
        try self.errors.append(self.allocator, .{
            .message = message,
            .location = self.currentLocation(),
        });
    }

    fn addErrorAt(self: *Lexer, message: []const u8, loc: SourceLocation) !void {
        try self.errors.append(self.allocator, .{
            .message = message,
            .location = loc,
        });
    }

    // ─── Main scan dispatcher ───────────────────────────────────────────

    fn scanToken(self: *Lexer) !void {
        self.skipWhitespace();

        if (self.isAtEnd()) return;

        const c = self.currentChar();

        // Newline → end-of-line token
        if (c == '\n') {
            const loc = self.currentLocation();
            _ = self.advance();
            try self.addToken(.end_of_line, "\n", loc);
            return;
        }

        // Single-quote comment (rest of line is comment, like REM)
        if (c == '\'') {
            self.skipToEndOfLine();
            return;
        }

        // Hex literal: &H or 0x (must check before general number scan)
        if (c == '&' and toUpper(self.peekChar(1)) == 'H') {
            try self.scanHexNumber();
            return;
        }
        if (c == '0' and (self.peekChar(1) == 'x' or self.peekChar(1) == 'X')) {
            try self.scanHexNumberCStyle();
            return;
        }

        // Number literal
        if (isDigit(c) or (c == '.' and isDigit(self.peekChar(1)))) {
            try self.scanNumber();
            return;
        }

        // String literal
        if (c == '"') {
            try self.scanString();
            return;
        }

        // Identifier or keyword
        if (isIdentifierStart(c)) {
            try self.scanIdentifierOrKeyword();
            return;
        }

        // Operators and delimiters
        try self.scanOperator();
    }

    // ─── Number scanning ────────────────────────────────────────────────

    fn scanNumber(self: *Lexer) !void {
        const loc = self.currentLocation();
        const start = self.pos;

        // Integer part
        while (!self.isAtEnd() and isDigit(self.currentChar())) {
            _ = self.advance();
        }

        // Fractional part
        if (!self.isAtEnd() and self.currentChar() == '.' and isDigit(self.peekChar(1))) {
            _ = self.advance(); // consume '.'
            while (!self.isAtEnd() and isDigit(self.currentChar())) {
                _ = self.advance();
            }
        }

        // Exponent (e/E)
        if (!self.isAtEnd() and (self.currentChar() == 'e' or self.currentChar() == 'E')) {
            _ = self.advance();
            if (!self.isAtEnd() and (self.currentChar() == '+' or self.currentChar() == '-')) {
                _ = self.advance();
            }
            if (!self.isAtEnd() and isDigit(self.currentChar())) {
                while (!self.isAtEnd() and isDigit(self.currentChar())) {
                    _ = self.advance();
                }
            } else {
                try self.addErrorAt("Invalid number: expected digits after exponent", loc);
            }
        }

        const lexeme = self.source[start..self.pos];
        const value = std.fmt.parseFloat(f64, lexeme) catch 0.0;
        try self.addTokenNumber(.number, lexeme, loc, value);

        // Consume an optional type suffix immediately after the number.
        // In BASIC, 42% means integer-typed 42, 3.14# means double, etc.
        // We emit the suffix as a separate token (same as for identifiers)
        // so the parser can see and skip it.
        if (!self.isAtEnd() and isNumericTypeSuffix(self.currentChar())) {
            if (getTypeSuffixTag(self.currentChar())) |stag| {
                const suffix_loc = self.currentLocation();
                const suffix_start = self.pos;
                _ = self.advance();
                try self.addToken(stag, self.source[suffix_start..self.pos], suffix_loc);
            }
        }
    }

    fn scanHexNumber(self: *Lexer) !void {
        const loc = self.currentLocation();
        const start = self.pos;

        // Skip &H
        _ = self.advance(); // &
        _ = self.advance(); // H

        if (self.isAtEnd() or !isHexDigit(self.currentChar())) {
            try self.addErrorAt("Invalid hex number: expected hex digits after &H", loc);
            return;
        }

        while (!self.isAtEnd() and isHexDigit(self.currentChar())) {
            _ = self.advance();
        }

        const lexeme = self.source[start..self.pos];
        const hex_digits = self.source[start + 2 .. self.pos]; // skip "&H"
        const value: f64 = @floatFromInt(std.fmt.parseInt(i64, hex_digits, 16) catch 0);
        try self.addTokenNumber(.number, lexeme, loc, value);
    }

    fn scanHexNumberCStyle(self: *Lexer) !void {
        const loc = self.currentLocation();
        const start = self.pos;

        // Skip 0x
        _ = self.advance(); // 0
        _ = self.advance(); // x

        if (self.isAtEnd() or !isHexDigit(self.currentChar())) {
            try self.addErrorAt("Invalid hex number: expected hex digits after 0x", loc);
            return;
        }

        while (!self.isAtEnd() and isHexDigit(self.currentChar())) {
            _ = self.advance();
        }

        const lexeme = self.source[start..self.pos];
        const hex_digits = self.source[start + 2 .. self.pos];
        const value: f64 = @floatFromInt(std.fmt.parseInt(i64, hex_digits, 16) catch 0);
        try self.addTokenNumber(.number, lexeme, loc, value);
    }

    // ─── String scanning ────────────────────────────────────────────────

    fn scanString(self: *Lexer) !void {
        const loc = self.currentLocation();
        const start = self.pos;

        _ = self.advance(); // consume opening '"'

        var has_non_ascii = false;

        while (!self.isAtEnd() and self.currentChar() != '"' and self.currentChar() != '\n') {
            if (self.currentChar() >= 0x80) {
                has_non_ascii = true;
            }
            // Handle escape sequences (backslash)
            if (self.currentChar() == '\\' and !self.isAtEnd()) {
                _ = self.advance(); // skip backslash
                if (!self.isAtEnd() and self.currentChar() != '\n') {
                    _ = self.advance(); // skip escaped char
                }
            } else {
                _ = self.advance();
            }
        }

        if (self.isAtEnd() or self.currentChar() == '\n') {
            try self.addErrorAt("Unterminated string literal", loc);
            // Still produce a string token for error recovery
            const lexeme = self.source[start..self.pos];
            try self.addTokenString(.string, lexeme, loc, has_non_ascii);
            return;
        }

        _ = self.advance(); // consume closing '"'

        const lexeme = self.source[start..self.pos];
        // The value is the text between the quotes (start+1 .. pos-1)
        try self.addTokenString(.string, lexeme, loc, has_non_ascii);
    }

    /// Extract the string content (between quotes) from a string token's lexeme.
    /// This is a utility for consumers of the token stream.
    pub fn stringValue(tok: Token) []const u8 {
        if (tok.lexeme.len >= 2 and tok.lexeme[0] == '"') {
            return tok.lexeme[1 .. tok.lexeme.len - 1];
        }
        return tok.lexeme;
    }

    // ─── Identifier / keyword scanning ──────────────────────────────────

    fn scanIdentifierOrKeyword(self: *Lexer) !void {
        const loc = self.currentLocation();
        const start = self.pos;

        while (!self.isAtEnd() and isIdentifierChar(self.currentChar())) {
            _ = self.advance();
        }

        const lexeme = self.source[start..self.pos];

        // ── Keyword vs identifier disambiguation ────────────────────────
        //
        // If a keyword is immediately followed by ANY type suffix
        // (%, #, !, &, @, ^, $) with no whitespace, it is a variable
        // name, not a keyword.  This is standard BASIC behaviour:
        //   SINGLE%  → identifier "SINGLE" + suffix .type_int
        //   INTEGER  → keyword .kw_integer  (no suffix)
        //   INTEGER% → identifier "INTEGER" + suffix .type_int
        //   LEFT$    → identifier "LEFT" + suffix .type_string
        //   EMPTY$   → identifier "EMPTY" + suffix .type_string
        //
        // The `$` suffix IS included: when LEFT$ is used as a function
        // call (e.g. LEFT$("hello", 3)), the parser's identifier path
        // sees identifier "LEFT" + suffix "$" + lparen and dispatches
        // through isBuiltinFunction().  When LEFT$ is used as a
        // variable (e.g. left$ = "hello"), no lparen follows, so the
        // parser treats it as a variable.  This avoids the ambiguity
        // where keyword tokens like .kw_left demanded '(' even in
        // variable-assignment contexts.

        const followed_by_suffix = !self.isAtEnd() and (isNumericTypeSuffix(self.currentChar()) or self.currentChar() == '$');

        if (!followed_by_suffix) {
            if (Tag.fromKeyword(lexeme)) |kw_tag| {
                // Special handling for REM — rest of line is comment
                if (kw_tag == .kw_rem) {
                    self.skipToEndOfLine();
                    return;
                }

                // Special: END SUB / END FUNCTION / END TYPE / etc.
                if (kw_tag == .kw_end) {
                    const saved_pos = self.pos;
                    const saved_line = self.line;
                    const saved_col = self.column;
                    self.skipWhitespace();
                    if (!self.isAtEnd() and isIdentifierStart(self.currentChar())) {
                        const compound_start = self.pos;
                        while (!self.isAtEnd() and isIdentifierChar(self.currentChar())) {
                            _ = self.advance();
                        }
                        const second_word = self.source[compound_start..self.pos];
                        if (resolveEndCompound(second_word)) |ctag| {
                            const compound_lexeme = self.source[start..self.pos];
                            try self.addToken(ctag, compound_lexeme, loc);
                            return;
                        }
                        // Not a compound — rewind and emit END as keyword
                        self.pos = saved_pos;
                        self.line = saved_line;
                        self.column = saved_col;
                    }
                    self.pos = saved_pos;
                    self.line = saved_line;
                    self.column = saved_col;
                }

                try self.addToken(kw_tag, lexeme, loc);
                return;
            }
        }

        // ── Identifier (possibly with type suffix) ──────────────────────
        if (!self.isAtEnd()) {
            if (getTypeSuffixTag(self.currentChar())) |stag| {
                _ = self.advance();
                const full_lexeme = self.source[start..self.pos];
                try self.addToken(.identifier, full_lexeme, loc);
                try self.addToken(stag, self.source[self.pos - 1 .. self.pos], .{
                    .line = self.line,
                    .column = self.column - 1,
                });
                return;
            }
        }
        try self.addToken(.identifier, lexeme, loc);
    }

    /// Resolve "END <word>" compound keywords.
    fn resolveEndCompound(second_word: []const u8) ?Tag {
        var buf: [16]u8 = undefined;
        if (second_word.len > buf.len) return null;
        const upper = toUpperBuf(second_word, &buf);

        if (std.mem.eql(u8, upper, "SUB")) return .kw_endsub;
        if (std.mem.eql(u8, upper, "FUNCTION")) return .kw_endfunction;
        if (std.mem.eql(u8, upper, "TYPE")) return .kw_endtype;
        if (std.mem.eql(u8, upper, "IF")) return .kw_endif;
        if (std.mem.eql(u8, upper, "CASE")) return .kw_endcase;
        if (std.mem.eql(u8, upper, "SELECT")) return .kw_endcase;
        if (std.mem.eql(u8, upper, "MATCH")) return .kw_endmatch;
        if (std.mem.eql(u8, upper, "WORKER")) return .kw_endworker;
        // NOTE: END CONSTRUCTOR, END DESTRUCTOR, END METHOD, and END CLASS
        // are intentionally NOT collapsed into compound tokens.  The parser
        // handles them as two separate tokens (.kw_end + .kw_constructor etc.)
        // which allows bare END (program termination) inside class member
        // bodies to be correctly distinguished from the closing delimiter.
        return null;
    }

    // ─── Operator / delimiter scanning ──────────────────────────────────

    fn scanOperator(self: *Lexer) !void {
        const loc = self.currentLocation();
        const c = self.advance();

        switch (c) {
            '+' => try self.addToken(.plus, self.source[self.pos - 1 .. self.pos], loc),
            '-' => try self.addToken(.minus, self.source[self.pos - 1 .. self.pos], loc),
            '*' => try self.addToken(.multiply, self.source[self.pos - 1 .. self.pos], loc),
            '/' => try self.addToken(.divide, self.source[self.pos - 1 .. self.pos], loc),
            '\\' => try self.addToken(.int_divide, self.source[self.pos - 1 .. self.pos], loc),
            '^' => try self.addToken(.power, self.source[self.pos - 1 .. self.pos], loc),
            '(' => try self.addToken(.lparen, self.source[self.pos - 1 .. self.pos], loc),
            ')' => try self.addToken(.rparen, self.source[self.pos - 1 .. self.pos], loc),
            ',' => try self.addToken(.comma, self.source[self.pos - 1 .. self.pos], loc),
            ';' => try self.addToken(.semicolon, self.source[self.pos - 1 .. self.pos], loc),
            ':' => try self.addToken(.colon, self.source[self.pos - 1 .. self.pos], loc),
            '.' => try self.addToken(.dot, self.source[self.pos - 1 .. self.pos], loc),
            '?' => try self.addToken(.kw_print, self.source[self.pos - 1 .. self.pos], loc),

            '=' => try self.addToken(.equal, self.source[self.pos - 1 .. self.pos], loc),

            '<' => {
                if (self.match('>')) {
                    try self.addToken(.not_equal, self.source[self.pos - 2 .. self.pos], loc);
                } else if (self.match('=')) {
                    try self.addToken(.less_equal, self.source[self.pos - 2 .. self.pos], loc);
                } else {
                    try self.addToken(.less_than, self.source[self.pos - 1 .. self.pos], loc);
                }
            },
            '>' => {
                if (self.match('=')) {
                    try self.addToken(.greater_equal, self.source[self.pos - 2 .. self.pos], loc);
                } else {
                    try self.addToken(.greater_than, self.source[self.pos - 1 .. self.pos], loc);
                }
            },

            '!' => {
                if (self.match('=')) {
                    try self.addToken(.not_equal, self.source[self.pos - 2 .. self.pos], loc);
                } else {
                    // ! as type suffix (SINGLE)
                    try self.addToken(.type_float, self.source[self.pos - 1 .. self.pos], loc);
                }
            },

            '%' => try self.addToken(.type_int, self.source[self.pos - 1 .. self.pos], loc),
            '#' => try self.addToken(.type_double, self.source[self.pos - 1 .. self.pos], loc),
            '$' => try self.addToken(.type_string, self.source[self.pos - 1 .. self.pos], loc),
            '@' => try self.addToken(.type_byte, self.source[self.pos - 1 .. self.pos], loc),
            '&' => {
                // & followed by H is a hex literal — but we handle that earlier.
                // Standalone & is the LONG type suffix.
                try self.addToken(.ampersand, self.source[self.pos - 1 .. self.pos], loc);
            },

            else => {
                // Unknown character — report error but continue
                try self.addErrorAt("Unexpected character", loc);
                try self.addToken(.unknown, self.source[self.pos - 1 .. self.pos], loc);
            },
        }
    }

    // ─── Type suffix helpers ────────────────────────────────────────────

    /// Returns true if `c` is a numeric type suffix character.
    /// These suffixes override keyword status when they immediately follow
    /// a keyword (e.g. `SINGLE%` becomes an identifier, not `.kw_single`).
    /// Note: `$` is intentionally excluded — it is part of string function
    /// keywords like LEFT$, MID$, CHR$, STR$.
    fn isNumericTypeSuffix(c: u8) bool {
        return switch (c) {
            '%', '!', '#', '@', '&', '^' => true,
            else => false,
        };
    }

    fn getTypeSuffixTag(c: u8) ?Tag {
        return switch (c) {
            '%' => .type_int,
            '!' => .type_float,
            '#' => .type_double,
            '$' => .type_string,
            '@' => .type_byte,
            '&' => .ampersand,
            '^' => .caret,
            else => null,
        };
    }

    // ─── Character classification ───────────────────────────────────────

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isHexDigit(c: u8) bool {
        return (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
    }

    fn isIdentifierStart(c: u8) bool {
        return isAlpha(c) or c == '_';
    }

    fn isIdentifierChar(c: u8) bool {
        return isAlpha(c) or isDigit(c) or c == '_';
    }

    fn toUpper(c: u8) u8 {
        return std.ascii.toUpper(c);
    }

    fn toUpperBuf(text: []const u8, buf: []u8) []const u8 {
        const len = @min(text.len, buf.len);
        for (0..len) |i| {
            buf[i] = std.ascii.toUpper(text[i]);
        }
        return buf[0..len];
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "empty source" {
    var lexer = Lexer.init("", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expectEqual(@as(usize, 1), lexer.tokens.items.len);
    try std.testing.expectEqual(Tag.end_of_file, lexer.tokens.items[0].tag);
}

test "simple PRINT statement" {
    var lexer = Lexer.init("PRINT \"Hello\"", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(lexer.tokens.items.len >= 3);
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.string, lexer.tokens.items[1].tag);
    try std.testing.expectEqualStrings("\"Hello\"", lexer.tokens.items[1].lexeme);
    try std.testing.expectEqual(Tag.end_of_file, lexer.tokens.items[lexer.tokens.items.len - 1].tag);
}

test "number literals" {
    var lexer = Lexer.init("42 3.14 1e10", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // 42, 3.14, 1e10, EOF
    try std.testing.expect(lexer.tokens.items.len >= 4);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[0].tag);
    try std.testing.expect(lexer.tokens.items[0].number_value == 42.0);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[1].tag);
    try std.testing.expect(lexer.tokens.items[1].number_value == 3.14);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[2].tag);
}

test "hex literals" {
    var lexer = Lexer.init("&HFF 0x1A", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(lexer.tokens.items.len >= 3);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[0].tag);
    try std.testing.expect(lexer.tokens.items[0].number_value == 255.0);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[1].tag);
    try std.testing.expect(lexer.tokens.items[1].number_value == 26.0);
}

test "operators" {
    var lexer = Lexer.init("+ - * / = <> <= >= < >", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    const expected = [_]Tag{
        .plus,      .minus,      .multiply,      .divide,    .equal,
        .not_equal, .less_equal, .greater_equal, .less_than, .greater_than,
    };
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, lexer.tokens.items[i].tag);
    }
}

test "delimiters" {
    var lexer = Lexer.init("( ) , ; : .", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    const expected = [_]Tag{ .lparen, .rparen, .comma, .semicolon, .colon, .dot };
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, lexer.tokens.items[i].tag);
    }
}

test "keywords are case-insensitive" {
    var lexer = Lexer.init("print Print PRINT", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[2].tag);
}

test "identifiers with type suffixes" {
    var lexer = Lexer.init("x% name$ y#", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // x%, name$, y# — each should produce identifier + suffix
    // x → identifier, % → type_int
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[0].tag);
    try std.testing.expectEqualStrings("x%", lexer.tokens.items[0].lexeme);
    try std.testing.expectEqual(Tag.type_int, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[2].tag);
    try std.testing.expectEqualStrings("name$", lexer.tokens.items[2].lexeme);
    try std.testing.expectEqual(Tag.type_string, lexer.tokens.items[3].tag);
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[4].tag);
    try std.testing.expectEqualStrings("y#", lexer.tokens.items[4].lexeme);
    try std.testing.expectEqual(Tag.type_double, lexer.tokens.items[5].tag);
}

test "end-of-line tokens" {
    var lexer = Lexer.init("PRINT\nEND\n", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // PRINT, EOL, END, EOL, EOF
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.kw_end, lexer.tokens.items[2].tag);
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[3].tag);
    try std.testing.expectEqual(Tag.end_of_file, lexer.tokens.items[4].tag);
}

test "compound END keywords" {
    var lexer = Lexer.init("END SUB\nEND FUNCTION\nEND TYPE\nEND IF", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expectEqual(Tag.kw_endsub, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.kw_endfunction, lexer.tokens.items[2].tag);
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[3].tag);
    try std.testing.expectEqual(Tag.kw_endtype, lexer.tokens.items[4].tag);
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[5].tag);
    try std.testing.expectEqual(Tag.kw_endif, lexer.tokens.items[6].tag);
}

test "REM comment skips to end of line" {
    var lexer = Lexer.init("REM this is a comment\nPRINT 42", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // REM line is skipped, then EOL, PRINT, 42, EOF
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[2].tag);
}

test "single-quote comment" {
    var lexer = Lexer.init("' this is a comment\nPRINT 42", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // Comment skipped, then EOL, PRINT, 42, EOF
    try std.testing.expectEqual(Tag.end_of_line, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[1].tag);
}

test "question mark is PRINT shorthand" {
    var lexer = Lexer.init("? \"hello\"", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.string, lexer.tokens.items[1].tag);
}

test "source locations are tracked" {
    var lexer = Lexer.init("PRINT\n  42", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // PRINT at line 1, col 1
    try std.testing.expectEqual(@as(u32, 1), lexer.tokens.items[0].location.line);
    try std.testing.expectEqual(@as(u32, 1), lexer.tokens.items[0].location.column);
    // 42 at line 2, col 3
    const num_tok = lexer.tokens.items[2]; // after PRINT and EOL
    try std.testing.expectEqual(@as(u32, 2), num_tok.location.line);
    try std.testing.expectEqual(@as(u32, 3), num_tok.location.column);
}

test "keyword with numeric suffix becomes identifier" {
    // SINGLE% should be an identifier, not kw_single + percent
    var lexer = Lexer.init("SINGLE% INTEGER# DOUBLE!", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    // SINGLE% → identifier "SINGLE%" + suffix .type_int
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[0].tag);
    try std.testing.expectEqualStrings("SINGLE%", lexer.tokens.items[0].lexeme);
    try std.testing.expectEqual(Tag.type_int, lexer.tokens.items[1].tag);
    // INTEGER# → identifier "INTEGER#" + suffix .type_double
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[2].tag);
    try std.testing.expectEqualStrings("INTEGER#", lexer.tokens.items[2].lexeme);
    try std.testing.expectEqual(Tag.type_double, lexer.tokens.items[3].tag);
    // DOUBLE! → identifier "DOUBLE!" + suffix .type_float
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[4].tag);
    try std.testing.expectEqualStrings("DOUBLE!", lexer.tokens.items[4].lexeme);
    try std.testing.expectEqual(Tag.type_float, lexer.tokens.items[5].tag);
}

test "keyword without suffix stays keyword" {
    // SINGLE, INTEGER, DOUBLE without suffix should remain keywords
    var lexer2 = Lexer.init("SINGLE INTEGER DOUBLE", std.testing.allocator);
    defer lexer2.deinit();
    try lexer2.tokenize();
    try std.testing.expectEqual(Tag.kw_single, lexer2.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.kw_integer, lexer2.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.kw_double, lexer2.tokens.items[2].tag);
}

test "dollar suffix makes keywords become identifiers" {
    // LEFT$, MID$, RIGHT$ should be tokenized as identifier + type_string
    // suffix, NOT as keyword tokens.  The parser's identifier path uses
    // isBuiltinFunction() to dispatch function calls when '(' follows,
    // and treats them as variables otherwise.
    var lexer3 = Lexer.init("LEFT$ MID$ RIGHT$", std.testing.allocator);
    defer lexer3.deinit();
    try lexer3.tokenize();
    // LEFT$  →  identifier "LEFT$" + type_string "$"
    try std.testing.expectEqual(Tag.identifier, lexer3.tokens.items[0].tag);
    try std.testing.expectEqualStrings("LEFT$", lexer3.tokens.items[0].lexeme);
    try std.testing.expectEqual(Tag.type_string, lexer3.tokens.items[1].tag);
    // MID$  →  identifier "MID$" + type_string "$"
    try std.testing.expectEqual(Tag.identifier, lexer3.tokens.items[2].tag);
    try std.testing.expectEqualStrings("MID$", lexer3.tokens.items[2].lexeme);
    try std.testing.expectEqual(Tag.type_string, lexer3.tokens.items[3].tag);
    // RIGHT$  →  identifier "RIGHT$" + type_string "$"
    try std.testing.expectEqual(Tag.identifier, lexer3.tokens.items[4].tag);
    try std.testing.expectEqualStrings("RIGHT$", lexer3.tokens.items[4].lexeme);
    try std.testing.expectEqual(Tag.type_string, lexer3.tokens.items[5].tag);
}

test "integer divide backslash" {
    var lexer = Lexer.init("10 \\ 3", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.int_divide, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[2].tag);
}

test "unterminated string produces error" {
    var lexer = Lexer.init("\"hello\n", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(lexer.hasErrors());
    // Should still produce a string token (for error recovery)
    try std.testing.expectEqual(Tag.string, lexer.tokens.items[0].tag);
}

test "bang-equals is not_equal" {
    var lexer = Lexer.init("x != 5", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.not_equal, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[2].tag);
}

test "complex expression" {
    var lexer = Lexer.init("IF x% > 10 AND y$ = \"hello\" THEN", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(!lexer.hasErrors());
    // IF, x%, %, >, 10, AND, y$, $, =, "hello", THEN, EOF
    try std.testing.expectEqual(Tag.kw_if, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[1].tag);
    try std.testing.expectEqual(Tag.type_int, lexer.tokens.items[2].tag);
    try std.testing.expectEqual(Tag.greater_than, lexer.tokens.items[3].tag);
    try std.testing.expectEqual(Tag.number, lexer.tokens.items[4].tag);
    try std.testing.expectEqual(Tag.kw_and, lexer.tokens.items[5].tag);
}

test "string value extraction" {
    const tok = Token{
        .tag = .string,
        .lexeme = "\"Hello World\"",
    };
    try std.testing.expectEqualStrings("Hello World", Lexer.stringValue(tok));
}

test "for loop tokens" {
    var lexer = Lexer.init("FOR i = 1 TO 10 STEP 2", std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    const expected = [_]Tag{
        .kw_for, .identifier, .equal, .number, .kw_to, .number, .kw_step, .number, .end_of_file,
    };
    try std.testing.expectEqual(expected.len, lexer.tokens.items.len);
    for (expected, 0..) |exp, i| {
        try std.testing.expectEqual(exp, lexer.tokens.items[i].tag);
    }
}

test "type declaration tokens" {
    const source = "TYPE Point\n  x AS DOUBLE\n  y AS DOUBLE\nEND TYPE";
    var lexer = Lexer.init(source, std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(!lexer.hasErrors());
    try std.testing.expectEqual(Tag.kw_type, lexer.tokens.items[0].tag);
    try std.testing.expectEqual(Tag.identifier, lexer.tokens.items[1].tag);
    try std.testing.expectEqualStrings("Point", lexer.tokens.items[1].lexeme);
}

test "create expression tokens" {
    const source = "DIM p AS Point = CREATE Point(1.0, 2.0)";
    var lexer = Lexer.init(source, std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(!lexer.hasErrors());
    try std.testing.expectEqual(Tag.kw_dim, lexer.tokens.items[0].tag);
    // Find CREATE token
    var found_create = false;
    for (lexer.tokens.items) |tok| {
        if (tok.tag == .kw_create) {
            found_create = true;
            break;
        }
    }
    try std.testing.expect(found_create);
}

test "no errors on valid program" {
    const source =
        \\PRINT "Hello from FasterBASIC!"
        \\DIM x AS INTEGER
        \\x = 42
        \\IF x > 10 THEN
        \\  PRINT x
        \\ENDIF
        \\END
    ;
    var lexer = Lexer.init(source, std.testing.allocator);
    defer lexer.deinit();
    try lexer.tokenize();
    try std.testing.expect(!lexer.hasErrors());
    try std.testing.expectEqual(Tag.kw_print, lexer.tokens.items[0].tag);
}
