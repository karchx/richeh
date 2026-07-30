const std = @import("std");
const frontend = @import("frontend");
const cli = @import("cli");
const lexer = frontend.lexer;

fn print_error_and_exit(io: std.Io, err: anyerror) noreturn {
    const stderr = std.Io.File.stderr();
    switch (err) {
        cli.CliError.ShowHelp => {
            std.process.exit(0);
        },
        else => {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "Error: {s}\n", .{@errorName(err)}) catch "Error: unknown\n";
            stderr.writeStreamingAll(io, msg) catch {};
        },
    }

    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    const global_allocator = arena.allocator();
    const all_args = init.minimal.args.toSlice(global_allocator) catch |err| print_error_and_exit(init.io, err);

    // Skip the executable name
    const argv = if (all_args.len > 0) all_args[1..] else all_args[0..0];
    const options = cli.parse_args(global_allocator, init.io, argv) catch |err| print_error_and_exit(init.io, err);
    defer cli.free_options(global_allocator, options);
}
