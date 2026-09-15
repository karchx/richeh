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
    env: std.StringHashMap(VReg),

    const Self = @This();

    pub fn init(builder_proc: *builder.IrBuilder, stmts: []const *ast.Node) IrError!Self {
        return Self{
            .builder_proc = builder_proc,
            .statements = stmts,
            .env = std.StringHashMap(VReg).init(builder_proc.allocator),
        };
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
            .assignment_statement => |assign| {
                const val_reg = (try self.visit(assign.val)).?;
                try self.builder_proc.emit(.{
                    .Store = .{ .src = val_reg, .symbol = assign.target },
                });
                self.env.put(assign.target, val_reg) catch return IrError.MemoryAllocationFailed;

                return null;
            },
            .identifier => |id| {
                if (self.env.get(id.sval.items)) |reg| {
                    return reg;
                }
                const reg = self.builder_proc.allocReg();
                try self.builder_proc.emit(.{
                    .Load = .{ .dest = reg, .symbol = id.sval.items },
                });
                return reg;
            },
            .out_statement => |out| {
                const pin_reg = (try self.visit(out.addr)).?;

                const mask_key = std.fmt.allocPrint(self.builder_proc.allocator, "mask_{d}", .{pin_reg}) catch return IrError.MemoryAllocationFailed;
                const mask_reg = if (self.env.get(mask_key)) |existing|
                    existing
                else blk: {
                    const one = self.builder_proc.allocReg();
                    try self.builder_proc.emit(.{ .Imm = .{ .dest = one, .imm_val = 1 } });

                    const new_mask = self.builder_proc.allocReg();
                    try self.builder_proc.emit(.{ .Shl = .{ .dest = new_mask, .src1 = one, .src2 = pin_reg } });
                    self.env.put(mask_key, new_mask) catch return IrError.MemoryAllocationFailed;
                    break :blk new_mask;
                };

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
                const wait_key = std.fmt.allocPrint(self.builder_proc.allocator, "delay_{d}", .{ticks}) catch return IrError.MemoryAllocationFailed;

                const reg = if (self.env.get(wait_key)) |existing|
                    existing
                else blk: {
                    const new_reg = self.builder_proc.allocReg();

                    try self.builder_proc.emit(.{
                        .LoadLiteral = .{ .dest = new_reg, .literal_val = ticks },
                    });
                    self.env.put(wait_key, new_reg) catch return IrError.MemoryAllocationFailed;
                    break :blk new_reg;
                };

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
