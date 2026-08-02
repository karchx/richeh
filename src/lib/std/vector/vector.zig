const std = @import("std");
const mem = std.mem;

fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

/// Create a generic Vector type with the specified element type.
///
/// This function defines a generic Vector type with various methods for manipulating
/// and accesing the elements in the vector
///
/// Parameters:
/// - `T: type`: The element type for the Vector.
///
/// Returns:
/// - `type`: The defined Vector type.
pub fn Vector(comptime T: type) type {
    return struct {
        flags: packed struct {
            peek_decrement: bool = false,
        },

        /// The internal ArrayList for storing elements.
        data: ArrayList(T),

        pindex: isize = 0,

        count: usize = 0,
        /// Structural-mutation counter. Bumped whenever an element is inserted or
        /// removed (push/push_slice/push_at/pop/peek_pop/clear). Moving `pindex`
        /// does NOT bump it, since that doesn't change which index holds which
        /// element. Callers can cache index-derived data and invalidate it by
        /// comparing against this value (see `parser.ParseProcess.token_peek_n`).
        generation: u64 = 0,

        const Self = @This();

        pub fn init(allocator: mem.Allocator) Self {
            return Self{
                .flags = .{ .peek_decrement = false },
                .data = ArrayList(T).init(allocator),
            };
        }

        pub fn items(self: Self) []T {
            return self.data.items;
        }

        pub fn at(self: *Self, index: usize) ?T {
            if (index >= self.data.items.len) {
                return null;
            }
            return self.data.items[index];
        }

        pub fn peek_no_increment(self: *Self) ?T {
            if (self.pindex < 0 or self.pindex >= self.count) {
                return null;
            }
            return self.at(@intCast(self.pindex));
        }

        pub fn peek(self: *Self) ?T {
            const res = self.peek_no_increment();
            if (res != null) {
                if (self.flags.peek_decrement) {
                    self.pindex -= 1;
                } else {
                    self.pindex += 1;
                }
            }
            return res;
        }

        pub fn back(self: Self) ?T {
            if (self.data.items.len == 0) {
                return null;
            }
            return self.data.items[self.data.items.len - 1];
        }

        pub fn push(self: *Self, elem: T) mem.Allocator.Error!void {
            try self.data.append(elem);
            self.count += 1;
            self.generation +%= 1;
        }

        pub fn pop(self: *Self) void {
            if (self.count > 0) {
                self.count -= 1;
                _ = self.data.pop();
                self.generation +%= 1;
            }
        }
    };
}
