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
        const exe = b.addExecutable(name, fname);
        exe.setTarget(target);
        exe.setBuildMode(mode);

        const i_step = b.addInstallArtifact(exe);
        const l_step = LinkStep.init(
            b,
            b.fmt("{s}/bin/{s}", .{ b.install_path, name }),
            b.fmt("{s}/{s}", .{ b.build_root, name }),
        );
        l_step.step.dependOn(&i_step.step);
        const b_step = b.step(name, "");
        b_step.dependOn(&l_step.step);
    }

    const test_step = b.step("test", "Run unit tests");
    const test_files = [_][]const u8{
        "src/reader.zig",
    };
    for (test_files) |file| {
        const itest = b.addTest(file);
        itest.setTarget(target);
        itest.setBuildMode(mode);
        test_step.dependOn(&itest.step);
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
