const std = @import("std");
const mem = std.mem;
const token = @import("token.zig");

/// Compatibility shim: ArrayList with embedded allocator (old-style managed API).
fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const Node = struct {
    pos: ?token.Pos = null,
    variant: Variant,

    pub const Variant = union(enum) {
        /// The root node.
        program: struct {
            statements: []const *Node,
        },
        expr_statement: struct {
            expr: *Node,
        },
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
        assignment: struct {
            target: []const u8,
            val: *Node,
        },
        // The matrix node.
        matrix: struct {
            rows: usize,
            cols: usize,
            elements: []const *Node,
        },
        number: token.TokenData,
        identifier: token.TokenData,
    };
};

/// Checks if the is a value type.
///
/// This functions determines if the given node (`n`) is of a value type, which includes:
/// - Number
pub fn node_is_value_type(n: Node) bool {
    return n.type == .Number;
}

pub fn node_is_assignment(n: Node) bool {
    if (n.type != .Expression) {
        return false;
    }

    const op = n.node_variant.?.exp.op;
    return mem.eql(u8, "=", op);
}

pub fn node_is_expressionable(n: Node) bool {
    return n.type == .Expression or n.type == .Number;
}
