const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const IrInstruction = builder.IrInstruction;
const VReg = builder.VReg;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

const BlockId = u32;

const BasicBlock = struct {
    Id: BlockId,
    Instructions: ArrayList(IrInstruction),
    Successors: ArrayList(BlockId),
    Predecessors: ArrayList(BlockId),
};

const InstRef = struct { block: BlockId, index: usize };

pub const CFG = struct {
    allocator: mem.Allocator,
    blocks: ArrayList(BasicBlock),
    entry: BlockId,
    next_id: BlockId,
    ir_instructions: *[]IrInstruction,
    defs: std.AutoHashMap(VReg, InstRef),
    work_list_seed: ArrayList(InstRef),

    const Self = @This();

    pub fn init(allocator: mem.Allocator, ir_instructions: *[]IrInstruction) !Self {
        return Self{
            .allocator = allocator,
            .blocks = ArrayList(BasicBlock).init(allocator),
            .entry = 0,
            .next_id = 0,
            .ir_instructions = ir_instructions,
            .defs = std.AutoHashMap(VReg, InstRef).init(allocator),
            .work_list_seed = ArrayList(InstRef).init(allocator),
        };
    }

    fn allocNextId(self: *Self) BlockId {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    pub fn build(self: *Self) !void {
        try self.basicBlocks();
        try self.buildEdges();
        try self.buildDefUse();
        try self.deadCode();
    }

    fn basicBlocks(self: *Self) !void {
        const leaders = try self.computeLeaders();

        defer self.allocator.free(leaders);

        var current: ?BasicBlock = null;

        for (self.ir_instructions.*, 0..) |instr, idx| {
            if (leaders[idx]) {
                var instr_list = ArrayList(IrInstruction).init(self.allocator);
                if (current) |b| {
                    try self.blocks.append(b);
                }

                try instr_list.append(instr);

                current = self.createBlock(
                    instr_list,
                );
                if (idx == 0) {
                    self.entry = current.?.Id;
                }
            } else {
                try current.?.Instructions.append(instr);
            }
        }
        if (current) |b| try self.blocks.append(b);
    }

    fn buildEdges(self: *Self) !void {
        var label_map = std.StringHashMap(BlockId).init(self.allocator);
        defer label_map.deinit();

        for (self.blocks.items) |bb| {
            for (bb.Instructions.items) |instr| {
                if (instr == .Label) {
                    const label_name = instr.Label;
                    try label_map.put(label_name, bb.Id);
                }
            }
        }

        for (self.blocks.items, 0..) |*bb, idx| {
            const last_instr = bb.Instructions.items[bb.Instructions.items.len - 1];
            switch (last_instr) {
                .Jump => |target| {
                    if (label_map.get(target)) |blockId| {
                        try bb.Successors.append(blockId);
                    }
                },
                // TODO: add return, condional(jump, branch)
                else => {
                    if (idx + 1 < self.blocks.items.len) {
                        const blockId = self.blocks.items[idx + 1].Id;
                        try bb.Successors.append(blockId);
                    }
                },
            }
        }

        for (self.blocks.items) |*bb| {
            for (bb.Successors.items) |succ_id| {
                try self.blocks.items[succ_id].Predecessors.append(bb.Id);
            }
        }
    }

    fn buildDefUse(self: *Self) !void {
        for (self.blocks.items) |bb| {
            for (bb.Instructions.items, 0..) |instr, idx| {
                const ref = InstRef{ .block = bb.Id, .index = idx };

                switch (instr) {
                    .Imm => |v| {
                        try self.defs.put(v.dest, ref);
                    },
                    .Add => |v| {
                        try self.defs.put(v.dest, ref);
                    },
                    .VolatileStore, .Jump, .CallExternal, .LoadLiteral => {
                        try self.work_list_seed.append(ref);
                    },
                    .Label, .Store => {},
                    else => {},
                }
            }
        }
    }

    fn deadCode(self: *Self) !void {
        var live = std.AutoHashMap(InstRef, void).init(self.allocator);
        defer live.deinit();

        var work = ArrayList(InstRef).init(self.allocator);
        defer work.deinit();

        for (self.work_list_seed.items) |ref| {
            try live.put(ref, {});
            try work.append(ref);
        }

        while (work.pop()) |ref| {
            const instr = self.blocks.items[ref.block].Instructions.items[ref.index];

            const used_vregs = try self.getUsedVRegs(instr);
            for (used_vregs) |v| {
                if (self.defs.get(v)) |def_ref| {
                    const gop = try live.getOrPut(def_ref);
                    if (!gop.found_existing) {
                        try work.append(def_ref);
                    }
                }
            }
        }

        try self.sweep(live);
    }

    fn sweep(self: *Self, live: std.AutoHashMap(InstRef, void)) !void {
        var new_ir = ArrayList(IrInstruction).init(self.allocator);

        for (self.blocks.items) |bb| {
            for (bb.Instructions.items, 0..) |instr, idx| {
                const ref = InstRef{ .block = bb.Id, .index = idx };
                if (live.contains(ref) or instr == .Label) {
                    try new_ir.append(instr);
                }
            }
        }

        self.ir_instructions.* = try new_ir.toOwnedSlice();
    }

    fn createBlock(self: *Self, instr: ArrayList(IrInstruction)) BasicBlock {
        const id = self.allocNextId();

        return BasicBlock{
            .Id = id,
            .Instructions = instr,
            .Successors = ArrayList(BlockId).init(self.allocator),
            .Predecessors = ArrayList(BlockId).init(self.allocator),
        };
    }

    fn computeLeaders(self: *Self) ![]bool {
        var label_map = std.StringHashMap(usize).init(self.allocator);
        defer label_map.deinit();

        for (self.ir_instructions.*, 0..) |instr, idx| {
            if (instr == .Label) {
                const label_name = instr.Label;

                try label_map.put(label_name, idx);
            }
        }

        const len_instr = self.ir_instructions.len;
        var is_leader = try self.allocator.alloc(bool, len_instr);
        @memset(is_leader, false);
        // first instr is always leader
        is_leader[0] = true;

        for (self.ir_instructions.*, 0..) |instr, idx| {
            switch (instr) {
                .Jump => |target| {
                    if (label_map.get(target)) |target_idx| {
                        is_leader[target_idx] = true;
                    }

                    if (idx + 1 < len_instr) {
                        is_leader[idx + 1] = true;
                    }
                },
                else => {},
            }
        }

        return is_leader;
    }

    fn getUsedVRegs(self: *Self, instr: IrInstruction) ![]VReg {
        var used_vregs = ArrayList(VReg).init(self.allocator);
        errdefer used_vregs.deinit();
        switch (instr) {
            .Add => |v| {
                try used_vregs.append(v.src1);
                try used_vregs.append(v.src2);
            },
            .Mult => |v| {
                try used_vregs.append(v.src1);
                try used_vregs.append(v.src2);
            },
            .VolatileStore => |v| {
                try used_vregs.append(v.pin);
            },
            .CallExternal => |v| {
                try used_vregs.append(v.src);
            },
            else => {},
        }

        const used_vregs_list = try used_vregs.toOwnedSlice();
        return used_vregs_list;
    }

    pub fn dump(self: *const Self) void {
        std.debug.print("CFG (entry = {d})\n", .{self.entry});
        for (self.blocks.items) |bb| {
            std.debug.print("BB {d}:\n", .{bb.Id});
            for (bb.Instructions.items) |instr| {
                switch (instr) {
                    .Label => |val| std.debug.print(" .Label = {s}\n", .{val}),
                    .Jump => |val| std.debug.print("  .Jump = {s}\n", .{val}),
                    else => std.debug.print("  {any}\n", .{instr}),
                }
            }
            std.debug.print("  succ: ", .{});
            for (bb.Successors.items) |s| std.debug.print("{d} ", .{s});
            std.debug.print("\n  pred: ", .{});
            for (bb.Predecessors.items) |p| std.debug.print("{d} ", .{p});
            std.debug.print("\n\n", .{});
        }
    }
};
