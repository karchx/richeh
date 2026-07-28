const std = @import("std");
const frontend = @import("frontend");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    frontend.lexer.Lexer.read_token();
}
