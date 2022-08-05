const std = @import("std");

tokens: std.ArrayList([]const u8),
pos: usize = 0,

const Self = @This();
const Error = error{
    TokenizeError,
} || std.mem.Allocator.Error;

fn init(allocator: std.mem.Allocator) Self {
    return .{
        .tokens = std.ArrayList([]const u8).init(allocator),
    };
}

fn deinit(self: *Self) void {
    self.tokens.deinit();
}

fn next(self: *Self) ?[]const u8 {
    if (self.pos == self.tokens.items.len) return null;
    defer self.pos += 1;
    return self.tokens.items[self.pos];
}

fn peek(self: *const Self) ?[]const u8 {
    if (self.pos == self.tokens.items.len) return null;
    return self.tokens.items[self.pos];
}

// TODO: deduplicate all this junk..
fn tokenize(self: *Self, str: []const u8) Error!void {
    self.tokens.clearRetainingCapacity();
    var str_slice = str;
    const allsym = "[]{}()'`~^@, \t\n\r";
    const special = allsym[0..11];
    const whitespace = allsym[11..];
    while (str_slice.len > 0) {
        if (std.mem.indexOfScalar(u8, whitespace, str_slice[0]) != null) {
            str_slice = std.mem.trimLeft(u8, str_slice, whitespace);
        } else if (str_slice.len >= 2 and std.mem.eql(u8, str_slice[0..2], "~@")) {
            try self.tokens.append(str_slice[0..2]);
            str_slice = str_slice[2..];
        } else if (std.mem.indexOfScalar(u8, special, str_slice[0]) != null) {
            try self.tokens.append(str_slice[0..1]);
            str_slice = str_slice[1..];
        } else if (str_slice[0] == '"') {
            var offset: usize = 1;
            while (true) {
                // if null, unbalanced string
                const ind = std.mem.indexOfScalarPos(u8, str_slice, offset, '"') orelse return Error.TokenizeError;
                offset = ind;
                if (str_slice[ind - 1] != '\\') break;
                offset += 1;
            }
            try self.tokens.append(str_slice[0 .. offset + 1]);
            str_slice = str_slice[offset + 1 ..];
        } else if (str_slice[0] == ';') {
            if (std.mem.indexOfScalar(u8, str_slice, '\n')) |ind| {
                try self.tokens.append(str_slice[0..ind]);
                str_slice = str_slice[ind..];
            } else {
                try self.tokens.append(str_slice[0..]);
                str_slice = str_slice[str_slice.len..];
            }
        } else {
            if (std.mem.indexOfAny(u8, str_slice, allsym)) |ind| {
                try self.tokens.append(str_slice[0..ind]);
                str_slice = str_slice[ind..];
            } else {
                try self.tokens.append(str_slice[0..]);
                str_slice = str_slice[str_slice.len..];
            }
        }
    }
}

test "tokenizer" {
    var reader = Self.init(std.testing.allocator);
    defer reader.deinit();

    const Case = struct {
        input: []const u8,
        expected: []const []const u8,
    };
    const cases = [_]Case{
        .{
            .input = "8",
            .expected = &.{
                "8",
            },
        },
        .{
            .input = " 8",
            .expected = &.{
                "8",
            },
        },
        .{
            .input = "8 ",
            .expected = &.{
                "8",
            },
        },
        .{
            .input = "8,  ,",
            .expected = &.{
                "8",
            },
        },
        .{
            .input = "8,  ,9",
            .expected = &.{
                "8",
                "9",
            },
        },
        .{
            .input = "8\n; ,9\n",
            .expected = &.{
                "8",
                "; ,9",
            },
        },
        .{
            .input = "[[89ab-a 22))",
            .expected = &.{
                "[",
                "[",
                "89ab-a",
                "22",
                ")",
                ")",
            },
        },
    };

    for (cases) |case| {
        try reader.tokenize(case.input);

        const exp = case.expected;
        const res = reader.tokens.items;
        try std.testing.expectEqual(exp.len, res.len);
        for (exp) |_, i| {
            try std.testing.expectEqualSlices(u8, exp[i], res[i]);
        }
    }
}

const MalType = union(enum){
    list: MalList,
    atom: MalAtom,
};

const MalList = struct {
    items: std.ArrayList(MalType),
};

const MalAtom = union(enum){
    num: i64,
    sym: []const u8,
};

fn readForm(self: *Self) MalType {
    _ = self;
}
