const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const IrInstruction = builder.IrInstruction;

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

pub const CFG = struct {
    allocator: mem.Allocator,
    blocks: ArrayList(BasicBlock),
    entry: BlockId,
    next_id: BlockId,
    ir_instructions: *[]IrInstruction,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, ir_instructions: *[]IrInstruction) !Self {
        return Self{
            .allocator = allocator,
            .blocks = ArrayList(BasicBlock).init(allocator),
            .entry = 0,
            .next_id = 0,
            .ir_instructions = ir_instructions,
        };
    }

    fn allocNextId(self: *Self) BlockId {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    pub fn basicBlocks(self: *Self) !void {
        const leaders = try self.computeLeaders();
        for (leaders, 0..) |ld, idx| {
            std.debug.print("{d} | LD: {}\n", .{ idx, ld });
        }
        defer self.allocator.free(leaders);

        var current: ?BasicBlock = null;

        for (self.ir_instructions.*, 0..) |instr, idx| {
            if (leaders[idx]) {
                var instr_list = ArrayList(IrInstruction).init(self.allocator);
                const success_list = ArrayList(BlockId).init(self.allocator);
                const predecess_list = ArrayList(BlockId).init(self.allocator);
                if (current) |b| {
                    try self.blocks.append(b);
                }

                try instr_list.append(instr);

                current = self.createBlock(
                    instr_list,
                    success_list,
                    predecess_list,
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

    fn createBlock(self: *Self, instr: ArrayList(IrInstruction), success: ArrayList(BlockId), predecess: ArrayList(BlockId)) BasicBlock {
        const id = self.allocNextId();

        return BasicBlock{
            .Id = id,
            .Instructions = instr,
            .Successors = success,
            .Predecessors = predecess,
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
};
