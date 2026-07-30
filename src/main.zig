const std = @import("std");
const frontend = @import("frontend");
const lexer = frontend.lexer;

fn print_error_and_exit(io: std.Io, err: anyerror) noreturn {
    const stderr = std.Io.File.stderr();
    switch (err) {}

    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const global_allocator = arena.allocator();
    const all_args = init.minimal.args.toSlice(global_allocator) catch |err| print_error_and_exit(init.io, err);
}
