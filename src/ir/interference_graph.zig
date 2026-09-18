const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const IrInstruction = builder.IrInstruction;
const VReg = builder.VReg;

pub const InterferenceGraph = struct {
    adj: std.AutoHashMap(VReg, std.ArrayList(VReg)),
    degree: std.AutoHashMap(VReg, u32),
    allocator: mem.Allocator,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .adj = std.AutoHashMap(VReg, std.ArrayList(VReg)).init(allocator),
            .degree = std.AutoHashMap(VReg, u32).init(allocator),
        };
    }

    pub fn addEdge(self: *Self, a: VReg, b: VReg) !void {
        if (a == b) return;
        try self.ensureNode(a);
        try self.ensureNode(b);

        // TODO: this is linear search, x.x
        if (!self.contains(self.adj.getPtr(a).?.*, b)) {
            try self.adj.getPtr(a).?.append(b);
            try self.adj.getPtr(b).?.append(a);
            self.degree.getPtr(a).?.* += 1;
            self.degree.getPtr(b).?.* += 1;
        }
    }

    fn ensureNode(self: *Self, v: VReg) !void {
        const gop = try self.adj.getOrPut(v);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(VReg).init(self.allocator);
            try self.degree.put(v, 0);
        }
    }

    fn contains(list: std.ArrayList(VReg), v: VReg) bool {
        for (list.items) |x| if (x == v) return true;
        return false;
    }
};
