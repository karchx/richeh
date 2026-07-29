pub const Token = struct {
    start: u32,
    end: u32,
    id: Id,

    pub const Id = enum(u8) { eof, identifier, equal, plus };

    pub fn string(id: Id) []const u8 {
        return switch (id) {
            .eof => "<EOF>",
            .identifier => "IDENTIFIER",
            .equal => "=",
            .plus => "+",
        };
    }
};
