const std = @import("std");
const mem = std.mem;
const process = std.process;

/// Compatibility shim: ArrayList with embedded allocator (old API style).
fn ArrayList(comptime T: type) type {
    return std.array_list.Managed(T);
}

pub const CliError = error{
    MissingInputFile,
    InvalidInputExtension,
    ShowHelp,
};

pub const CliOptions = struct {
    /// The path to the input file that will be transpiled.
    input_file: []const u8,
    /// Flag to control AST node printing.
    print_ast: bool,
};

pub fn free_options(allocator: mem.Allocator, options: CliOptions) void {
    allocator.free(options.input_file);
}

fn print_usage(io: std.Io) void {
    std.Io.File.stderr().writeStreamingAll(io,
        \\Usage:
        \\ richeh -in <input_file> [-ast]
        \\ richeh -version
        \\
        \\Arguments:
        \\ -help       Show this help message
        \\ -version    Print version and exit
        \\ -in  <file> Input file to compile
        \\ -ast        Print Ast nodes (optional, disabled by default)
    ) catch {};
}

/// Parse command-line arguments
pub fn parse_args(allocator: mem.Allocator, io: std.Io, argv: []const []const u8) !CliOptions {
    if (argv.len == 0) {
        print_usage(io);
        return CliError.ShowHelp;
    }

    var input_file: ?[]const u8 = null;
    var print_ast = false;
    var program_args = ArrayList([]const u8).init(allocator);

    errdefer {
        for (program_args.items) |p| allocator.free(p);
        program_args.deinit();
    }

    var i: usize = 0;
    while (i < argv.len) {
        const arg = argv[i];
        i += 1;
        if (std.mem.eql(u8, arg, "--")) {
            while (i < argv.len) {
                try program_args.append(try allocator.dupe(u8, argv[i]));
                i += 1;
            }
            break;
        }

        if (std.mem.eql(u8, arg, "-help")) {
            print_usage(io);
            return CliError.ShowHelp;
        } else if (std.mem.eql(u8, arg, "-in")) {
            if (i >= argv.len) return CliError.MissingInputFile;
            const file = argv[i];
            i += 1;
            input_file = try allocator.dupe(u8, file);
        } else if (std.mem.eql(u8, arg, "-ast")) {
            print_ast = true;
        }
    }

    const ifilepath = input_file orelse {
        return CliError.MissingInputFile;
    };

    if (!std.mem.endsWith(u8, ifilepath, ".rh")) {
        return CliError.InvalidInputExtension;
    }

    return CliOptions{
        .input_file = ifilepath,
        .print_ast = print_ast,
    };
}
