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
                    for (form.list) |subform, i| {
                        if (i != 0) {
                            try self.writer.print(" ", .{});
                        }
                        try self.prStrNonRoot(subform);
                    }
                    try self.writer.print(")", .{});
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
                        }
                    }
                }
            }
        }
    };
}
