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
    try writer.print("Node Type: {s}\n", .{@tagName(node.variant)});

    switch (node.variant) {
        .exp => |exp| {
            if (exp.op.len > 0) {
                try print_indent(writer, depth + 1);
                try writer.print("Operator: {s}\n", .{exp.op});
                if (exp.left) |left| {
                    try print_indent(writer, depth + 1);
                    try writer.print("Left:\n", .{});
                    try print_node(left.*, writer, depth + 2);
                }
                if (exp.right) |right| {
                    try print_indent(writer, depth + 1);
                    try writer.print("Right:\n", .{});
                    try print_node(right.*, writer, depth + 2);
                }
            }
        },
        .variable => |variable| {
            if (variable.name.items.len > 0) {
                try print_indent(writer, depth + 1);
                try writer.print("Name {s}\n", .{variable.name.items});
            }

            if (variable.val) |val| {
                try print_indent(writer, depth + 1);
                try writer.print("Value:\n", .{});
                try print_node(val.*, writer, depth + 2);
            }
        },
        .identifier => |data| {
            try print_indent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{data.sval.items});
        },
        .statement => {
            try print_indent(writer, depth + 1);
            try writer.print("Statement\n", .{});
        },
        .number => |data| {
            try print_indent(writer, depth + 1);
            try writer.print("Value: {d}\n", .{data.llnum});
        },
        .unary => |unary| {
            try print_indent(writer, depth + 1);
            try writer.print("Operator: {s}\n", .{unary.op});
            try print_indent(writer, depth + 1);
            try writer.print("Operator: \n", .{});
            try print_node(unary.operand.*, writer, depth + 2);
        },
        .matrix => {
            try print_indent(writer, depth + 1);
            try writer.print("Matrix\n", .{});
        },
    }
}
