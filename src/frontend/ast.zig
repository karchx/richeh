const std = @import("std");
const mem = std.mem;
const token = @import("token.zig");

/// Compatibility shim: ArrayList with embedded allocator (old-style managed API).
fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const NodeFlags = packed struct {
    /// Indicates if the tnode is inside an expression.
    inside_expression: bool = false,

    /// Indicates if the node has a combined variable.
    has_variable_combined: bool = false,
};

pub const NodeType = enum {
    /// Represents an expression node.
    Expression,
    /// Represents a number node
    Number,
    /// Represents a unary node.
    Unary,
    /// Represents a variable node.
    Variable,
};

pub const BindedNode = struct {
    owner: ?*Node,
};

pub const Node = struct {
    flags: ?NodeFlags = null,
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

        /// The unary node.
        unary: struct {
            op: []const u8,
            operand: *Node,
        },

        /// The variable node.
        variable: struct {
            name: ArrayList(u8),
            val: ?*Node = null
        }
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
