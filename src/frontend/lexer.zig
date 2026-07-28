const std = @import("std");

pub const Lexer = struct {
    pub fn read_token() void {
        std.debug.print("Lexer read_token", .{});
    }
};
