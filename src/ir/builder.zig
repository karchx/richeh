const std = @import("std");
const mem = std.mem;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const VReg = u32;
pub const IrOpCode = enum {
    /// load inmediate register.
    Imm,
    /// load normal register.
    Load,
    /// store register.
    Store,
    /// Add two register.
    Add,
    /// Mult two register.
    Mult,
    /// Write register in port special instr in hadware.
    Out,
};

pub const IrInstruction = struct {
    op: IrOpCode,
    dest: VReg = 0,
    src1: VReg = 0,
    src2: VReg = 0,
    imm_val: u32 = 0,
};

pub const IrBuilder = struct {
    allocator: mem.Allocator,
    instructions: ArrayList(IrInstruction),

    const Self = @This();

    pub fn init(allocator: mem.Allocator) !Self {
       const arena_ptr = try allocator.create(std.heap.ArenaAllocator);
       errdefer allocator.destroy(arena_ptr);
       arena_ptr.* = std.heap.ArenaAllocator.init(allocator);
       errdefer arena_ptr.deinit();
       const a = arena_ptr.allocator();

       return Self{
            .allocator = a,
            .instructions = ArrayList(IrInstruction).init(a),
       };
    }

    fn emit(self: *Self, inst: IrInstruction) !void {
        try self.instructions.append(inst);
    }
};