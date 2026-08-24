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
    /// Load 32-bits constant
    LoadLiteral,
    /// load normal register.
    Load,
    /// store register.
    Store,
    /// Add two register.
    Add,
    /// Mult two register.
    Mult,
    /// Write register in port special instr in hadware.
    VolatileStore,
    /// Loop instruction
    Loop,
};

pub const IrInstruction = union(IrOpCode) {
    Imm: struct { dest: VReg, imm_val: u32 },
    LoadLiteral: struct { dest: VReg, literal_val: u32 },
    Load: struct { dest: VReg, symbol: []const u8 },
    Store: struct { src: VReg, symbol: []const u8 },
    Add: struct { dest: VReg, src1: VReg, src2: VReg },
    Mult: struct { dest: VReg, src1: VReg, src2: VReg },
    VolatileStore: struct { base_addr: VReg, pin: u32, offset: u32 },
    Loop: struct { src: VReg, tag: []const u8 },
};

pub const IrError = error{
    NotImplementedYet,
    NotImplementedOp,
    NotInstructionsYet,
} || ParseError;

pub const IrBuilder = struct {
    allocator: mem.Allocator,
    instructions: ArrayList(IrInstruction),
    lvn_map: std.AutoHashMap(u32, VReg),
    next_vreg: VReg,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .instructions = ArrayList(IrInstruction).init(allocator),
            .lvn_map = std.AutoHashMap(u32, VReg).init(allocator),
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

    pub fn trackLoadedRegister(self: *Self, key: u32, reg: VReg) ?VReg {
        const loaded_reg = self.lvn_map.get(key);
        if (loaded_reg) |find_reg| {
            return find_reg;
        } else {
            self.lvn_map.put(key, reg);
            return null;
        }
    }
};
