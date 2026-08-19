const std = @import("std");
const mem = std.mem;
const parser = @import("frontend").parser;
const ParseError = parser.ParseError;

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
    symbol: ?[]const u8 = null, // Name variable (table symbols)
};

pub const IrError = error {
    NotImplementedYet,
    NotImplementedOp,
} || ParseError;

pub const IrBuilder = struct {
    allocator: mem.Allocator,
    instructions: ArrayList(IrInstruction),
    next_vreg: VReg,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) IrError!Self {
       const arena_ptr = allocator.create(std.heap.ArenaAllocator) catch {
            return IrError.MemoryAllocationFailed;
       };
       errdefer allocator.destroy(arena_ptr);
       arena_ptr.* = std.heap.ArenaAllocator.init(allocator);
       errdefer arena_ptr.deinit();
       const a = arena_ptr.allocator();

       return Self{
            .allocator = a,
            .instructions = ArrayList(IrInstruction).init(a),
            .next_vreg = 0,
       };
    }

    pub fn allocReg(self: *Self) VReg {
        const reg = self.next_vreg;
        self.next_vreg += 1;
        return reg;
    }

    pub fn emit(self: *Self, inst: IrInstruction) IrError!void {
        self.instructions.append(inst) catch {
            return IrError.MemoryAllocationFailed;
        };
    }
};