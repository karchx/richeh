const std = @import("std");
const mem = std.mem;
const token = @import("token.zig");

pub const NodeType = enum {
    /// Represents an expression node.
    Expression,

    /// Represents a number node
    Number,
};

pub const BindedNode = struct {
    owner: ?*Node,
};

pub const Node = struct {
    type: NodeType,
    pos: ?token.Pos = null,
    data: ?token.TokenData = null,
    binded: ?*BindedNode = null,
    node_variant: ?union(enum) {
        /// The expresion node.
        exp: struct {
            left: ?*Node = null,
            right: ?*Node = null,
            op: []const u8,
        },
    } = null,
};

/// Checks if the is a value type.
///
/// This functions determines if the given node (`n`) is of a value type, which includes:
/// - Number
pub fn node_is_value_type(n: Node) bool {
    return n.type == .Number;
}

pub fn node_is_expressionable(n: Node) bool {
    return n.type == .Expression or n.type == .Number;
}
