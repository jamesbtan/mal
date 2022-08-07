// printer interface kinda jank..
const types = @import("types.zig");

pub fn Printer(comptime Writer: type) type {
    return struct {
        writer: Writer,

        pub const Error = Writer.Error;
        const Self = @This();

        pub fn init(writer: Writer) Self {
            return .{ .writer = writer };
        }

        pub fn prStr(self: *const Self, form: types.MalType) Error!void {
            try self.prStrNonRoot(form);
            try self.writer.print("\n", .{});
        }

        fn prStrNonRoot(self: *const Self, form: types.MalType) Error!void {
            switch (form) {
                .list => {
                    try self.writer.print("(", .{});
                    try self.prListCdr(form.list);
                },
                .atom => {
                    switch (form.atom) {
                        .nil => {
                            try self.writer.print("NIL", .{});
                        },
                        .sym, .str, .keyword => |s| {
                            try self.writer.print("{s}", .{s});
                        },
                        .num => |n| {
                            try self.writer.print("{}", .{n});
                        },
                        .bool => |b| {
                            try self.writer.print("{}", .{b});
                        },
                        .vector => |v| {
                            try self.writer.print("[", .{});
                            for (v.items) |e, i| {
                                if (i != 0) {
                                    try self.writer.print(" ", .{});
                                }
                                try self.prStrNonRoot(e);
                            }
                            try self.writer.print("]", .{});
                        },
                        .hash => |h| {
                            // is there a better way to print braces?
                            try self.writer.print("{c}", .{'{'});
                            var e_iter = h.iterator();
                            var first = true;
                            while (e_iter.next()) |e| {
                                if (first) {
                                    first = false;
                                } else {
                                    try self.writer.print(" ", .{});
                                }
                                try self.writer.print("{s} ", .{ e.key_ptr.* });
                                try self.prStrNonRoot(e.value_ptr.*);
                            }
                            try self.writer.print("{c}", .{'}'});
                        },
                    }
                },
            }
        }

        fn prListCdr(self: *const Self, cdr: ?*const types.MalList) Error!void {
            if (cdr) |cdr_v| {
                try self.prStrNonRoot(cdr_v.*.car);
                const n_cdr = cdr_v.*.cdr;
                if (n_cdr != null) {
                    try self.writer.print(" ", .{});
                }
                try self.prListCdr(n_cdr);
            } else {
                try self.writer.print(")", .{});
            }
        }
    };
}
