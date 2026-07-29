const std = @import("std");
const ascii = std.ascii;
const unicode = std.unicode;
const Token = @import("token.zig").Token;

pub const Lexer = struct {
    it: unicode.Utf8Iterator,

    fn isIdentifier(c: u32) bool {
        return switch (c) {
            'a'...'z',
            'A'...'Z',
            '_',
            '0'...'9',
            => true,
            else => false,
        };
    }

    pub fn next(self: *Lexer) !Token {
        var start_index = self.it.i;
        var state: enum {
            start,
            identifier,
            equal,
            plus,
        } = .start;

        var res: Token.Id = .eof;
        var str_delimit: u32 = undefined;

        while (self.it.nextCodepoint()) |c| {
            switch (state) {
                .start => switch (c) {
                    '#' => state = .line_comment,
                },
            }
        }
    }
};
