const std = @import("std");
const ast = @import("ast.zig");

fn print_indent(writer: *std.Io.Writer, depth: usize) !void {
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try writer.print("  ", .{});
    }
}

pub fn print_node(node: ast.Node, writer: *std.Io.Writer, depth: usize) !void {
    try print_indent(writer, depth);
    try writer.print("Node Type: {s}\n", .{@tagName(node.type)});

    switch (node.type) {
        .Expression => {
            if (node.node_variant != null and node.node_variant.?.exp.op.len > 0) {
                try print_indent(writer, depth + 1);
                try writer.print("Operator: {s}\n", .{node.node_variant.?.exp.op});
                if (node.node_variant.?.exp.left) |left| {
                    try print_indent(writer, depth + 1);
                    try writer.print("Left:\n", .{});
                    try print_node(left.*, writer, depth + 2);
                }
                if (node.node_variant.?.exp.right) |right| {
                    try print_indent(writer, depth + 1);
                    try writer.print("Right:\n", .{});
                    try print_node(right.*, writer, depth + 2);
                }
            }
        },
        .Number => {
            if (node.data) |data| {
                try print_indent(writer, depth + 1);
                try writer.print("Value: {d}\n", .{data.llnum});
            }
        },
        .Unary => {
            if (node.node_variant != null) {
                try print_indent(writer, depth + 1);
                try writer.print("Operator: {s}\n", .{node.node_variant.?.unary.op});
                try print_indent(writer, depth + 1);
                try writer.print("Operator: \n", .{});
                try print_node(node.node_variant.?.unary.operand.*, writer, depth + 2);
            }
        },
        .Variable => {
            if (node.node_variant.?.variable.name.items.len > 0) {
                try print_indent(writer, depth + 1);
                try writer.print("Name {s}\n", .{node.node_variant.?.variable.name.items});
            }

            if (node.node_variant.?.variable.val) |val| {
                try print_indent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try print_node(val.*, writer, depth + 2);
            }

        }
    }
}
