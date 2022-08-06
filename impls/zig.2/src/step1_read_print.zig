const std = @import("std");
const types = @import("types.zig");
const Reader = @import("reader.zig");
const Printer = @import("printer.zig").Printer;

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var reader = Reader.init(std.testing.allocator);
    defer reader.deinit();
    var printer = Printer(@TypeOf(stdout)).init(stdout);
    var buf: [256]u8 = undefined;
    while (true) {
        try stdout.print("user> ", .{});
        const input = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse break;
        const read = try READ(input, &reader);
        defer reader.destroy(&read);
        const eval = EVAL(read);
        try PRINT(eval, printer);
    }
}

fn READ(in: []const u8, reader: *Reader) Reader.Error!types.MalType {
    return try reader.readStr(in);
}

fn EVAL(in: types.MalType) types.MalType {
    return in;
}

fn PRINT(in: types.MalType, printer: anytype) @TypeOf(printer).Error!void {
    try printer.prStr(in);
}
