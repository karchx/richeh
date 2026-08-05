const std = @import("std");
const mem = std.mem;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const token = @import("token.zig");
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
} || LexError;

pub const Parse = struct {
    lexer_proc: *lexer.Lexer,
    parser_last_token: token.Token = undefined,
    parser_current_body: ?ast.Node = null,
    forward_type_names: ?std.StringHashMap(void) = null,
    // TODO: change nodes to codegen or another module (?

    const Self = @This();

    pub fn init(lexer_proc: *lexer.Lexer) Self {
        return Self{
            .lexer_proc = lexer_proc,
        };
    }

    fn is_unary_operator(op: []const u8) bool {
        return mem.eql(u8, "-", op) or mem.eql(u8, "+", op) or
            mem.eql(u8, "*", op) or mem.eql(u8, "/", op);
    }

    fn ignore_nl_or_comment(self: *Self, t: *?token.Token) void {
        while (t.* != null and token.is_nl_or_comment_or_newline_separator(t.*)) {
            _ = self.lexer_proc.tokens.peek(); // skip token
            t.* = self.lexer_proc.tokens.peek_no_increment();
        }
    }

    fn create_node(self: *Self, n: *ast.Node) ParseError!void {
        var is_bound = false;
        var binded: ast.BindedNode = .{
            .owner = null,
        };

        if (self.parser_current_body) |body| {
            if (body.binded != null) {
                const owner = self.lexer_proc.allocator.create(ast.Node) catch {
                    return ParseError.MemoryAllocationFailed;
                };
                errdefer self.lexer_proc.allocator.destroy(owner);
                owner.* = body;
                owner.*.binded = null;
                owner.*.data = null;
                binded.owner = owner;
                is_bound = true;
            }
        }
        if (is_bound) {
            const b = self.lexer_proc.allocator.create(ast.BindedNode) catch {
                return ParseError.MemoryAllocationFailed;
            };
            errdefer self.lexer_proc.allocator.destroy(b);
            b.*.owner = binded.owner;
            n.binded = b;
        } else {
            n.binded = null;
        }

        self.lexer_proc.nodes.push(n.*) catch {
            return ParseError.MemoryAllocationFailed;
        };
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

    /// Peeks at the expressionable node on top of the stack.
    ///
    /// This functions returns the node on top of the stack if it is expressionable,
    /// or `null` otherwise.
    fn node_peek_expressionable_or_null(self: *Self) ?ast.Node {
        const n = self.lexer_proc.nodes.back();
        return if (n != null and ast.node_is_expressionable(n.?)) n.? else null;
    }

    fn node_pop(self: *Self) ?ast.Node {
        const last_node = self.lexer_proc.nodes.back();
        self.lexer_proc.nodes.pop();
        return last_node;
    }

    fn make_expression_node(self: *Self, left_node: *ast.Node, right_node: *ast.Node, op: []const u8, op_pos: ?token.Pos) ParseError!void {
        const exp_node = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        defer self.lexer_proc.allocator.destroy(exp_node);
        const left = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        left.* = left_node.*;
        const right = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        errdefer self.lexer_proc.allocator.destroy(right);
        right.* = right_node.*;
        exp_node.* = ast.Node{
            .type = .Expression,
            .pos = op_pos orelse left.*.pos orelse right.*.pos,
            .node_variant = .{
                .exp = .{
                    .left = left,
                    .right = right,
                    .op = op,
                },
            },
        };
        try self.create_node(exp_node);
    }

    fn parse_single_token_to_node(self: *Self) ParseError!bool {
        const t = self.token_next();
        if (t == null) {
            std.debug.print("expected token, got eof\n", .{});
            return ParseError.InvalidToken;
        }

        switch (t.?.type) {
            .Number => {
                switch (t.?.data) {
                    .llnum => |n| {
                        var number_node = ast.Node{
                            .type = .Number,
                            .pos = t.?.pos,
                            .data = .{ .llnum = n },
                        };
                        try self.create_node(&number_node);
                    },
                    else => {
                        std.debug.print("invalid number token\n", .{});
                        return ParseError.InvalidToken;
                    },
                }
            },
            else => {
                std.debug.print("[PARSER]: expected single token, got '{s}'", .{@tagName(t.?.type)});
                return ParseError.InvalidToken;
            },
        }
        return true;
    }

    fn parse_for_normal_unary(self: *Self) ParseError!void {
        const unary_tok = self.token_next();
        const unary_op = unary_tok.?.data.sval.items;

        try self.parse_expressionable();
        const unary_operand_node = self.node_pop() orelse {
            return ParseError.InvalidOperand;
        };
        const operand = self.lexer_proc.allocator.create(ast.Node) catch {
            return ParseError.MemoryAllocationFailed;
        };
        errdefer self.lexer_proc.allocator.destroy(operand);
        operand.* = unary_operand_node;
        self.lexer_proc.nodes.push(ast.Node{
            .type = .Unary,
            .pos = unary_tok.?.pos,
            .node_variant = .{
                .unary = .{
                    .op = unary_op,
                    .operand = operand,
                },
            },
        }) catch {
            return ParseError.MemoryAllocationFailed;
        };
    }

    fn parse_for_unary(self: *Self) ParseError!void {
        _ = self.token_peek_next();
        try self.parse_for_normal_unary();
    }

    fn parse_expression(self: *Self) ParseError!bool {
        var t = self.token_peek_next();
        if (t == null) return false;

        const op = t.?.data.sval.items;
        const op_pos = t.?.pos;
        var node_left = self.node_peek_expressionable_or_null();

        _ = self.token_next(); // skip operator
        _ = self.node_pop();

        node_left.?.flags = .{ .inside_expression = true };
        t = self.token_peek_next();
        if (t == null) {
            return ParseError.InvalidOperand;
        }

        // Operator type
        if (t.?.type == .Plus or t.?.type == .Minus or t.?.type == .Mult or t.?.type == .Div) {
            try self.parse_for_unary();
        } else {
            try self.parse_expressionable();
        }

        var node_right = self.node_pop() orelse {
            return ParseError.InvalidOperand;
        };
        node_right.flags = .{ .inside_expression = true };
        try self.make_expression_node(&node_left.?, &node_right, op, op_pos);
        const exp_node = self.node_pop() orelse {
            return ParseError.InvalidExpression;
        };
        self.lexer_proc.nodes.push(exp_node) catch {
            return ParseError.MemoryAllocationFailed;
        };

        return true;
    }

    fn parse_variable(self: *Self) ParseError!bool {
        const ident_token = self.token_next();
        const t = self.token_peek_next();

        if (ident_token == null or ident_token.?.type != .Identifier) {
            std.debug.print("expected identifier\n", .{});
            return ParseError.InvalidIdentifier;
        }

        // Variable node.
        var name = ArrayList(u8).initCapacity(self.lexer_proc.allocator, ident_token.?.data.sval.items.len) catch {
            return ParseError.MemoryAllocationFailed;
        };
        errdefer name.deinit();
        name.appendSlice(ident_token.?.data.sval.items) catch {
            return ParseError.MemoryAllocationFailed;
        };
        // var value_node: ?ast.Node = null;
        const has_value = token.is_operator(t, "=");
        std.debug.print("Token: {s}\n", .{t.?.data.sval.items});
        std.debug.print("has value, {}\n", .{has_value});
        return true;
    }

    fn parse_expressionable_single(self: *Self) ParseError!bool {
        // TODO: validation expr depth and max parse expr depth
        const t = self.token_peek_next();
        if (t == null) {
            return false;
        }

        return switch (t.?.type) {
            .Number => try self.parse_single_token_to_node(),
            .Plus, .Minus, .Mult, .Div => try self.parse_expression(),
            .Identifier => try self.parse_variable(),
            else => false,
        };
    }

    fn parse_expressionable(self: *Self) ParseError!void {
        while (try self.parse_expressionable_single()) {}
    }

    fn next(self: *Self) ParseError!bool {
        const t = self.token_peek_next();
        if (t == null) {
            return false;
        }
        switch (t.?.type) {
            .Number, .Identifier => {
                try self.parse_expressionable();
            },
            else => {
                return ParseError.InvalidToken;
            },
        }
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
