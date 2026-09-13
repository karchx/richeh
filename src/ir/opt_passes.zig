const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const IrError = builder.IrError;
const VReg = builder.VReg;
const IrOpCode = builder.IrOpCode;
const IrInstruction = builder.IrInstruction;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

const FlatLattice = enum { Top, Const, Bottom };

/// LatticeValue ∈ {⊤, c, ⊥}.
const LatticeValue = union(FlatLattice) {
    Top,
    Const: u32,
    Bottom,
};

const BlockId = u32;

const BasicBlock = struct {
    id: BlockId,
    instructions: ArrayList(IrInstruction),
    successors: ArrayList(BlockId),
    predecessors: ArrayList(BlockId),
};

const CFG = struct {
    blocks: ArrayList(BasicBlock),
    entry: BlockId,
};

pub const OptPasses = struct {
    allocator: mem.Allocator,
    know_const: std.AutoHashMap(VReg, LatticeValue),
    know_symbol: std.StringHashMap(LatticeValue),
    value_to_vreg: std.AutoHashMap(u32, VReg),

    const Self = @This();

    pub fn init(allocator: mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .know_const = std.AutoHashMap(VReg, LatticeValue).init(allocator),
            .know_symbol = std.StringHashMap(LatticeValue).init(allocator),
            .value_to_vreg = std.AutoHashMap(u32, VReg).init(allocator),
        };
    }

    pub fn valueNumbering(self: *Self, ir_instructions: *[]IrInstruction) !void {
        var ir_vn = ArrayList(IrInstruction).init(self.allocator);
        defer ir_vn.deinit();

        for (ir_instructions.*) |inst| {
            switch (inst) {
                .Imm => |val| {
                    const vn_imm = self.value_to_vreg.get(val.imm_val);
                    if (vn_imm == null) {
                        try self.value_to_vreg.put(val.imm_val, val.dest);
                        try self.append_opt_pass(&ir_vn, inst);
                    }
                },
                else => try self.append_opt_pass(&ir_vn, inst),
            }
        }

        ir_instructions.* = try ir_vn.toOwnedSlice();
    }

    pub fn constantFolding(self: *Self, ir_instructions: *[]IrInstruction) !void {
        var ir_pass = ArrayList(IrInstruction).init(self.allocator);
        defer ir_pass.deinit();

        for (ir_instructions.*) |inst| {
            switch (inst) {
                .Imm => |val| {
                    try self.know_const.put(val.dest, .{ .Const = val.imm_val });
                    try self.append_opt_pass(&ir_pass, inst);
                },
                .Store => |s| {
                    const val = self.know_const.get(s.src);
                    if (val) |lat| {
                        if (lat == .Const) try self.know_symbol.put(s.symbol, lat);
                    }
                },
                .Load => |l| {
                    const val = self.know_symbol.get(l.symbol);
                    if (val) |lat| {
                        if (lat == .Const) {
                            const new_v = l.dest;
                            try self.know_const.put(new_v, lat);
                            try self.append_opt_pass(&ir_pass, .{ .Imm = .{ .dest = new_v, .imm_val = lat.Const } });
                            continue;
                        }
                    }
                    try self.append_opt_pass(&ir_pass, inst);
                },
                .Shl => |op| {
                    const val1 = self.know_const.get(op.src1) orelse .Top;
                    const val2 = self.know_const.get(op.src2) orelse .Top;

                    if (val1 == .Const and val2 == .Const) {
                        const result_shl = val1.Const << @intCast(val2.Const);
                        try self.append_opt_pass(&ir_pass, .{ .Imm = .{ .dest = op.dest, .imm_val = result_shl } });
                    } else {
                        try self.append_opt_pass(&ir_pass, inst);
                    }
                },
                else => try self.append_opt_pass(&ir_pass, inst),
            }
        }

        ir_instructions.* = try ir_pass.toOwnedSlice();
    }

    fn append_opt_pass(_: *Self, data: *ArrayList(IrInstruction), instr: IrInstruction) IrError!void {
        data.append(instr) catch return IrError.MemoryAllocationFailed;
    }
};
