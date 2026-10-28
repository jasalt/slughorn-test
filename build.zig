const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const slughorn_dep = b.dependency("slughorn", .{});

    const slughorn_lib = addSlughorn(b, slughorn_dep, target, optimize);
    const slughorn_c = translateShim(b, target, optimize);

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

    // WebGL2 build: the same app core compiled to wasm32-wasi (libc/libc++ come from Zig's
    // bundled wasi-libc), with src/web_gl.zig standing in for the GL headers.
    const web_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const web_optimize = b.option(std.builtin.OptimizeMode, "web-optimize", "Optimization mode for the web build (default small)") orelse .small;
    const web_mod = b.createModule(.{
        .root_source_file = b.path("src/web_main.zig"),
        .target = web_target,
        .optimize = web_optimize,
        .link_libc = true,
    });
    web_mod.addImport("slughorn_c", translateShim(b, web_target, web_optimize));
    web_mod.addImport("gl_c", b.createModule(.{ .root_source_file = b.path("src/web_gl.zig"), .target = web_target, .optimize = web_optimize }));
    web_mod.linkLibrary(addSlughorn(b, slughorn_dep, web_target, web_optimize));
    const wasm = b.addExecutable(.{ .name = "vector-feedback", .root_module = web_mod });
    // A WASI reactor: no main, exports called from JS after _initialize runs constructors.
    wasm.entry = .disabled;
    wasm.wasi_exec_model = .reactor;
    wasm.rdynamic = true;

    const web_step = b.step("web", "Build the WebGL2/WebAssembly version into zig-out/web");
    web_step.dependOn(&b.addInstallArtifact(wasm, .{ .dest_dir = .{ .override = .{ .custom = "web" } } }).step);
    web_step.dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("web"),
        .install_dir = .{ .custom = "web" },
        .install_subdir = "",
        .exclude_extensions = &.{ ".sh", ".py" },
    }).step);
}

/// slughorn core (C++20) plus our C ABI shim, compiled with Zig's bundled clang/libc++.
fn addSlughorn(b: *std.Build, dep: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    mod.addIncludePath(dep.path(""));
    mod.addIncludePath(b.path("src/c"));
    const cxx_flags: []const []const u8 = &.{ "-std=c++20", "-fno-sanitize=undefined" };
    mod.addCSourceFile(.{ .file = dep.path("slughorn/slughorn.cpp"), .flags = cxx_flags });
    mod.addCSourceFile(.{ .file = b.path("src/c/slughorn_c.cpp"), .flags = cxx_flags });
    if (target.result.cpu.arch.isWasm()) mod.addCSourceFile(.{ .file = b.path("src/c/wasm_cxa.c") });
    return b.addLibrary(.{ .name = "slughorn", .root_module = mod });
}

fn translateShim(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.addTranslateC(.{
        .root_source_file = b.path("src/c/slughorn_c.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
}
