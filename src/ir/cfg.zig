const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const InterferenceGraph = @import("interference_graph.zig").InterferenceGraph;
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
    Def: std.DynamicBitSet,
    Use: std.DynamicBitSet,
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
    live_in: std.AutoHashMap(BlockId, std.DynamicBitSet),
    live_out: std.AutoHashMap(BlockId, std.DynamicBitSet),
    precolored: std.AutoHashMap(VReg, u8),
    assignment: std.AutoHashMap(VReg, i32),
    graph: InterferenceGraph,

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
            .live_in = std.AutoHashMap(BlockId, std.DynamicBitSet).init(allocator),
            .live_out = std.AutoHashMap(BlockId, std.DynamicBitSet).init(allocator),
            .precolored = std.AutoHashMap(VReg, u8).init(allocator),
            .assignment = std.AutoHashMap(VReg, i32).init(allocator),
            .graph = InterferenceGraph.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.graph.deinit();
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

    pub fn computeLiveness(self: *Self) !void {
        try self.computeLocalLiveness();

        for (self.blocks.items) |bb| {
            try self.live_in.put(bb.Id, try std.DynamicBitSet.initEmpty(self.allocator, 128));
            try self.live_out.put(bb.Id, try std.DynamicBitSet.initEmpty(self.allocator, 128));
        }

        var changed = true;

        while (changed) {
            changed = false;

            var i = self.blocks.items.len;
            while (i > 0) {
                i -= 1;
                const bb = &self.blocks.items[i];

                var new_out = try std.DynamicBitSet.initEmpty(self.allocator, 128);
                for (bb.Successors.items) |succ_id| {
                    if (self.live_in.get(succ_id)) |succ_in| {
                        new_out.setUnion(succ_in);
                    }
                }

                var new_in = try new_out.clone(self.allocator);

                var def_it = bb.Def.iterator(.{});

                while (def_it.next()) |bit| {
                    new_in.unset(bit);
                }
                new_in.setUnion(bb.Use);

                const old_in = self.live_in.getPtr(bb.Id).?;
                const old_out = self.live_out.getPtr(bb.Id).?;

                if (!new_in.eql(old_in.*) or !new_out.eql(old_out.*)) {
                    changed = true;
                    old_in.* = new_in;
                    old_out.* = new_out;
                } else {
                    new_in.deinit();
                    new_out.deinit();
                }
            }
        }
    }

    pub fn computePrecolored(self: *Self) !void {
        const ARG0_COLOR: u8 = 4;
        for (self.blocks.items) |bb| {
            for (bb.Instructions.items) |instr| {
                switch (instr) {
                    .CallExternal => |val| {
                        try self.precolored.put(val.src, ARG0_COLOR);
                    },
                    else => {},
                }
            }
        }
    }

    pub fn buildInterference(self: *Self) !void {
        for (0..self.next_id) |v| {
            try self.graph.ensureNode(@intCast(v));
        }

        for (self.blocks.items) |bb| {
            var live = try self.live_out.get(bb.Id).?.clone(self.allocator);
            defer live.deinit();

            var i = bb.Instructions.items.len;
            while (i > 0) {
                i -= 1;
                const instr = bb.Instructions.items[i];

                if (self.getDestVReg(instr)) |d| {
                    var live_it = live.iterator(.{});
                    while (live_it.next()) |v| {
                        if (v != d) try self.graph.addEdge(d, @intCast(v));
                    }
                    live.unset(d);
                }

                const used_vregs = try self.getUsedVRegs(instr);
                for (used_vregs) |u| {
                    live.set(u);
                }
            }
        }

        var simply_stack = try self.simplify(14);
        defer simply_stack.deinit();
        try self.select(&simply_stack, 14);
    }

    fn filterDegreeK(self: *Self, K: u32) !ArrayList(VReg) {
        var kList = ArrayList(VReg).init(self.allocator);

        var nodes_it = self.graph.nodes();

        while (nodes_it.next()) |current| {
            if (self.graph.getDegree(current.*) < K) {
                try kList.append(current.*);
            }
        }

        return kList;
    }

    fn nodesActives(self: *Self) !std.AutoHashMap(VReg, void) {
        var actives = std.AutoHashMap(VReg, void).init(self.allocator);
        var nodes = self.graph.nodes();
        while (nodes.next()) |v| {
            try actives.put(v.*, {});
        }

        return actives;
    }

    fn simplify(self: *Self, K: u32) !ArrayList(VReg) {
        var current_degree = try self.graph.degree.clone();
        defer current_degree.deinit();

        var actives = try self.nodesActives();
        defer actives.deinit();

        var stack = ArrayList(VReg).init(self.allocator);
        var work_list = try self.filterDegreeK(K);
        defer work_list.deinit();

        while (work_list.pop()) |v| {
            if (!actives.contains(v)) continue;

            try stack.append(v);
            _ = actives.remove(v);

            const neighbors = self.graph.adj.getPtr(v) orelse continue;
            var it = neighbors.iterator();
            while (it.next()) |entry| {
                const n = entry.key_ptr.*;
                if (!actives.contains(n)) continue;

                const deg = current_degree.getPtr(n).?;
                deg.* -= 1;
                if (deg.* == K - 1) {
                    try work_list.append(n);
                }
            }
        }
        return stack;
    }

    fn select(self: *Self, stack: *ArrayList(VReg), K: u32) !void {
        self.assignment.clearRetainingCapacity();
        var used = try std.DynamicBitSet.initEmpty(self.allocator, K);
        defer used.deinit();

        while (stack.pop()) |v| {
            used.setRangeValue(.{ .start = 0, .end = K }, false);

            if (self.precolored.get(v)) |forced| {
                const neighbors = self.graph.adj.get(v) orelse {
                    try self.assignment.put(v, forced);
                    continue;
                };

                var conflict = false;
                var it = neighbors.keyIterator();
                while (it.next()) |n| {
                    if (self.assignment.get(n.*)) |c| {
                        if (c == forced) {
                            conflict = true;
                            break;
                        }
                    }
                }
                if (conflict) {
                    try self.assignment.put(v, -1);
                } else {
                    try self.assignment.put(v, forced);
                }
                continue;
            }

            const neighbors = self.graph.adj.get(v) orelse continue;
            var it_n = neighbors.keyIterator();
            while (it_n.next()) |n| {
                if (self.assignment.get(n.*)) |c| {
                    if (c >= 0) used.set(@intCast(c));
                }
            }

            var assigned: i32 = -1;
            for (0..K) |c| {
                if (!used.isSet(c)) {
                    assigned = @intCast(c);
                    break;
                }
            }
            try self.assignment.put(v, assigned);
        }
    }

    fn computeLocalLiveness(self: *Self) !void {
        for (self.blocks.items) |*bb| {
            var i: usize = bb.Instructions.items.len;

            while (i > 0) {
                i -= 1;
                const instr = bb.Instructions.items[i];

                if (self.getDestVReg(instr)) |d| {
                    bb.Def.set(d);
                    bb.Use.unset(d);
                }

                const used_vregs = try self.getUsedVRegs(instr);
                for (used_vregs) |u| {
                    bb.Use.set(u);
                }
            }
        }
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

                current = try self.createBlock(
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

    fn createBlock(self: *Self, instr: ArrayList(IrInstruction)) !BasicBlock {
        const id = self.allocNextId();

        return BasicBlock{
            .Id = id,
            .Instructions = instr,
            .Successors = ArrayList(BlockId).init(self.allocator),
            .Predecessors = ArrayList(BlockId).init(self.allocator),
            .Def = try std.DynamicBitSet.initEmpty(self.allocator, 128),
            .Use = try std.DynamicBitSet.initEmpty(self.allocator, 128),
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
                try used_vregs.append(v.base_addr);
            },
            .CallExternal => |v| {
                try used_vregs.append(v.src);
            },
            else => {},
        }

        const used_vregs_list = try used_vregs.toOwnedSlice();
        return used_vregs_list;
    }

    /// Extract virtual register for dest in instruction
    fn getDestVReg(_: *Self, instr: IrInstruction) ?VReg {
        return switch (instr) {
            .Imm => |v| v.dest,
            .LoadLiteral => |v| v.dest,
            .Load => |v| v.dest,
            .Add => |v| v.dest,
            .Mult => |v| v.dest,
            .Shl => |v| v.dest,

            .Store, .VolatileStore, .CallExternal, .Jump, .Label => null,
        };
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

        var it = self.precolored.iterator();

        while (it.next()) |val| {
            std.debug.print("Precolored v{d} -> r{d}\n", .{ val.key_ptr.*, val.value_ptr.* });
        }
        var it_col = self.assignment.iterator();
        while (it_col.next()) |val| {
            std.debug.print("Colored: v{d} -> r{d}\n", .{ val.key_ptr.*, val.value_ptr.* });
        }

        std.debug.print("\n", .{});
        self.graph.dump();
    }
};
