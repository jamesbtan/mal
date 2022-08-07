// Pointers / slices are unmanaged
// Memory handled by user
// May intern an allocator, however many atoms do not need it?
// Only things that need allocator: {MalType.{list, atom.{vector, hash}}}

const std = @import("std");

pub const MalType = union(enum) {
    list: ?*const MalList,
    atom: MalAtom,
};

pub const MalAtom = union(enum) {
    num: i64,
    sym: []const u8,
    keyword: []const u8,
    vector: std.ArrayList(MalType),
    nil,
};

pub const MalList = struct {
    car: MalType,
    cdr: ?*const MalList = null,
};
