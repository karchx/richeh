const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const ast = @import("frontend").ast;
const IrError = builder.IrError;
const VReg = builder.VReg;
const IrOpCode = builder.IrOpCode;

pub const Gen = struct {
    builder_proc: *builder.IrBuilder,
    statements: []const *ast.Node,

    const Self = @This();

    pub fn init(builder_proc: *builder.IrBuilder, stmts: []const *ast.Node) IrError!Self {
        return Self{
            .builder_proc = builder_proc,
            .statements = stmts
        };
    }

    pub fn generate_instruction(self: *Self) IrError!void {
        for (self.statements) |stmt| {
            _ = try self.visit(stmt);
        }
    }

    fn visit(self: *Self, node: *const ast.Node) IrError!?VReg {
        return switch (node.variant) {
            .program => null,
            .number => |num| {
                const reg = self.builder_proc.allocReg();
                const parsed_val = switch(num) {
                    .llnum => |l| @as(u32, @intCast(l)),
                    .sval => |s| std.fmt.parseInt(u32, s.items, 10) catch { return IrError.MemoryAllocationFailed; },
                    else => 0
                };

                try self.builder_proc.emit(.{
                    .op = .Imm,
                    .dest = reg,
                    .imm_val = parsed_val,
                });
                return reg;
            },
            .assignment_statement => |assign| {
                const val_operand = try self.visit(assign.val);
                try self.builder_proc.emit(.{
                    .op = .Store,
                    .symbol = assign.target,
                    .src1 = val_operand.?,
                });

                return null;
            },
            .exp => |e| {
                const left_reg = (try self.visit(e.left.?)).?;
                const right_reg = (try self.visit(e.right.?)).?;

                const reg = self.builder_proc.allocReg();
                const opcode = self.getOpCode(e.op);

                try self.builder_proc.emit(.{
                    .op = opcode.?,
                    .dest = reg,
                    .src1 = left_reg,
                    .src2 = right_reg,
                });
                return reg;
            },
            else => null
        };
    }

    fn getOpCode(_: *Self, operator: []const u8) ?IrOpCode {
        if (mem.eql(u8, operator, "+")) { 
            return .Add;
        } else if (mem.eql(u8, operator, "*")) {
            return .Mult;
        } else {
            return null;
        }
    }
};