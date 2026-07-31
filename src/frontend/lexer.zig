const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const unicode = std.unicode;
const token = @import("token.zig");

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

        return Self{ .curr_exp_count = 0, .queued_token = null, .ifile = ifile, .allocator = a, .io = io };
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

    fn token_make_operator(self: *Self, c: ?u8) LexError!token.Token {
        _ = try self.peek_char();
        const sval = try self.read_op();
        const tempTokenPos = token.Pos{
            .col = 1,
            .line = 1,
            .start_col = 1,
            .end_col = 2,
            .end_line = 2,
            .filename = "mock",
        };

        return switch (c.?) {
            '+' => token.Token{ .type = .Plus, .data = .{ .sval = sval }, .pos = tempTokenPos },
            '-' => token.Token{ .type = .Minus, .data = .{ .sval = sval }, .pos = tempTokenPos },
            '*' => token.Token{ .type = .Mult, .data = .{ .sval = sval }, .pos = tempTokenPos },
            '/' => token.Token{ .type = .Div, .data = .{ .sval = sval }, .pos = tempTokenPos },
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
            .pos = token.Pos{
                .col = 1,
                .line = 1,
                .start_col = 1,
                .end_col = 2,
                .end_line = 2,
                .filename = "mock",
            },
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

    fn read_next_token(self: *Self) LexError!?token.Token {
        if (self.queued_token) |qt| {
            self.queued_token = null;
            self.current_token = qt;
            return qt;
        }

        var t = try self.handle_comment();
        std.debug.print("Token {any}\n", .{t});

        if (t != null) {
            t.?.pos.line = 1;
            return t;
        }

        const c = try self.peek_char();
        if (c == null) {
            return t;
        }

        switch (c.?) {
            '+', '-', '*', '/' => t = try self.token_make_operator(c),
            ' ', '\t', '\r' => t = try self.handle_whitespace(),
            else => {
                if (t == null) {
                    return LexError.InvalidCharacter;
                }
            },
        }

        self.current_token = t;
        return t;
    }

    pub fn lex(self: *Self) LexError!void {
        var t = try self.read_next_token();
        while (t != null) {
            t = try self.read_next_token();
        }
    }

    pub fn deinit(self: *Self) void {
        self.ifile.close(self.io);
    }
};
