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
    const BASE_ADDR = 0x60004000;

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

    fn getHexValue(_: *Self, value: u32) []const u8 {
        var buf: [10]u8 = undefined;
        const addr = std.fmt.bufPrint(&buf, "0x{X}", .{value}) catch "0x00";
        return addr;
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
                    const reg = self.getNextReg();
                    const addr = self.getHexValue(imm.imm_val);
                    try writer.print("  movi a{}, {s}\n", .{ reg, addr });
                },
                .VolatileStore => |vs| {
                    const offset = self.getHexValue(vs.offset);
                    try writer.print("  s32i a{}, a{}, {s}\n", .{ vs.pin + 2, vs.base_addr + 2, offset });
                },
                else => std.debug.print("\n", .{}),
            }
        }

        try printIndent(writer, "retw.n\n");
        return self.out_buffer.items;
    }
};
