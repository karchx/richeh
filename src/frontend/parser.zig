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
    InvalidAssignment,
    InvalidMatrixDimensions,
    UnexpectedEOF,
} || LexError;

pub const Parse = struct {
    lexer_proc: *lexer.Lexer,
    parser_last_token: token.Token = undefined,

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
            .pos = tok.pos,
            .variant = .{ .identifier = tok.data },
        };
    }

    fn create_number_node(_: *Self, tok: token.Token) ParseError!ast.Node {
        return ast.Node{
            .pos = tok.pos,
            .variant = .{ .number = tok.data },
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
            .variant = .{ .exp = .{
                .left = left_ptr,
                .right = right_ptr,
                .op = op_str,
            } },
        };
    }

    fn create_variable_node(self: *Self, left: ast.Node, right: ast.Node) ParseError!ast.Node {
        const right_ptr = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        right_ptr.* = right;

        const ident_name = left.variant.identifier.sval;

        return ast.Node{
            .pos = left.pos,
            .variant = .{
                .variable = .{
                    .name = ident_name,
                    .val = right_ptr,
                },
            },
        };
    }

    fn parse_group_or_matrix(self: *Self, tok: token.Token) ParseError!ast.Node {
        const next_tok = self.token_peek_next() orelse return ParseError.UnexpectedEOF;

        // If the next token distint LParen is simple operations
        // e.g: (5 * 5)
        if (next_tok.type != .LParen) {
            const expr = try self.parse_expr(0);
            const rparen = self.token_next() orelse return ParseError.UnexpectedEOF;
            if (rparen.type != .RParen) return ParseError.InvalidToken;
            return expr;
        }

        var elements_list = ArrayList(*ast.Node).init(self.lexer_proc.allocator);
        errdefer elements_list.deinit();

        var rows: usize = 0;
        var cols: usize = 0;

        // rows
        while (true) {
            _ = self.token_next();
            var current_cols: usize = 0;

            // columns
            while (true) {
                const node_val = try self.parse_expr(0);

                const node_ptr = self.lexer_proc.allocator.create(ast.Node) catch return ParseError.MemoryAllocationFailed;
                node_ptr.* = node_val;

                elements_list.append(node_ptr) catch return ParseError.MemoryAllocationFailed;
                current_cols += 1;

                const delim = self.token_next() orelse return ParseError.UnexpectedEOF;
                if (delim.type == .Semicolon) {
                    continue;
                } else if (delim.type == .RParen) {
                    break;
                } else {
                    return ParseError.InvalidToken;
                }
            }

            if (rows == 0) {
                cols = current_cols;
            } else if (cols != current_cols) {
                return ParseError.InvalidMatrixDimensions;
            }

            rows += 1;

            const row_delim = self.token_next() orelse return ParseError.UnexpectedEOF;
            if (row_delim.type == .Comma) {
                continue;
            } else if (row_delim.type == .RParen) {
                break;
            } else {
                return ParseError.InvalidToken;
            }
        }

        const element_slice = elements_list.toOwnedSlice() catch {
            return ParseError.MemoryAllocationFailed;
        };

        return ast.Node{
            .pos = tok.pos,
            .variant = .{
                .matrix = .{
                    .cols = rows,
                    .rows = cols,
                    .elements = element_slice,
                },
            },
        };
    }

    fn parse_prefix(self: *Self, tok: token.Token) ParseError!ast.Node {
        return try switch (tok.type) {
            .Number => self.create_number_node(tok),
            .Identifier => self.create_identifier_node(tok),
            .LParen => try self.parse_group_or_matrix(tok),
            else => return ParseError.InvalidToken,
        };
    }

    fn parse_infix(self: *Self, initial_left: ast.Node, min_bp: u8) ParseError!ast.Node {
        var left = initial_left;
        while (true) {
            const next_token = self.token_peek_next() orelse break;
            const bp = op_table.get_infix_bp(next_token.type) orelse break;

            if (bp.left < min_bp) break;

            // consume token
            _ = self.token_next();
            switch (next_token.type) {
                .Plus, .Minus, .Mult, .Div => {
                    const right = try self.parse_expr(bp.right);
                    left = try self.create_binary_node(next_token.data.sval.items, left, right);
                },
                .Equal => {
                    switch (left.variant) {
                        .identifier => {
                            const right = try self.parse_expr(bp.right);
                            left = try self.create_variable_node(left, right);
                        },
                        else => return ParseError.InvalidAssignment,
                    }
                },
                else => unreachable,
            }
        }
        return left;
    }

    fn parse_expr(self: *Self, min_bp: u8) ParseError!ast.Node {
        const tok = self.token_next() orelse return ParseError.UnexpectedEOF;

        const left = try self.parse_prefix(tok);
        return try self.parse_infix(left, min_bp);
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

    pub fn parse(self: *Self) ParseError!void {
        while (try self.next()) {}
    }
};
