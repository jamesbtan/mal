const std = @import("std");
const Allocator = std.mem.Allocator;
const T = @import("types.zig");

allocator: Allocator,

const Self = @This();
pub const Error = error{
    TokenizeError,
    ParseError,
} || Allocator.Error;

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn readStr(self: *Self, str: []const u8) Error!T.MalType {
    var tok_iter = tokenizer(str);
    return try readForm(&tok_iter, self.allocator);
}

const TokenIterator = struct {
    str_slice: []const u8,

    const IterSelf = @This();

    pub fn next(self: *IterSelf) Error!?[]const u8 {
        const slice = (try self.peek()) orelse return null;
        self.str_slice = self.str_slice[slice.len..];
        return slice;
    }

    pub fn peek(self: *IterSelf) Error!?[]const u8 {
        const allsym = "[]{}()'`~^@, \t\n\r";
        const special = allsym[0..11];
        const whitespace = allsym[11..];
        self.str_slice = std.mem.trimLeft(u8, self.str_slice, whitespace);
        if (self.str_slice.len == 0) {
            return null;
        } else if (self.str_slice.len >= 2 and std.mem.eql(u8, self.str_slice[0..2], "~@")) {
            return self.str_slice[0..2];
        } else if (std.mem.indexOfScalar(u8, special, self.str_slice[0]) != null) {
            return self.str_slice[0..1];
        } else if (self.str_slice[0] == '"') {
            var offset: usize = 1;
            while (true) {
                // if null, unbalanced string
                const ind = std.mem.indexOfAnyPos(u8, self.str_slice, offset, "\"\\") orelse return Error.TokenizeError;
                offset = ind;
                switch (self.str_slice[offset]) {
                    '\\' => offset += 2,
                    '"' => {
                        return self.str_slice[0 .. offset + 1];
                    },
                    else => unreachable,
                }
            }
        } else if (self.str_slice[0] == ';') { // last 2 are similar?
            if (std.mem.indexOfScalar(u8, self.str_slice, '\n')) |ind| {
                return self.str_slice[0..ind];
            } else {
                return self.str_slice[0..];
            }
        } else {
            if (std.mem.indexOfAny(u8, self.str_slice, allsym)) |ind| {
                return self.str_slice[0..ind];
            } else {
                return self.str_slice[0..];
            }
        }
    }
};

fn tokenizer(str: []const u8) TokenIterator {
    return .{ .str_slice = str };
}

test "tokenizer" {
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
        const exp = case.expected;

        var tok_iter = tokenizer(case.input);
        var i: usize = 0;
        while (i < exp.len) : (i += 1) {
            const tok = (try tok_iter.next()) orelse break;
            try std.testing.expectEqualStrings(exp[i], tok);
        }
        try std.testing.expectEqual(@as(?[]const u8, null), try tok_iter.next());
        try std.testing.expectEqual(i, exp.len);
    }
}

fn readForm(tok_iter: *TokenIterator, alloc: Allocator) Error!T.MalType {
    if (try tok_iter.next()) |tok| {
        if (tok[0] == '(') {
            return T.MalType{ .list = try readList(tok_iter, alloc) };
        } else {
            return T.MalType{ .atom = try readAtom(tok) };
        }
    } else {
        return T.MalType{ .atom = .nil };
    }
}

fn readAtom(tok: []const u8) Error!T.MalAtom {
    if (tok[0] == ';') {
        return .nil;
    }
    if (std.fmt.parseInt(i64, tok, 10)) |i| {
        return T.MalAtom{ .num = i };
    } else |_| {}
    return T.MalAtom{ .sym = tok };
}

fn readList(tok_iter: *TokenIterator, alloc: Allocator) Error!?*T.MalList {
    if (try tok_iter.peek()) |tok| {
        if (tok[0] == ')') {
            _ = try tok_iter.next();
            return null;
        }
        var ml = try alloc.create(T.MalList);
        ml.*.car = try readForm(tok_iter, alloc);
        ml.*.cdr = try readList(tok_iter, alloc);
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
        const exp = case.expected;
        const res = try reader.readStr(case.input);
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

