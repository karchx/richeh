const std = @import("std");
const token = @import("token.zig");

pub const Associativity = struct { left: u8, right: u8 };

pub fn get_infix_bp(token_type: token.TokenType) ?Associativity {
    return switch (token_type) {
        .Equal => .{ .left = 1, .right = 2 },
        .Plus, .Minus => .{ .left = 3, .right = 4 },
        .Mult, .Div => .{ .left = 5, .right = 6 },
        else => null,
    };
}
