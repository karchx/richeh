const std = @import("std");
const mem = std.mem;
const IrInstruction = @import("ir").builder.IrInstruction;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const Asm = struct {
    allocator: mem.Allocator,
    out_buffer: ArrayList(u8),
    reg_counter: u8 = 2, // init a2
    literal_counter: usize = 0,
    v2p_map: [256]u8 = [_]u8{0} ** 256,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .out_buffer = ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.out_buffer.deinit();
    }

    fn getNextReg(self: *Self) u8 {
        const reg = self.reg_counter;
        self.reg_counter += 1;
        if (self.reg_counter > 15) {
            @panic("POC limit");
        }
        return reg;
    }

    fn printIndent(writer: *ArrayList(u8), code: []const u8) !void {
        try writer.print("  {s}", .{code});
    }

    pub fn generate(self: *Self, instrs: []const IrInstruction) ![]const u8 {
        var writer = &self.out_buffer;
        try writer.print(".text\n", .{});
        try writer.print(".align 4\n", .{});
        try writer.print(".global app_main\n", .{});
        try writer.print("app_main:\n", .{});
        try printIndent(writer, "entry a1, 32\n");

        for (instrs) |instr| {
            switch (instr) {
                .Imm => |imm| {
                    const physical_reg = self.getNextReg();
                    self.v2p_map[imm.dest] = physical_reg;

                    try writer.print("  movi a{}, 0x{x}\n", .{ physical_reg, imm.imm_val });
                },
                .LoadLiteral => |llit| {
                    const physical_reg = self.getNextReg();
                    self.v2p_map[llit.dest] = physical_reg;

                    try writer.print("  l32r a{}, {d}\n", .{ physical_reg, llit.literal_val });
                },
                .VolatileStore => |vs| {
                    const preg_base = self.v2p_map[vs.base_addr];
                    const preg_pin = self.v2p_map[vs.pin];
                    try writer.print("  s32i a{}, a{}, 0x{x}\n", .{ preg_pin, preg_base, vs.offset });
                },
                .Loop => |loop| {
                    const preg = self.v2p_map[loop.src];
                    try writer.print("  loop a{}, .{s}\n", .{ preg, loop.tag });
                    try printIndent(writer, "nop\n");
                    try writer.print(".{s}: \n", .{loop.tag});
                },
                else => std.debug.print("\n", .{}),
            }
        }

        try printIndent(writer, "retw.n\n");
        return self.out_buffer.items;
    }
};
