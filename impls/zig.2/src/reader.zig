const std = @import("std");
const Allocator = std.mem.Allocator;
const T = @import("types.zig");

allocator: Allocator,
tokens: std.ArrayList([]const u8),
pos: usize = 0,

const Self = @This();
pub const Error = error{
    TokenizeError,
    ParseError,
} || Allocator.Error;

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .tokens = std.ArrayList([]const u8).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
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

pub fn readStr(self: *Self, str: []const u8) Error!T.MalType {
    try self.tokenize(str);
    return try self.readForm();
}

// TODO: deduplicate all this junk..
fn tokenize(self: *Self, str: []const u8) Error!void {
    self.tokens.clearRetainingCapacity();
    self.pos = 0;
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
                const ind = std.mem.indexOfAnyPos(u8, str_slice, offset, "\"\\") orelse return Error.TokenizeError;
                offset = ind;
                switch (str_slice[offset]) {
                    '\\' => offset += 2,
                    '"' => {
                        try self.tokens.append(str_slice[0 .. offset + 1]);
                        str_slice = str_slice[offset + 1 ..];
                        break;
                    },
                    else => unreachable,
                }
            }
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
        .{
            // "a"
            .input = "\"a\"",
            .expected = &.{
                "\"a\"",
            },
        },
        .{
            // "a\""
            .input = "\"a\\\"\"",
            .expected = &.{
                "\"a\\\"\"",
            },
        },
        .{
            // \\
            // backslash outside of string is not an escape (?)
            .input = "\\\\",
            .expected = &.{
                "\\\\",
            },
        },
        .{
            // "\\\""
            .input = "\"\\\\\\\"\"",
            .expected = &.{
                "\"\\\\\\\"\"",
            },
        },
        .{
            // "\\\\"
            .input = "\"\\\\\\\\\"",
            .expected = &.{
                "\"\\\\\\\\\"",
            },
        },
    };

    for (cases) |case| {
        try reader.tokenize(case.input);

        const exp = case.expected;
        const res = reader.tokens.items;
        try std.testing.expectEqual(exp.len, res.len);
        for (exp) |_, i| {
            try std.testing.expectEqualStrings(exp[i], res[i]);
        }
    }
}

fn readForm(self: *Self) Error!T.MalType {
    if (self.peek()) |tok| {
        if (tok[0] == '(') {
            return T.MalType{ .list = try self.readList() };
        } else {
            return T.MalType{ .atom = try self.readAtom() };
        }
    } else {
        return T.MalType{ .atom = .nil };
    }
}

fn readAtom(self: *Self) Error!T.MalAtom {
    const tok = self.next() orelse return Error.ParseError;
    if (tok[0] == ';') {
        return .nil;
    }
    if (std.fmt.parseInt(i64, tok, 10)) |i| {
        return T.MalAtom{ .num = i };
    } else |_| {}
    return T.MalAtom{ .sym = tok };
}

fn readList(self: *Self) Error!?*T.MalList {
    // first paren
    _ = self.next();
    return try self.readCdr();
}

fn readCdr(self: *Self) Error!?*T.MalList {
    if (self.peek()) |tok| {
        if (tok[0] == ')') {
            _ = self.next();
            return null;
        }
        var ml = try self.allocator.create(T.MalList);
        ml.*.car = try self.readForm();
        ml.*.cdr = try self.readCdr();
        return ml;
    } else {
        return Error.ParseError;
    }
}

pub fn destroy(self: *Self, form: *const T.MalType) void {
    if (std.meta.activeTag(form.*) != .list) return;
    var prev: ?*const T.MalList = undefined;
    var curr: ?*const T.MalList = form.*.list;
    while (curr != null) {
        std.mem.swap(?*const T.MalList, &prev, &curr);
        curr = prev.?.*.cdr;
        self.destroy(&prev.?.*.car);
        self.allocator.destroy(prev.?);
    }
}

// move to types
fn equalList(a: ?*const T.MalList, b: ?*const T.MalList) bool {
    var x: ?*const T.MalList = a;
    var y: ?*const T.MalList = b;
    while (x != null and y != null) {
        if (!equal(x.?.*.car, y.?.*.car)) return false;
        x = x.?.*.cdr;
        y = y.?.*.cdr;
    }
    return x == y;
}

