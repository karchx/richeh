const std = @import("std");
const mem = std.mem;
const IrInstruction = @import("ir").builder.IrInstruction;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const Asm = struct {
    allocator: mem.Allocator,
    lit_buffer: ArrayList(u8),
    text_buffer: ArrayList(u8),
    reg_counter: u8 = 2, // init a2
    literal_counter: usize = 0,
    ofile: ?std.Io.File = null,
    io: std.Io,
    v2p_map: [256]u8 = [_]u8{0} ** 256,

    const Self = @This();

    fn globalIo() std.Io {
        return std.Io.Threaded.global_single_threaded.io();
    }

    pub fn init(allocator: mem.Allocator) !Self {
        const io = globalIo();
        const f = std.Io.Dir.cwd().createFile(io, "o.S", .{}) catch null;
        errdefer if (f) |ff| ff.close(io);

        return Self{
            .allocator = allocator,
            .lit_buffer = ArrayList(u8).init(allocator),
            .text_buffer = ArrayList(u8).init(allocator),
            .ofile = f,
            .io = io,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.ofile) |f| f.close(self.io);
        self.text_buffer.deinit();
        self.lit_buffer.deinit();
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

    pub fn generate(self: *Self, instrs: []const IrInstruction) !void {
        var writer = &self.text_buffer;
        var lit_writer = &self.lit_buffer;

        try lit_writer.print("/* LITERAL SECTION */\n", .{});

        try writer.print(".text\n", .{});
        try writer.print(".align 4\n", .{});
        try writer.print(".global app_main\n\n", .{});
        try writer.print("app_main:\n", .{});
        try printIndent(writer, "entry a1, 32\n");

        for (instrs) |instr| {
            switch (instr) {
                .Imm => |imm| {
                    const physical_reg = self.getNextReg();
                    self.v2p_map[imm.dest] = physical_reg;

                    try writer.print("  /* IMMEDIATE SECTION*/\n", .{});
                    try writer.print("  movi a{}, 0x{x}\n\n", .{ physical_reg, imm.imm_val });
                },
                .LoadLiteral => |llit| {
                    const physical_reg = self.getNextReg();
                    self.v2p_map[llit.dest] = physical_reg;
                    try lit_writer.print(".literal {s}_{}, {d}\n\n", .{ "DELAY_TICKS", physical_reg, llit.literal_val });
                    try writer.print("  l32r a{}, {s}_{}\n\n", .{ physical_reg, "DELAY_TICKS", physical_reg });
                },
                .VolatileStore => |vs| {
                    const preg_base = self.v2p_map[vs.base_addr];
                    const preg_pin = self.v2p_map[vs.pin];
                    try writer.print("  s32i a{}, a{}, 0x{x}\n", .{ preg_pin, preg_base, vs.offset });
                },
                .CallExternal => |ce| {
                    const preg = self.v2p_map[ce.src];
                    if (preg != 6) {
                        try writer.print("  mov a6, a{}\n\n", .{preg});
                    }
                    try writer.print("  call4 {s}\n\n", .{ce.target});
                },
                else => std.debug.print("\n", .{}),
            }
        }

        try printIndent(writer, "retw.n\n");
        try self.ofile.?.writeStreamingAll(self.io, self.lit_buffer.items);
        try self.ofile.?.writeStreamingAll(self.io, self.text_buffer.items);
    }
};
