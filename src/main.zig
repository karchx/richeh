const std = @import("std");
const frontend = @import("frontend");
const cli = @import("cli");
const ir = @import("ir");
const lexer = frontend.lexer;
const parser = frontend.parser;
const pprint = frontend.pprint;
const irbuilder = ir.builder;
const gen = ir.gen;

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

    const PipelineCtx = struct { allocator: std.mem.Allocator, io: std.Io, options: @TypeOf(options) };
    const ctx = PipelineCtx{ .allocator = global_allocator, .io = init.io, .options = options };
    const thread = std.Thread.spawn(.{ .stack_size = pipeline_stack_size }, run_pipeline, .{ctx}) catch {
        run_pipeline(.{ .allocator = global_allocator, .io = init.io, .options = options });
        return;
    };
    thread.join();
}

// Stack size for the compilation worker thread (256MiB).
const pipeline_stack_size: usize = 256 * 1024 * 1024;

fn run_pipeline(ctx: anytype) void {
    const global_allocator = ctx.allocator;
    const options = ctx.options;
    const io = ctx.io;

    var lp = lexer.Lexer.init(global_allocator, options.input_file) catch |err| print_error_and_exit(io, err);
    var pp = parser.Parse.init(&lp);
    var builder = irbuilder.IrBuilder.init(global_allocator) catch |err| print_error_and_exit(io, err);
    defer {
        lp.deinit();
    }

    lp.lex() catch |err| print_error_and_exit(io, err);
    const root_node = pp.parse() catch |err| print_error_and_exit(io, err);
    const stmts = root_node.variant.program.statements;
    var generation = gen.Gen.init(&builder, stmts) catch |err| print_error_and_exit(io, err);
    generation.generate_instruction() catch |err| print_error_and_exit(io, err);

    if (options.print_ast) {
        var ast_buf: [65536]u8 = undefined;
        var ast_writer = std.Io.File.stdout().writer(io, &ast_buf);
        pprint.print_node(root_node, &ast_writer.interface, 0) catch |err| print_error_and_exit(io, err);
        ast_writer.interface.flush() catch |err| print_error_and_exit(io, err);
    }
}
