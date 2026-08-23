const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const ast = @import("frontend").ast;
const IrError = builder.IrError;
const VReg = builder.VReg;
const IrOpCode = builder.IrOpCode;
const IrInstruction = builder.IrInstruction;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const Gen = struct {
    builder_proc: *builder.IrBuilder,
    statements: []const *ast.Node,

    const Self = @This();

    pub fn init(builder_proc: *builder.IrBuilder, stmts: []const *ast.Node) IrError!Self {
        return Self{ .builder_proc = builder_proc, .statements = stmts };
    }

    pub fn generateInstruction(self: *Self) IrError![]const IrInstruction {
        for (self.statements) |stmt| {
            _ = try self.visit(stmt);
        }

        if (self.builder_proc.instructions.items.len > 0) {
            return self.builder_proc.instructions.items;
        } else {
            return IrError.NotInstructionsYet;
        }
    }

    fn visit(self: *Self, node: *const ast.Node) IrError!?VReg {
        return switch (node.variant) {
            .program => null,
            .number => |num| {
                const reg = self.builder_proc.allocReg();
                const parsed_val = switch (num) {
                    .llnum => |l| @as(u32, @intCast(l)),
                    .sval => |s| std.fmt.parseInt(u32, s.items, 16) catch {
                        return IrError.MemoryAllocationFailed;
                    },
                    else => 0,
                };

                try self.builder_proc.emit(.{
                    .Imm = .{ .dest = reg, .imm_val = parsed_val },
                });
                return reg;
            },
            .exp => |e| {
                const left_reg = (try self.visit(e.left.?)).?;
                const right_reg = (try self.visit(e.right.?)).?;

                const reg = self.builder_proc.allocReg();
                const opcode = self.getOpCode(e.op) orelse return IrError.NotImplementedOp;

                const instruction: IrInstruction = switch (opcode) {
                    inline .Add, .Mult => |comptime_op| @unionInit(
                        IrInstruction,
                        @tagName(comptime_op),
                        .{ .dest = reg, .src1 = left_reg, .src2 = right_reg },
                    ),
                    else => unreachable,
                };

                try self.builder_proc.emit(instruction);
                return reg;
            },
            .identifier => |id| {
                const reg = self.builder_proc.allocReg();
                try self.builder_proc.emit(.{
                    .Load = .{ .dest = reg, .symbol = id.sval.items },
                });
                return reg;
            },
            .assignment_statement => |assign| {
                const val_reg = (try self.visit(assign.val)).?;
                try self.builder_proc.emit(.{
                    .Store = .{ .src = val_reg, .symbol = assign.target },
                });

                return null;
            },
            .out_statement => |out| {
                const mask_pin = switch (out.addr.variant) {
                    .number => |val| @as(c_longlong, 1) << @intCast(val.llnum),
                    else => 0,
                };

                var mask_pin_hex = ast.Node{
                    .variant = .{
                        .number = .{
                            .llnum = mask_pin,
                        },
                    },
                };
                const mask_pin_reg = (try self.visit(&mask_pin_hex)).?;

                var val_base_addrs = ArrayList(u8).init(self.builder_proc.allocator);
                defer val_base_addrs.deinit();
                // BASE ADDRESS ESP32-S3: 0x60004000
                val_base_addrs.appendSlice("60004000") catch {
                    return IrError.MemoryAllocationFailed;
                };

                var base_addr = ast.Node{
                    .variant = .{
                        .number = .{
                            .sval = val_base_addrs,
                        },
                    },
                };

                const base_addr_reg = (try self.visit(&base_addr)).?;

                // SET OUTPUT PIN
                // 36 = 0x24
                try self.builder_proc.emit(.{
                    .VolatileStore = .{ .base_addr = base_addr_reg, .pin = mask_pin_reg, .offset = 36 },
                });

                // offset pulse for HIGH or LOW
                // HIGH = 8 = 0x08
                // LOW = 12 = 0x0C
                const offset_pulse: VReg = switch (out.val.variant) {
                    .number => |val| if (val.llnum == 1) 8 else 12,
                    else => 0,
                };
                try self.builder_proc.emit(.{
                    .VolatileStore = .{ .base_addr = base_addr_reg, .pin = mask_pin_reg, .offset = offset_pulse },
                });
                return null;
            },
            else => null,
        };
    }

    fn getOpCode(_: *Self, operator: []const u8) ?IrOpCode {
        const clean_operator = mem.trim(u8, operator, " \r\n\t\x00");
        if (mem.eql(u8, clean_operator, "+")) {
            return .Add;
        } else if (mem.eql(u8, clean_operator, "*")) {
            return .Mult;
        } else {
            return null;
        }
    }
};
