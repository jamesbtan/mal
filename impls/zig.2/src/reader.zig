const std = @import("std");
const Allocator = std.mem.Allocator;

allocator: Allocator,
tokens: std.ArrayList([]const u8),
pos: usize = 0,

const Self = @This();
const Error = error{
    TokenizeError,
    ParseError,
} || Allocator.Error;

fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
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

fn readStr(self: *Self, str: []const u8) MalType {
    self.tokenize(str);
    self.readForm();
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
        .{
            .input = "\"a\"",
            .expected = &.{
                "\"a\"",
            },
        },
        .{
            .input = "\"a\\\"\"",
            .expected = &.{
                "\"a\\\"\"",
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

const MalType = union(enum) {
    list: []const MalType,
    atom: MalAtom,
    nil,
};

const MalAtom = union(enum) {
    num: i64,
    sym: []const u8,
};

fn readForm(self: *Self) Error!MalType {
    if (self.peek()) |tok| {
        if (tok[0] == '(') {
            if (try self.readList()) |list| {
                return MalType{ .list = list };
            } else {
                return .nil;
            }
        } else {
            return MalType{ .atom = try self.readAtom() };
        }
    } else {
        return .nil;
    }
}

fn readAtom(self: *Self) Error!MalAtom {
    const tok = self.next() orelse return Error.ParseError;
    const i = std.fmt.parseInt(i64, tok, 10) catch {
        return MalAtom{ .sym = tok };
    };
    return MalAtom{ .num = i };
}

fn readList(self: *Self) Error!?[]MalType {
    const tok_slice = self.tokens.items[self.pos..];
    const num_child = blk: {
        var cnt: usize = 0;
        var depth: usize = 0;
        for (tok_slice) |tok| {
            if (depth == 1 and tok[0] != ')') {
                cnt += 1;
            }
            switch (tok[0]) {
                '(' => depth += 1,
                ')' => depth -= 1,
                else => {},
            }
            if (depth == 0) break;
        }
        break :blk cnt;
    };
    // get rid of wrapping parens
    _ = self.next();
    defer _ = self.next();
    if (num_child == 0) return null;
    var ml = try self.allocator.alloc(MalType, num_child);
    var i: usize = 0;
    while (i < num_child) : (i += 1) {
        ml[i] = try self.readForm();
    }
    return ml;
}

fn destroy(self: *Self, form: *const MalType) void {
    if (std.meta.activeTag(form.*) == .list) {
        for (form.list) |subform| {
            self.destroy(&subform);
        }
        self.allocator.free(form.list);
    }
}

fn equal(a: MalType, b: MalType) bool {
    const a_tag = std.meta.activeTag(a);
    const b_tag = std.meta.activeTag(b);
    if (a_tag != b_tag) return false;
    switch (a_tag) {
        .list => {
            const a_len = a.list.len;
            const b_len = b.list.len;
            if (a_len != b_len) return false;
            var i: usize = 0;
            while (i < a_len) : (i += 1) {
                if (!equal(a.list[i], b.list[i])) return false;
            }
            return true;
        },
        .atom => {
            const a_atm_tag = std.meta.activeTag(a.atom);
            const b_atm_tag = std.meta.activeTag(b.atom);
            if (a_atm_tag != b_atm_tag) return false;
            switch (a_atm_tag) {
                .num => return a.atom.num == b.atom.num,
                .sym => return std.mem.eql(u8, a.atom.sym, b.atom.sym),
            }
        },
        .nil => {
            return b == .nil;
        },
    }
}

test "readForm" {
    var reader = Self.init(std.testing.allocator);
    defer reader.deinit();

    const Case = struct {
        input: []const u8,
        expected: MalType,
    };
    const cases = [_]Case{
        .{
            .input = "",
            .expected = .nil,
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
                    .{ .atom = .{ .num = 1 } },
                },
            },
        },
        .{
            .input = "(1 2)",
            .expected = .{
                .list = &.{
                    .{ .atom = .{ .num = 1 } },
                    .{ .atom = .{ .num = 2 } },
                },
            },
        },
        .{
            .input = "(1 (2))",
            .expected = .{
                .list = &.{
                    .{ .atom = .{ .num = 1 } },
                    .{
                        .list = &.{
                            .{ .atom = .{ .num = 2 } },
                        },
                    },
                },
            },
        },
        .{
            .input = "(1 (2) 3 (four (5 6)))",
            .expected = .{
                .list = &.{
                    .{ .atom = .{ .num = 1 } },
                    .{
                        .list = &.{
                            .{ .atom = .{ .num = 2 } },
                        },
                    },
                    .{ .atom = .{ .num = 3 } },
                    .{
                        .list = &.{
                            .{ .atom = .{ .sym = "four" } },
                            .{
                                .list = &.{
                                    .{ .atom = .{ .num = 5 } },
                                    .{ .atom = .{ .num = 6 } },
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
                    .nil,
                    .{ .atom = .{ .num = 3 } },
                    .nil,
                    .nil,
                },
            },
        },
        .{
            .input = "()",
            .expected = .nil,
        },
    };

    for (cases) |case, i| {
        try reader.tokenize(case.input);
        const exp = case.expected;
        const res = try reader.readForm();
        defer reader.destroy(&res);
        std.testing.expect(equal(exp, res)) catch |err| {
            std.debug.print("\nINPUT:\n{s}\n\n", .{cases[i].input});
            std.debug.print("EXPECTED:\n{}\nGOT:\n{}\n\n", .{ exp, res });
            std.debug.print("EXPECTED:\n{}\nGOT:\n{}\n\n", .{ exp.list[3], res.list[3] });
            return err;
        };
    }
}
