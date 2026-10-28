const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const slughorn_dep = b.dependency("slughorn", .{});

    // slughorn core (C++20) plus our C ABI shim, compiled with Zig's bundled clang/libc++.
    const slughorn_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    slughorn_mod.addIncludePath(slughorn_dep.path(""));
    slughorn_mod.addIncludePath(b.path("src/c"));
    const cxx_flags: []const []const u8 = &.{ "-std=c++20", "-fno-sanitize=undefined" };
    slughorn_mod.addCSourceFile(.{ .file = slughorn_dep.path("slughorn/slughorn.cpp"), .flags = cxx_flags });
    slughorn_mod.addCSourceFile(.{ .file = b.path("src/c/slughorn_c.cpp"), .flags = cxx_flags });
    const slughorn_lib = b.addLibrary(.{ .name = "slughorn", .root_module = slughorn_mod });

    const slughorn_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c/slughorn_c.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const gl_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c/gl.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addImport("slughorn_c", slughorn_c);
    exe_mod.addImport("gl_c", gl_c);
    exe_mod.linkLibrary(slughorn_lib);
    exe_mod.linkSystemLibrary("glfw", .{});
    exe_mod.linkSystemLibrary("GL", .{});

    const exe = b.addExecutable(.{ .name = "vector-feedback", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Run the vector feedback visualizer").dependOn(&run_cmd.step);

    // Unit tests: pure logic plus the slughorn shim; no display required.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("slughorn_c", slughorn_c);
    test_mod.addImport("gl_c", gl_c);
    test_mod.linkLibrary(slughorn_lib);
    const unit_tests = b.addTest(.{ .root_module = test_mod });
    const test_step = b.step("test", "Run headless unit tests");
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Headless end-to-end check: renders frames on a virtual X server (Mesa llvmpipe),
    // reads the framebuffer back and validates it.
    const smoke = b.addSystemCommand(&.{ "xvfb-run", "-a", "-s", "-screen 0 1280x800x24" });
    smoke.addArtifactArg(exe);
    smoke.addArgs(&.{ "--selftest", "--frames", "120" });
    smoke.addArg("--screenshot");
    _ = smoke.addOutputFileArg("selftest.ppm");
    smoke.expectExitCode(0);
    smoke.has_side_effects = true;
    b.step("smoke", "Render frames headless under Xvfb and validate output").dependOn(&smoke.step);
}
