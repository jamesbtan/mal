// Pointers / slices are unmanaged
// Memory handled by user
// May intern an allocator, however many atoms do not need it?
// Only things that need allocator: {MalType.{list, atom.{vector, hash}}}

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MalType = union(enum) {
    list: ?*const MalList,
    atom: MalAtom,
};

pub const MalAtom = union(enum) {
    num: i64,
    sym: []const u8,
    str: []const u8,
    keyword: []const u8,
    vector: std.ArrayList(MalType),
    hash: std.StringHashMap(MalType),
    bool: bool,
    nil,
};

pub const MalList = struct {
    car: MalType,
    cdr: ?*const MalList = null,

    pub fn allocPair(car: MalType, cdr: ?*const MalList, alloc: Allocator) Allocator.Error!*MalList {
        var ml = try alloc.create(MalList);
        ml.car = car;
        ml.cdr = cdr;
        return ml;
    }

    pub fn construct(elems: []MalType, alloc: Allocator) Allocator.Error!?*MalList {
        var ml: ?*MalList  = null;
        errdefer destroyList(ml, alloc);
        for (elems) |elem| {
            const next = try allocPair(elem, ml, alloc);
            ml = next;
        }
        return ml;
    }
};

pub fn equal(a: MalType, b: MalType) bool {
    const a_tag = std.meta.activeTag(a);
    const b_tag = std.meta.activeTag(b);
    if (a_tag != b_tag) return false;
    switch (a_tag) {
        .atom => {
            const a_atm_tag = std.meta.activeTag(a.atom);
            const b_atm_tag = std.meta.activeTag(b.atom);
            if (a_atm_tag != b_atm_tag) return false;
            switch (a_atm_tag) {
                .sym, .str, .keyword => return std.mem.eql(u8, a.atom.sym, b.atom.sym),
                else => return std.meta.eql(a, b),
            }
        },
        .list => {
            return equalList(a.list, b.list);
        },
    }
}

fn equalList(a: ?*const MalList, b: ?*const MalList) bool {
    var x: ?*const MalList = a;
    var y: ?*const MalList = b;
    while (x != null and y != null) {
        if (!equal(x.?.car, y.?.car)) return false;
        x = x.?.cdr;
        y = y.?.cdr;
    }
    return x == y;
}

pub fn destroy(form: *const MalType, alloc: Allocator) void {
    switch (form.*) {
        .list => |l| destroyList(l, alloc),
        .atom => |a| switch (a) {
            .vector => |v| destroyVec(v, alloc),
            .hash => |h| destroyHash(&h, alloc),
            else => {},
        },
    }
}

pub fn destroyList(list: ?*const MalList, alloc: Allocator) void {
    var curr = list;
    while (curr != null) {
        const next = curr.?.cdr;
        destroy(&curr.?.car, alloc);
        alloc.destroy(curr.?);
        curr = next;
    }
}

pub fn destroyVec(vec: std.ArrayList(MalType), alloc: Allocator) void {
    for (vec.items) |e| {
        destroy(&e, alloc);
    }
    vec.deinit();
}

pub fn destroyHash(hash: *const std.StringHashMap(MalType), alloc: Allocator) void {
    var v_iter = hash.valueIterator();
    while (v_iter.next()) |v| {
        destroy(v, alloc);
    }
    const hash_ptr = @intToPtr(*std.StringHashMap(MalType), @ptrToInt(hash));
    hash_ptr.deinit();
}