fn equal(a: T.MalType, b: T.MalType) bool {
    const a_tag = std.meta.activeTag(a);
    const b_tag = std.meta.activeTag(b);
    if (a_tag != b_tag) return false;
    switch (a_tag) {
        .list => {
            return equalList(a.list, b.list);
        },
        .atom => {
            const a_atm_tag = std.meta.activeTag(a.atom);
            const b_atm_tag = std.meta.activeTag(b.atom);
            if (a_atm_tag != b_atm_tag) return false;
            switch (a_atm_tag) {
                .sym => return std.mem.eql(u8, a.atom.sym, b.atom.sym),
                else => return std.meta.eql(a, b),
            }
        },
    }
}

test "readForm" {
    var reader = Self.init(std.testing.allocator);
    defer reader.deinit();

    const Case = struct {
        input: []const u8,
        expected: T.MalType,
    };
    const cases = [_]Case{
        .{
            .input = "",
            .expected = .{ .atom = .nil },
        },
        .{
            .input = "8",
            .expected = .{
                .atom = .{ .num = 8 },
            },
        },
        .{
            .input = "abc",
            .expected = .{
                .atom = .{ .sym = "abc" },
            },
        },
        .{
            .input = "(1)",
            .expected = .{
                .list = &.{
                    .car = .{ .atom = .{ .num = 1 } },
                },
            },
        },
        .{
            .input = "(1 2)",
            .expected = .{
                .list = &.{
                    .car = .{ .atom = .{ .num = 1 } },
                    .cdr = &.{
                        .car = .{ .atom = .{ .num = 2 } },
                    },
                },
            },
        },
        .{
            .input = "(1 (2))",
            .expected = .{
                .list = &.{
                    .car = .{ .atom = .{ .num = 1 } },
                    .cdr = &.{
                        .car = .{
                            .list = &.{
                                .car = .{ .atom = .{ .num = 2 } },
                            },
                        },
                    },
                },
            },
        },
        .{
            .input = "(1 (2) 3 (four (5 6)))",
            .expected = .{
                .list = &.{
                    .car = .{ .atom = .{ .num = 1 } },
                    .cdr = &.{
                        .car = .{
                            .list = &.{
                                .car = .{ .atom = .{ .num = 2 } },
                            },
                        },
                        .cdr = &.{
                            .car = .{ .atom = .{ .num = 3 } },
                            .cdr = &.{
                                .car = .{
                                    .list = &.{
                                        .car = .{ .atom = .{ .sym = "four" } },
                                        .cdr = &.{
                                            .car = .{
                                                .list = &.{
                                                    .car = .{ .atom = .{ .num = 5 } },
                                                    .cdr = &.{
                                                        .car = .{ .atom = .{ .num = 6 } },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
        .{
            .input = "(() 3 () ())",
            .expected = .{
                .list = &.{
                    .car = .{ .list = null },
                    .cdr = &.{
                        .car = .{ .atom = .{ .num = 3 } },
                        .cdr = &.{
                            .car = .{ .list = null },
                            .cdr = &.{
                                .car = .{ .list = null },
                            },
                        },
                    },
                },
            },
        },
        .{
            .input = "()",
            .expected = .{ .list = null },
        },
    };

    for (cases) |case, i| {
        try reader.tokenize(case.input);
        const exp = case.expected;
        const res = try reader.readForm();
        defer reader.destroy(&res);
        std.testing.expect(equal(exp, res)) catch |err| {
            const stderr = std.io.getStdErr().writer();
            const Printer = @import("printer.zig").Printer(@TypeOf(stderr));
            var printer = Printer.init(stderr);
            std.debug.print("\nINPUT:\n{s}\n\n", .{cases[i].input});
            std.debug.print("EXPECTED:\n", .{});
            try printer.prStr(exp);
            std.debug.print("GOT:\n", .{});
            try printer.prStr(res);
            return err;
        };
    }
}
