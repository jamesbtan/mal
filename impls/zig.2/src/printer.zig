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
                        .sym => {
                            try self.writer.print("{s}", .{form.atom.sym});
                        },
                        .num => {
                            try self.writer.print("{}", .{form.atom.num});
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
