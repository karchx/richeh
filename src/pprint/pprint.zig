const std = @import("std");
const ast = @import("frontend").ast;
const IrInstruction = @import("ir").builder.IrInstruction;

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
        .assignment_statement => |assign| {
            try print_indent(writer, depth + 1);
            try writer.print("Target: {s}\n", .{assign.target});
            try print_indent(writer, depth + 1);
            try writer.print("Value:\n", .{});
            try print_node(assign.val.*, writer, depth + 2);
        },
        .out_statement => |stmt| {
            try print_node(stmt.val.*, writer, depth + 1);
            try print_indent(writer, depth + 1);
            try writer.print("TargetAddress: \n", .{});
            try print_node(stmt.addr.*, writer, depth + 2);
        },
        .wait_statement => |wstmt| {
            try print_indent(writer, depth + 1);
            try writer.print("Time (sec): \n", .{});
            try print_node(wstmt.seconds.*, writer, depth + 2);
        },
        .identifier => |data| {
            try print_indent(writer, depth + 1);
            try writer.print("Name: {s}\n", .{data.sval.items});
        },
        .number => |data| {
            try print_indent(writer, depth + 1);
            switch (data) {
                .llnum => |num| try writer.print("Value: {d}\n", .{num}),
                .sval => |str| try writer.print("Value: {s}\n", .{str.items}),
                else => try writer.print("Value: Unknow", .{}),
            }
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

pub fn print_ir_code(inst: IrInstruction, writer: *std.Io.Writer) !void {
    switch (inst) {
        .Imm => |imm| try writer.print("v{d} = IMM({d})\n", .{ imm.dest, imm.imm_val }),
        .Load => |load| try writer.print("v{d} = LOAD(\"{s}\")\n", .{ load.dest, load.symbol }),
        .LoadLiteral => |llit| try writer.print("v{d} = LOADLIT({d})\n", .{ llit.dest, llit.literal_val }),
        .Mult => |op| try writer.print("v{d} = MULT(v{d}, v{d})\n", .{ op.dest, op.src1, op.src2 }),
        .Add => |op| try writer.print("v{d} = ADD(v{d}, v{d})\n", .{ op.dest, op.src1, op.src2 }),
        .Store => |store| try writer.print("STORE(v{d}, \"{s}\")\n", .{ store.src, store.symbol }),
        .VolatileStore => |vs| try writer.print("VolatileStore(base_addr=v{d}, pin=v{d}, offset={d})\n", .{ vs.base_addr, vs.pin, vs.offset }),
        .Loop => |loop| try writer.print("{s} = LOOP(v{})\n", .{ loop.tag, loop.src }),
    }
}
