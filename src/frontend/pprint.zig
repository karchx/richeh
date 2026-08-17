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
        .program => |prog| {
            try print_indent(writer, depth + 1);
            try writer.print("Statements: \n", .{});
            for (prog.statements) |stmt| {
                try print_node(stmt.*, writer, depth + 2);
            }
        },
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
        .assignment => |assign| {
            try print_indent(writer, depth + 1);
            try writer.print("Target: {s}\n", .{assign.target});
            try print_indent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try print_node(assign.val.*, writer, depth + 2);
        },
        .expr_statement => |stmt| {
            try print_indent(writer, depth + 1);
            try writer.print("Expression Statement:\n", .{});
            try print_node(stmt.expr.*, writer, depth + 2);
        },
        .out_statement => |stmt| {
            for (stmt.val) |val| {
                try print_node(val.*, writer, depth + 1);
            }
            try print_indent(writer, depth + 1);
            try writer.print("Addr: {s}\n", .{stmt.addr});
        },
        .identifier => |data| {
            try print_indent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{data.sval.items});
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
            // for (matrix.elements) |el| {
            //     try print_node(el.*, writer, depth + 2);
            // }
        },
    }
}
