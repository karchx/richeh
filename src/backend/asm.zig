const std = @import("std");
const mem = std.mem;
const ir = @import("ir");
const IrInstruction = ir.builder.IrInstruction;
const VReg = ir.builder.VReg;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

const PhysReg = enum(u4) {
    a0,
    a1,
    a2,
    a3,
    a4,
    a5,
    a6,
    a7,
    a8,
    a9,
    a10,
    a11,
    a12,
    a13,
    a14,
    a15,
};

pub const Asm = struct {
    allocator: mem.Allocator,
    app_buffer: ArrayList(u8), // app section and config instruction
    lit_buffer: ArrayList(u8),
    text_buffer: ArrayList(u8),
    literal_counter: usize = 0,
    ofile: ?std.Io.File = null,
    io: std.Io,

    const Self = @This();
    const phys_regs = [_]PhysReg{
        .a2, .a3, .a4, .a5, .a6, .a7, // args + return
        .a8, .a9, .a10, .a11, // caller-saved extra
        .a12, .a13, .a14, .a15, // callee-saved
    };

    fn globalIo() std.Io {
        return std.Io.Threaded.global_single_threaded.io();
    }

    pub fn init(allocator: mem.Allocator) !Self {
        const io = globalIo();
        const f = std.Io.Dir.cwd().createFile(io, "o.S", .{}) catch null;
        errdefer if (f) |ff| ff.close(io);

        return Self{
            .allocator = allocator,
            .app_buffer = ArrayList(u8).init(allocator),
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
        self.app_buffer.deinit();
    }

    fn printIndent(writer: *ArrayList(u8), code: []const u8) !void {
        try writer.print("  {s}", .{code});
    }

    pub fn generate(self: *Self, instrs: []IrInstruction, assignment: *const std.AutoHashMap(VReg, i32)) !void {
        var writer = &self.text_buffer;
        var lit_writer = &self.lit_buffer;
        var app_buffer = &self.app_buffer;

        try lit_writer.print("/* LITERAL SECTION */\n", .{});

        try app_buffer.print(".text\n", .{});
        try app_buffer.print(".align 4\n", .{});
        try app_buffer.print(".global app_main\n\n", .{});
        try app_buffer.print("app_main:\n", .{});
        try printIndent(app_buffer, "entry a1, 32\n");
        try app_buffer.print("  /* CONFIG REGISTERS */\n", .{});

        for (instrs) |instr| {
            switch (instr) {
                .Label => |label| {
                    try writer.print("\n{s}:\n", .{label});
                },
                .Imm => |imm| {
                    const r_idx = assignment.get(imm.dest).?;
                    const r = phys_regs[@intCast(r_idx)];
                    // imm_val is 32 in decimal assign GPIO5 TODO: create map for values GPIO in decimal or hex
                    if (imm.imm_val == 32 or imm.imm_val == 1610629120) {
                        try app_buffer.print("  movi {s}, 0x{x}\n", .{ @tagName(r), imm.imm_val });
                    } else {
                        try writer.print("  movi {s}, 0x{x}\n\n", .{ @tagName(r), imm.imm_val });
                    }
                },
                .LoadLiteral => |llit| {
                    const r_idx = assignment.get(llit.dest).?;
                    const r = phys_regs[@intCast(r_idx)];

                    try lit_writer.print(".literal {s}_{s}, {d}\n\n", .{ "DELAY_TICKS", @tagName(r), llit.literal_val });
                    try writer.print("  l32r {s}, {s}_{s}\n\n", .{ @tagName(r), "DELAY_TICKS", @tagName(r) });
                },
                .VolatileStore => |vs| {
                    const base_idx = assignment.get(vs.base_addr).?;
                    const pin_idx = assignment.get(vs.pin).?;

                    const base = phys_regs[@intCast(base_idx)];
                    const pin = phys_regs[@intCast(pin_idx)];
                    // TODO: refactor
                    if (vs.offset == 36) {
                        try app_buffer.print("  s32i {s}, {s}, 0x{x}\n", .{ @tagName(pin), @tagName(base), vs.offset });
                    } else {
                        try writer.print("  s32i {s}, {s}, 0x{x}\n", .{ @tagName(pin), @tagName(base), vs.offset });
                    }
                },

                .CallExternal => |ce| {
                    const idx = assignment.get(ce.src).?;
                    const arg = phys_regs[@intCast(idx)];
                    if (arg != .a6) {
                        try writer.print("  mov a6, {s}\n\n", .{@tagName(arg)});
                    }
                    try writer.print("  call4 {s}\n\n", .{ce.target});
                },
                .Jump => |jump| {
                    try writer.print("  j {s}\n", .{jump});
                },
                else => std.debug.print("\n", .{}),
            }
        }

        try printIndent(writer, "\n");
        try self.ofile.?.writeStreamingAll(self.io, self.lit_buffer.items);
        try self.ofile.?.writeStreamingAll(self.io, self.app_buffer.items);
        try self.ofile.?.writeStreamingAll(self.io, self.text_buffer.items);
    }
};
