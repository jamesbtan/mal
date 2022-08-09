const std = @import("std");
const Allocator = std.mem.Allocator;
const T = @import("types.zig");

allocator: Allocator,

const Self = @This();
pub const Error = error{
    TokenizeError,
} || ParseError || Allocator.Error;
const ParseError = error{
    EndOfTokens,
    InvalidKey,
    InvalidSyntax,
    MismatchBrace,
};

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn readStr(self: *Self, str: []const u8) Error!T.MalType {
    var tok_iter = tokenizer(str);
    return try self.readForm(&tok_iter);
}

const TokenIterator = struct {
    str_slice: []const u8,
    memo: ?[]const u8 = null,

    const IterSelf = @This();

    pub fn next(self: *IterSelf) Error!?[]const u8 {
        const slice = (try self.peekAndInvalidate()) orelse return null;
        self.str_slice = self.str_slice[slice.len..];
        return slice;
    }

    pub fn peek(self: *IterSelf) Error!?[]const u8 {
        if (self.memo != null) {
            return self.memo;
        }

        const allsym = "[]{}()'`~^@, \t\n\r";
        const special = allsym[0..11];
        const whitespace = allsym[11..];
        self.str_slice = std.mem.trimLeft(u8, self.str_slice, whitespace);
        if (self.str_slice.len == 0) {
            self.memo = null;
        } else if (self.str_slice.len >= 2 and std.mem.eql(u8, self.str_slice[0..2], "~@")) {
            self.memo = self.str_slice[0..2];
        } else if (std.mem.indexOfScalar(u8, special, self.str_slice[0]) != null) {
            self.memo = self.str_slice[0..1];
        } else if (self.str_slice[0] == '"') {
            var offset: usize = 1;
            while (true) {
                // if null, unbalanced string
                const ind = std.mem.indexOfAnyPos(u8, self.str_slice, offset, "\"\\") orelse return Error.TokenizeError;
                offset = ind;
                switch (self.str_slice[offset]) {
                    '\\' => offset += 2,
                    '"' => {
                        self.memo = self.str_slice[0 .. offset + 1];
                        break;
                    },
                    else => unreachable,
                }
            }
        } else if (self.str_slice[0] == ';') { // last 2 are similar?
            if (std.mem.indexOfScalar(u8, self.str_slice, '\n')) |ind| {
                self.memo = self.str_slice[0..ind];
            } else {
                self.memo = self.str_slice[0..];
            }
        } else {
            if (std.mem.indexOfAny(u8, self.str_slice, allsym)) |ind| {
                self.memo = self.str_slice[0..ind];
            } else {
                self.memo = self.str_slice[0..];
            }
        }

        return self.memo;
    }

    fn peekAndInvalidate(self: *IterSelf) Error!?[]const u8 {
        defer self.memo = null;
        return self.peek();
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

fn readForm(self: *const Self, tok_iter: *TokenIterator) Error!T.MalType {
    if (try tok_iter.peek()) |tok| {
        switch (tok[0]) {
            '(' => {
                _ = try tok_iter.next();
                return T.MalType{ .list = try self.readList(tok_iter) };
            },
            '\'', '`', '~', '@' => |c| {
                _ = try tok_iter.next();
                const sym = blk: {
                    if (std.mem.eql(u8, tok, "~@")) {
                        break :blk "splice-unquote";
                    } else {
                        break :blk switch (c) {
                            '\'' => "quote",
                            '`' => "quasiquote",
                            '~' => "unquote",
                            '@' => "deref",
                            else => unreachable,
                        };
                    }
                };
                const form = try self.readForm(tok_iter);
                errdefer T.destroy(&form, self.allocator);
                const ml = try T.MalList.construct(&[_]T.MalType{
                    form, .{ .atom = .{ .sym = sym } },
                }, self.allocator);
                errdefer T.destroy(ml, alloc);
                return T.MalType{ .list = ml };
            },
            '^' => {
                _ = try tok_iter.next();
                const meta = try self.readForm(tok_iter);
                errdefer T.destroy(&meta, self.allocator);
                const form = try self.readForm(tok_iter);
                errdefer T.destroy(&form, self.allocator);
                const ml = try T.MalList.construct(&[_]T.MalType{
                    meta, form, .{ .atom = .{ .sym = "with-meta" } },
                }, self.allocator);
                return T.MalType{ .list = ml };
            },
            else => return T.MalType{ .atom = try self.readAtom(tok_iter) },
        }
    } else {
        return T.MalType{ .atom = .nil };
    }
}

fn readAtom(self: *const Self, tok_iter: *TokenIterator) Error!T.MalAtom {
    const tok = (try tok_iter.next()) orelse return ParseError.EndOfTokens;
    switch (tok[0]) {
        ';' => return .nil,
        ':' => {
            if (tok.len == 1) return ParseError.InvalidSyntax;
            return T.MalAtom{ .keyword = tok };
        },
        '"' => return T.MalAtom{ .str = tok },
        '[' => return T.MalAtom{ .vector = try self.readVec(tok_iter) },
        '{' => return T.MalAtom{ .hash = try self.readHash(tok_iter) },
        else => {},
    }
    if (std.mem.eql(u8, "true", tok)) {
        return T.MalAtom{ .bool = true };
    } else if (std.mem.eql(u8, "false", tok)) {
        return T.MalAtom{ .bool = false };
    } else if (std.fmt.parseInt(i64, tok, 10)) |i| {
        return T.MalAtom{ .num = i };
    } else |_| {
        return T.MalAtom{ .sym = tok };
    }
}

fn readVec(self: *const Self, tok_iter: *TokenIterator) Error!std.ArrayList(T.MalType) {
    var vec = std.ArrayList(T.MalType).init(self.allocator);
    errdefer T.destroyVec(vec, self.allocator);

    while (try tok_iter.peek()) |tok| {
        switch (tok[0]) {
            ']' => {
                _ = try tok_iter.next();
                break;
            },
            ')', '}' => return ParseError.MismatchBrace,
            else => {
                try vec.append(try self.readForm(tok_iter));
            },
        }
    } else {
        return ParseError.EndOfTokens;
    }
    return vec;
}

fn readHash(self: *const Self, tok_iter: *TokenIterator) Error!std.StringHashMap(T.MalType) {
    _ = tok_iter;
    var hash = std.StringHashMap(T.MalType).init(self.allocator);
    errdefer T.destroyHash(&hash, self.allocator);

    while (try tok_iter.peek()) |tok| {
        switch (tok[0]) {
            '}' => {
                _ = try tok_iter.next();
                break;
            },
            ')', ']' => return ParseError.MismatchBrace,
            else => {},
        }
        const key = try self.readForm(tok_iter);
        switch (key) {
            .atom => |a| {
                switch (a) {
                    .str, .keyword => |s| {
                        const value = try self.readForm(tok_iter);
                        const entry = try hash.getOrPut(s);
                        if (entry.found_existing) {
                            return ParseError.InvalidKey;
                        }
                        entry.value_ptr.* = value;
                        continue;
                    },
                    else => {},
                }
            },
            else => {},
        }
        return ParseError.InvalidKey;
    } else {
        return ParseError.EndOfTokens;
    }
    return hash;
}

fn readList(self: *const Self, tok_iter: *TokenIterator) Error!?*T.MalList {
    if (try tok_iter.peek()) |tok| {
        switch (tok[0]) {
            ')' => {
                _ = try tok_iter.next();
                return null;
            },
            ']', '}' => return ParseError.MismatchBrace,
            else => {},
        }
        const form = try self.readForm(tok_iter);
        errdefer T.destroy(&form, self.allocator);
        // TODO rewrite direct recursion
        const sublist = try self.readList(tok_iter);
        errdefer T.destroyList(sublist, self.allocator);
        const ml = try T.MalList.allocPair(form, sublist, self.allocator);
        return ml;
    } else {
        return ParseError.EndOfTokens;
    }
}

test "readForm - basic tests" {
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
        .{
            .input = "~@(1)",
            .expected = .{
                .list = &.{
                    .car = .{ .atom = .{ .sym = "splice-unquote" } },
                    .cdr = &.{
                        .car = .{
                            .list = &.{
                                .car = .{ .atom = .{ .num = 1 } },
                            },
                        },
                    },
                },
            },
        },
    };
    for (cases) |case, i| {
        const exp = case.expected;
        const res = try reader.readStr(case.input);
        defer T.destroy(&res, reader.allocator);
        std.testing.expect(T.equal(exp, res)) catch |err| {
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

test "parser errors" {
    var reader = Self.init(std.testing.allocator);

    const Case = struct {
        input: []const u8,
        expected: Error,
    };
    const cases = [_]Case{
        .{
            .input = "(",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "[",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "[ 1",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "[ 1 2",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "[ [ 1 2 ]",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "((",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "([",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "(()",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "([]",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "(((",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "((]",
            .expected = ParseError.MismatchBrace,
        },
        .{
            .input = "((([[]",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "{",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "{{",
            .expected = ParseError.EndOfTokens,
        },
        .{
            .input = "{{]",
            .expected = ParseError.MismatchBrace,
        },
        .{
            .input = "{{[()}",
            .expected = ParseError.MismatchBrace,
        },
    };

    for (cases) |case| {
        const exp = case.expected;
        std.testing.expectError(exp, reader.readStr(case.input)) catch |e| {
            std.debug.print("{s}\n", .{case.input});
            return e;
        };
    }
}

test "hash - leak detection" {
    var reader = Self.init(std.testing.allocator);

    const res = try reader.readStr("{:a {:b {:c 3}}}");
    defer T.destroy(&res, reader.allocator);
}
