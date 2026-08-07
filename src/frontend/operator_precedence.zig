const std = @import("std");

pub const Associativity = enum { LeftToRight, RightToLeft };

pub const MAX_OPERATORS_IN_GROUP = 12;

pub const TOTAL_OPERATORS_GROUP = 14;

pub const OpPrecedenceGroup = struct {
    operators: [MAX_OPERATORS_IN_GROUP]?[]const u8,
    associativity: ?Associativity = null,
};

pub const op_precedence = [_]OpPrecedenceGroup{
    OpPrecedenceGroup{
        .operators = [_]?[]const u8{ "*", "/", null, null, null, null, null, null, null, null, null, null },
        .associativity = .LeftToRight,
    },
    OpPrecedenceGroup{
        .operators = [_]?[]const u8{ "+", "-", null, null, null, null, null, null, null, null, null, null },
        .associativity = .LeftToRight,
    },
    OpPrecedenceGroup{
        .operators = [_]?[]const u8{ "=", null, null, null, null, null, null, null, null, null, null, null },
        .associativity = .RightToLeft,
    },
};
