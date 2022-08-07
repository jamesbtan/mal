pub const MalType = union(enum) {
    list: ?*const MalList,
    atom: MalAtom,
};

pub const MalAtom = union(enum) {
    num: i64,
    sym: []const u8,
    nil,
};

pub const MalList = struct {
    car: MalType,
    cdr: ?*const MalList = null,
};
