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
    /// Shl bit operator.
    Shl,
    /// Write register in port special instr in hadware.
    VolatileStore,
    /// Call external function
    CallExternal,
    /// Label
    Label,
    /// Jump
    Jump,
};

pub const IrInstruction = union(IrOpCode) {
    Imm: struct { dest: VReg, imm_val: u32 },
    LoadLiteral: struct { dest: VReg, literal_val: u32 },
    Load: struct { dest: VReg, symbol: []const u8 },
    Store: struct { src: VReg, symbol: []const u8 },
    Add: struct { dest: VReg, src1: VReg, src2: VReg },
    Mult: struct { dest: VReg, src1: VReg, src2: VReg },
    Shl: struct { dest: VReg, src1: VReg, src2: VReg },
    VolatileStore: struct { base_addr: VReg, pin: u32, offset: u32 },
    CallExternal: struct { src: VReg, target: []const u8 },
    Label: []const u8,
    Jump: []const u8,
};

pub const IrError = error{
    NotImplementedYet,
    NotImplementedOp,
    NotInstructionsYet,
} || ParseError;

pub const IrBuilder = struct {
    allocator: mem.Allocator,
    instructions: ArrayList(IrInstruction),
    // key = value, value = reg
    lvn_map: std.AutoHashMap(u32, VReg),
    // key = base_addr + offset, value = pin
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

    /// generation const values that are already know
    pub fn constAddress(self: *Self) !VReg {
        const base_addr_reg = self.allocReg();
        // BASE ADDRESS ESP32-S3: 0x60004000
        // 1610629120
        try self.emit(.{ .Imm = .{ .dest = base_addr_reg, .imm_val = 1610629120 } });
        return base_addr_reg;
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
