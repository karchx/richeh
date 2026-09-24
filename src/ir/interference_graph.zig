const std = @import("std");
const mem = std.mem;
const builder = @import("builder.zig");
const IrInstruction = builder.IrInstruction;
const VReg = builder.VReg;
const AdjacencyMap = std.AutoHashMap(VReg, std.AutoHashMap(VReg, void));

pub const InterferenceGraph = struct {
    adj: AdjacencyMap,
    degree: std.AutoHashMap(VReg, u32),
    allocator: mem.Allocator,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .adj = AdjacencyMap.init(allocator),
            .degree = std.AutoHashMap(VReg, u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.adj.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.adj.deinit();
        self.degree.deinit();
    }

    pub fn ensureNode(self: *Self, v: VReg) !void {
        const gop = try self.adj.getOrPut(v);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.AutoHashMap(VReg, void).init(self.allocator);
            try self.degree.put(v, 0);
        }
    }

    // add non-directed edge a-b
    pub fn addEdge(self: *Self, a: VReg, b: VReg) !void {
        if (a == b) return;

        try self.ensureNode(a);
        try self.ensureNode(b);

        const neighbors_a = self.adj.getPtr(a).?;
        const gop_a = try neighbors_a.getOrPut(b);
        if (!gop_a.found_existing) {
            const neighbors_b = self.adj.getPtr(b).?;
            try neighbors_b.put(a, {});

            self.degree.getPtr(a).?.* += 1;
            self.degree.getPtr(b).?.* += 1;
        }
    }

    pub fn hasEdge(self: *const Self, a: VReg, b: VReg) bool {
        if (self.adj.get(a)) |neighbors| {
            return neighbors.contains(b);
        }
        return false;
    }

    pub fn getDegree(self: *const Self, v: VReg) u32 {
        return self.degree.get(v) orelse 0;
    }

    pub fn nodes(self: *Self) AdjacencyMap.KeyIterator {
        return self.adj.keyIterator();
    }

    pub fn dump(self: *const Self) void {
        var it = self.adj.iterator();
        while (it.next()) |entry| {
            const v = entry.key_ptr.*;
            std.debug.print("v{d} (deg={d}) -> ", .{ v, self.getDegree(v) });

            var nit = entry.value_ptr.iterator();
            while (nit.next()) |n| {
                std.debug.print("v{d} ", .{n.key_ptr.*});
            }
            std.debug.print("\n", .{});
        }
    }
};
