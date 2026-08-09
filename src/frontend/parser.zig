const std = @import("std");
const mem = std.mem;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const token = @import("token.zig");
const op_table = @import("operator_precedence.zig");
const LexError = lexer.LexError;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

/// Errors that cant occur during parsing process.
pub const ParseError = error{
    ///
    InvalidSymbol,
    InvalidKeyword,
    InvalidToken,
    InvalidOperand,
    InvalidIdentifier,
    UnexpectedEOF,
} || LexError;

pub const Parse = struct {
    lexer_proc: *lexer.Lexer,
    parser_last_token: token.Token = undefined,
    parser_current_body: ?ast.Node = null,
    forward_type_names: ?std.StringHashMap(void) = null,

    const Self = @This();

    pub fn init(lexer_proc: *lexer.Lexer) Self {
        return Self{
            .lexer_proc = lexer_proc,
        };
    }

    fn ignore_nl_or_comment(self: *Self, t: *?token.Token) void {
        while (t.* != null and token.is_nl_or_comment_or_newline_separator(t.*)) {
            _ = self.lexer_proc.tokens.peek(); // skip token
            t.* = self.lexer_proc.tokens.peek_no_increment();
        }
    }

    /// Retrieves the next token.
    ///
    /// This function peeks at the next token without incrementing the token stream's position.
    /// It ignores newline or comment tokens and updates the current position if a valid token is found.
    fn token_next(self: *Self) ?token.Token {
        var next_token = self.lexer_proc.tokens.peek_no_increment();
        self.ignore_nl_or_comment(&next_token);
        if (next_token != null) {
            self.parser_last_token = next_token.?;
        }
        next_token = self.lexer_proc.tokens.peek();
        self.lexer_proc.current_token = next_token;
        return next_token;
    }

    fn token_peek_next(self: *Self) ?token.Token {
        var next_token = self.lexer_proc.tokens.peek_no_increment();
        self.ignore_nl_or_comment(&next_token);
        const peek_token = self.lexer_proc.tokens.peek_no_increment();
        self.lexer_proc.current_token = peek_token;
        return peek_token;
    }

    fn create_identifier_node(_: *Self, tok: token.Token) ParseError!ast.Node {
        return ast.Node{
            .type = .Identifier,
            .pos = tok.pos,
            .data = tok.data,
            .node_variant = null,
        };
    }

    fn create_number_node(_: *Self, tok: token.Token) ParseError!ast.Node {
        return ast.Node{
            .type = .Number,
            .pos = tok.pos,
            .data = tok.data,
            .node_variant = null,
        };
    }

    fn create_binary_node(self: *Self, op_str: []const u8, left: ast.Node, right: ast.Node) ParseError!ast.Node {
        const left_ptr = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        left_ptr.* = left;

        const right_ptr = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        right_ptr.* = right;

        return ast.Node{
            .type = .Expression,
            .node_variant = .{
                .exp = .{
                    .left = left_ptr,
                    .right = right_ptr,
                    .op = op_str,
                },
            },
        };
    }

    fn parse_expr(self: *Self, min_bp: u8) ParseError!ast.Node {
        const tok = self.token_next() orelse return ParseError.UnexpectedEOF;

        var left = try switch (tok.type) {
            .Number => self.create_number_node(tok),
            .Identifier => self.create_identifier_node(tok),
            else => return ParseError.InvalidToken,
        };

        while (true) {
            const next_token = self.token_peek_next() orelse break;
            const bp = op_table.get_infix_bp(next_token.type) orelse break;

            if (bp.left < min_bp) break;

            // consume token
            _ = self.token_next();
            switch (next_token.type) {
                .Plus, .Minus, .Mult, .Div, .Equal => {
                    const right = try self.parse_expr(bp.right);
                    left = try self.create_binary_node(next_token.data.sval.items, left, right);
                },
                else => unreachable,
            }
        }

        return left;
    }

    fn next(self: *Self) ParseError!bool {
        const t = self.token_peek_next() orelse return false;

        try switch (t.type) {
            .Number, .Identifier => {
                // Pratt get control for expression
                const expr_node = try self.parse_expr(0);
                self.lexer_proc.nodes.push(expr_node) catch {
                    return ParseError.MemoryAllocationFailed;
                };
            },
            .NewLine => {
                _ = self.token_next();
            },
            else => ParseError.InvalidToken,
        };
        return true;
    }

    /// This function repeatedly processes tokens until there are no more tokens
    /// to process.
    fn prescan_forward_type_names(self: *Self) void {
        if (self.forward_type_names != null) return;
        var set = std.StringHashMap(void).init(self.lexer_proc.allocator);
        const items = self.lexer_proc.tokens.items();
        var i: usize = 0;
        while (i < items.len) : (i += 1) {
            var j = i + 1;
            while (j < items.len) : (j += 1) {}
            if (j < items.len and items[j].type == .Identifier) {
                set.put(items[j].data.sval.items, {}) catch {
                    set.deinit();
                    return;
                };
            }
        }
        self.forward_type_names = set;
    }

    pub fn parse(self: *Self) ParseError!void {
        self.prescan_forward_type_names();
        while (try self.next()) {}
    }
};
