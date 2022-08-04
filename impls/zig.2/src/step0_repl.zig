const std = @import("std");

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var buf: [256]u8 = undefined;
    while (true) {
        try stdout.print("user> ", .{});
        const input = (try stdin.readUntilDelimiterOrEof(&buf, '\n')) orelse break;
        try stdout.print("{s}\n", .{rep(input)});
    }
}

fn READ(in: []const u8) []const u8 {
    return in;
}

fn EVAL(in: []const u8) []const u8 {
    return in;
}

fn PRINT(in: []const u8) []const u8 {
    return in;
}

fn rep(in: []const u8) []const u8 {
    const read = READ(in);
    const eval = EVAL(read);
    const print = PRINT(eval);
    return print;
}
