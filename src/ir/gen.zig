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
    gpio_base: VReg = 0,

    const Self = @This();

    pub fn init(builder_proc: *builder.IrBuilder, stmts: []const *ast.Node) IrError!Self {
        return Self{ .builder_proc = builder_proc, .statements = stmts };
    }

    pub fn generateInstruction(self: *Self) IrError![]IrInstruction {
        const gpio_reg = self.builder_proc.constAddress() catch return IrError.MemoryAllocationFailed;
        self.gpio_base = gpio_reg;

        for (self.statements) |stmt| {
            switch (stmt.variant) {
                .main_loop => |loop| {
                    try self.builder_proc.emit(.{
                        .Label = ".main_loop",
                    });
                    for (loop.statements) |main_stmt| {
                        _ = try self.visit(main_stmt);
                    }
                    try self.builder_proc.emit(.{
                        .Jump = ".main_loop",
                    });
                },
                else => {},
            }
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
                const parsed_val = switch (num) {
                    .llnum => |l| @as(u32, @intCast(l)),
                    .sval => |s| std.fmt.parseInt(u32, s.items, 16) catch {
                        return IrError.MemoryAllocationFailed;
                    },
                    else => 0,
                };

                const loaded_reg = self.builder_proc.lvn_map.get(parsed_val);
                if (loaded_reg) |find_reg| return find_reg;

                const reg = self.builder_proc.allocReg();
                self.builder_proc.lvn_map.put(parsed_val, reg) catch return IrError.MemoryAllocationFailed;

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
                const pin_reg = (try self.visit(out.addr)).?;

                const one = self.builder_proc.allocReg();
                try self.builder_proc.emit(.{ .Imm = .{ .dest = one, .imm_val = 1 } });

                const mask_reg = self.builder_proc.allocReg();
                try self.builder_proc.emit(.{ .Shl = .{ .dest = mask_reg, .src1 = one, .src2 = pin_reg } });

                const base_addr_reg = self.gpio_base;

                // SET OUTPUT PIN
                // 36 = 0x24
                try self.builder_proc.emit(.{
                    .VolatileStore = .{ .base_addr = base_addr_reg, .pin = mask_reg, .offset = 36 },
                });

                // offset pulse for HIGH or LOW
                // HIGH = 8 = 0x08
                // LOW = 12 = 0x0C
                const offset_pulse: VReg = switch (out.val.variant) {
                    .number => |val| if (val.llnum == 1) 8 else 12,
                    else => 0,
                };

                try self.builder_proc.emit(.{
                    .VolatileStore = .{ .base_addr = base_addr_reg, .pin = mask_reg, .offset = offset_pulse },
                });

                return null;
            },
            .wait_statement => |wait| {
                const FREQ_CPU_DEFAULT: u32 = 100; // FREQ IN Hz
                const seconds: u32 = @intCast(wait.seconds.variant.number.llnum);
                const ticks = seconds * FREQ_CPU_DEFAULT;
                const reg = self.builder_proc.allocReg();

                try self.builder_proc.emit(.{
                    .LoadLiteral = .{ .dest = reg, .literal_val = ticks },
                });

                try self.builder_proc.emit(.{
                    .CallExternal = .{ .src = reg, .target = "vTaskDelay" },
                });
                return reg;
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
