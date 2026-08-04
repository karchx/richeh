const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const unicode = std.unicode;
const token = @import("token.zig");
const ast = @import("ast.zig");
const lib = @import("lib");
const Vector = lib.vector.Vector;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const LexError = error{
    ///
    InvalidOperator,
    InvalidNumber,
    InvalidExpression,
    FileReadError,
    FileOpenError,
    MemoryAllocationFailed,
    InvalidCharacter,
};

pub const Lexer = struct {
    queued_token: ?token.Token = null,
    curr_exp_count: isize,
    // TODO: change ifile, io allocator, to codegen or another module (?
    ifile: std.Io.File,
    io: std.Io,
    allocator: mem.Allocator,
    current_token: ?token.Token = null,
    file_offset: u64 = 0,
    tokens: Vector(token.Token),
    nodes: Vector(ast.Node),
    pos: token.Pos,

    const Self = @This();

    fn globalIo() std.Io {
        return std.Io.Threaded.global_single_threaded.io();
    }

    pub fn init(allocator: mem.Allocator, ifilepath: []const u8) LexError!Self {
        const io = globalIo();
        const ifile = blk: {
            const is_abs = std.fs.path.isAbsolute(ifilepath);
            if (is_abs) {
                break :blk std.Io.Dir.openFileAbsolute(io, ifilepath, .{ .mode = .read_only }) catch {
                    return LexError.FileOpenError;
                };
            }
            break :blk std.Io.Dir.cwd().openFile(io, ifilepath, .{ .mode = .read_only }) catch {
                return LexError.FileOpenError;
            };
        };
        errdefer ifile.close(io);

        const arena_ptr = allocator.create(std.heap.ArenaAllocator) catch {
            return LexError.MemoryAllocationFailed;
        };
        errdefer allocator.destroy(arena_ptr);
        arena_ptr.* = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_ptr.deinit();
        const a = arena_ptr.allocator();

        const input_file_path = a.dupe(u8, ifilepath) catch {
            return LexError.MemoryAllocationFailed;
        };
        errdefer a.free(input_file_path);

        return Self{
            .curr_exp_count = 0,
            .queued_token = null,
            .ifile = ifile,
            .allocator = a,
            .io = io,
            .tokens = Vector(token.Token).init(a),
            .nodes = Vector(ast.Node).init(a),
            .pos = .{ .col = 1, .line = 1, .start_col = 1, .end_col = 1, .filename = input_file_path },
        };
    }

    fn in_expression(self: *Self) bool {
        return self.curr_exp_count > 0;
    }

    fn next_char(self: *Self) LexError!?u8 {
        var buffer: [1]u8 = undefined;
        const readBytes = self.ifile.readPositionalAll(self.io, &buffer, self.file_offset) catch {
            return LexError.FileReadError;
        };

        if (readBytes == 0) {
            return null;
        }
        self.file_offset += 1;

        const c = buffer[0];
        if (c == '\n') {
            self.pos.line += 1;
            self.pos.col = 1;
        } else {
            self.pos.col += 1;
        }

        return c;
    }

    fn peek_char(self: *Self) LexError!?u8 {
        var buffer: [1]u8 = undefined;
        const readBytes = self.ifile.readPositionalAll(self.io, &buffer, self.file_offset) catch {
            return LexError.FileReadError;
        };

        return if (readBytes == 0) null else buffer[0];
    }

    fn read_op(self: *Self) LexError!ArrayList(u8) {
        var buffer = ArrayList(u8).init(self.allocator);
        const op0 = (try self.next_char()) orelse {
            return LexError.InvalidOperator;
        };
        buffer.append(op0) catch {
            return LexError.MemoryAllocationFailed;
        };
        const pc = try self.peek_char();
        if (pc != null) {
            buffer.append(pc.?) catch {
                return LexError.MemoryAllocationFailed;
            };
            _ = try self.next_char();
        }

        return buffer;
    }

    /// Reads characters from the input file based on a given condition.
    fn getc_if(self: *Self, buffer: *ArrayList(u8), exp: fn (u8) bool) LexError!void {
        while (true) {
            const c = try self.peek_char();
            if (c == null or !exp(c.?)) break;
            buffer.append(c.?) catch {
                return LexError.MemoryAllocationFailed;
            };

            _ = try self.next_char();
        }
    }

    fn read_number_str(self: *Self) LexError!ArrayList(u8) {
        var raw = ArrayList(u8).init(self.allocator);
        defer raw.deinit();

        try self.getc_if(&raw, struct {
            fn call(_c: u8) bool {
                return ascii.isDigit(_c) or _c == '_';
            }
        }.call);

        var buffer = ArrayList(u8).init(self.allocator);
        for (raw.items) |c| {
            if (c == '_') continue;
            buffer.append(c) catch return LexError.MemoryAllocationFailed;
        }

        return buffer;
    }

    fn read_number(self: *Self) LexError!c_longlong {
        const s = try self.read_number_str();
        defer s.deinit();

        const number: c_longlong = std.fmt.parseInt(c_longlong, s.items, 10) catch {
            return LexError.InvalidNumber;
        };
        return number;
    }

    fn token_make_number_from_string(self: *Self, number_str: []const u8) LexError!?token.Token {
        const v: c_longlong = std.fmt.parseInt(c_longlong, number_str, 10) catch {
            return LexError.InvalidNumber;
        };

        _ = try self.next_char();

        return token.Token{
            .type = .Number,
            .data = .{ .llnum = v },
            .pos = self.pos,
        };
    }

    fn token_make_number(self: *Self) LexError!?token.Token {
        var buffer = try self.read_number_str();
        defer buffer.deinit();

        if (buffer.items.len == 0) {
            buffer.append('0') catch {
                return LexError.MemoryAllocationFailed;
            };
        }

        return try self.token_make_number_from_string(buffer.items);
    }

    fn token_make_operator(self: *Self) LexError!token.Token {
        const c = try self.peek_char();
        const sval = try self.read_op();

        return switch (c.?) {
            '+' => token.Token{ .type = .Plus, .data = .{ .sval = sval }, .pos = self.pos },
            '-' => token.Token{ .type = .Minus, .data = .{ .sval = sval }, .pos = self.pos },
            '*' => token.Token{ .type = .Mult, .data = .{ .sval = sval }, .pos = self.pos },
            '/' => token.Token{ .type = .Div, .data = .{ .sval = sval }, .pos = self.pos },
            else => undefined,
        };
    }

    fn token_make_comment(self: *Self) LexError!token.Token {
        var buffer = ArrayList(u8).init(self.allocator);
        try self.getc_if(&buffer, struct {
            fn call(_c: u8) bool {
                return _c != '\n' and _c != '\r';
            }
        }.call);

        return token.Token{
            .type = .Comment,
            .data = .{
                .sval = buffer,
            },
            .pos = self.pos,
        };
    }

    fn token_make_newline(self: *Self) LexError!token.Token {
        _ = try self.next_char();
        return token.Token{
            .type = .NewLine,
            .data = .{ .cval = '\n' },
            .pos = self.pos,
        };
    }

    /// Creates an identifier or keyword token from the input file.
    /// It then checks if the collected characters form a keyword or an identifier and
    /// returns the corresponding token.
    ///
    // TODO: validate keywords tokens
    fn token_make_identifier_or_keyword(self: *Self) LexError!?token.Token {
        var buffer = ArrayList(u8).init(self.allocator);
        try self.getc_if(&buffer, struct {
            fn call(_c: u8) bool {
                return ascii.isAlphabetic(_c) or ascii.isDigit(_c) or _c == '_';
            }
        }.call);

        return token.Token{
            .type = .Identifier,
            .data = .{ .sval = buffer },
            .pos = self.pos,
        };
    }

    fn handle_comment(self: *Self) LexError!?token.Token {
        const c = try self.peek_char();
        if (c == '-') {
            _ = try self.next_char();
            const nxt = try self.peek_char();
            if (nxt == '-') {
                _ = try self.next_char();
                return try self.token_make_comment();
            }
        }

        return null;
    }

    fn handle_whitespace(self: *Self) LexError!?token.Token {
        var last_token = self.tokens.back();
        if (last_token != null) {
            _ = self.tokens.pop();
            last_token.?.whitespace = true;
            self.tokens.push(last_token.?) catch {
                return LexError.MemoryAllocationFailed;
            };
        }

        _ = try self.next_char();
        return self.read_next_token();
    }

    fn read_special_token(self: *Self) LexError!?token.Token {
        const c = try self.peek_char();
        if (c == null) {
            return null;
        }

        if (ascii.isAlphabetic(c.?) or c.? == '_') {
            return null;
        }
        return null;
    }

    fn read_next_token(self: *Self) LexError!?token.Token {
        if (self.queued_token) |qt| {
            self.queued_token = null;
            self.current_token = qt;
            return qt;
        }

        var t = try self.handle_comment();

        const start_line = self.pos.line;
        const start_col = self.pos.col;

        if (t != null) {
            t.?.pos.line = start_line;
            t.?.pos.col = start_col;
            t.?.pos.start_col = start_col;
            t.?.pos.end_line = self.pos.line;
            t.?.pos.end_col = self.pos.col;
            return t;
        }

        const c = try self.peek_char();
        if (c == null) {
            return t;
        }

        switch (c.?) {
            '+', '-', '*', '/' => t = try self.token_make_operator(),
            '0'...'9' => t = try self.token_make_number(),
            '\n' => t = try self.token_make_newline(),
            ' ', '\t', '\r' => t = try self.handle_whitespace(),
            else => {
                t = try self.read_special_token();
                if (t == null) {
                    return LexError.InvalidCharacter;
                }
            },
        }

        if (t != null) {
            t.?.pos.line = start_line;
            t.?.pos.col = start_col;
            t.?.pos.start_col = start_col;
            t.?.pos.end_line = self.pos.line;
            t.?.pos.end_col = self.pos.col;
        }

        self.current_token = t;
        return t;
    }

    pub fn lex(self: *Self) LexError!void {
        var t = try self.read_next_token();
        while (t != null) {
            self.tokens.push(t.?) catch {
                return LexError.MemoryAllocationFailed;
            };
            t = try self.read_next_token();
        }
    }

    pub fn deinit(self: *Self) void {
        self.ifile.close(self.io);
    }
};
