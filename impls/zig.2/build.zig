const std = @import("std");
const Builder = std.build.Builder;
const Step = std.build.Step;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const steps = [_][]const u8{
        "repl",
        "read_print",
        "eval",
        "env",
        "if_fn_do",
        "tco",
        "file",
        "quote",
        "macros",
        "try",
        "mal",
    };

    for (steps) |step, i| {
        const name = b.fmt("step{X}_{s}", .{ i, step });
        const fname = b.fmt("src/{s}.zig", .{name});
        const xtable = b.addExecutable(name, fname);
        xtable.setTarget(target);
        xtable.setBuildMode(mode);

        const i_step = b.addInstallArtifact(xtable);
        const l_step = LinkStep.init(b, b.fmt("zig-out/bin/{s}", .{name}), name);
        l_step.step.dependOn(&i_step.step);
        const b_step = b.step(name, "");
        b_step.dependOn(&l_step.step);
    }
}

const LinkStep = struct {
    step: Step,
    source: []const u8,
    target: []const u8,

    const Self = @This();

    fn init(b: *Builder, source: []const u8, target: []const u8) *Self {
        const self = b.allocator.create(Self) catch unreachable;
        self.* = .{
            .step = Step.init(
                .custom,
                b.fmt("link: {s} -> {s}", .{ source, target }),
                b.allocator,
                make,
            ),
            .source = source,
            .target = target,
        };
        return self;
    }

    fn make(step: *Step) anyerror!void {
        const self = @fieldParentPtr(Self, "step", step);
        const cwd = std.fs.cwd();
        cwd.symLink(self.source, self.target, .{}) catch |err| switch (err) {
            error.PathAlreadyExists => {
                cwd.deleteFile(self.target) catch {};
                return try make(step);
            },
            else => return err,
        };
    }
};
