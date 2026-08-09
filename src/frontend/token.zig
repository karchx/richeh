const std = @import("std");
const mem = std.mem;
pub const TokenType = enum {
    /// An identifier, variable or function name
    Identifier,
    /// Operator '='
    Equal,
    /// Operator '+'
    Plus,
    /// Operator '-'
    Minus,
    /// Operator '*'
    Mult,
    /// Operator '/'
    Div,
    /// A symbol, such as parentheses, braces, etc.
    Symbol,
    /// A numeric literal.
    Number,
    /// An comment XD.
    Comment,
    /// An newline
    NewLine,

    /// End of line
    EOF,
};

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

// Represents the position of a token in the source code.
pub const Pos = struct {
    line: u32,
    col: u32,
    start_col: u32,
    end_col: u32,
    end_line: u32 = 0,
    filename: []const u8,
};

pub const TokenData = union(enum) {
    /// A single character value.
    cval: u8,
    /// A string value.
    sval: ArrayList(u8),
    /// An integer value.
    inum: c_int,
    /// A long integer value.
    lnum: c_long,
    /// A long long integer value.
    llnum: c_longlong,
    /// A double-precision floating-point value.
    dnum: f64,
    /// A bool value.
    bval: bool,
};

pub const Token = struct {
    type: TokenType,
    data: TokenData,
    pos: Pos,
    whitespace: bool = false,
};

pub fn is_operator(token: ?Token, val: []const u8) bool {
    const t = token orelse return false;

    const trim_items = std.mem.trim(u8, t.data.sval.items, " \t\r\n\x00");

    if (!mem.eql(u8, trim_items, val)) return false;

    return switch (t.type) {
        .Plus, .Div, .Mult, .Minus, .Equal => true,
        else => false,
    };
}

pub fn is_nl_or_comment_or_newline_separator(token: ?Token) bool {
    if (token == null) {
        return false;
    }

    return token.?.type == .NewLine or
        token.?.type == .Comment;
}
