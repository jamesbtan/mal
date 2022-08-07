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
                        .sym => |s| {
                            try self.writer.print("{s}", .{s});
                        },
                        .keyword => |k| {
                            try self.writer.print(":{s}", .{k});
                        },
                        .num => |n| {
                            try self.writer.print("{}", .{n});
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
                        }
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
