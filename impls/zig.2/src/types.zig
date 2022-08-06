pub const MalType = union(enum) {
    list: []const MalType,
    atom: MalAtom,
};

pub const MalAtom = union(enum) {
    num: i64,
    sym: []const u8,
    nil,
};
