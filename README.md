# vector-feedback

A video-feedback device written in Zig 0.17.0 that renders vector graphics on the GPU with
[slughorn](https://github.com/AlphaPixel/slughorn), a C++20 implementation of the Slug technique.

It works like pointing a camera at the monitor it feeds. Each frame, the previous image is
shown on a rectangular **picture plane** in front of a virtual camera. You move that plane
(pan, roll, zoom, and yaw/pitch tilt in perspective), and the movement builds up recursive
tunnels, spirals and trails. Animated vector shapes, packed by slughorn and drawn with the
Slug coverage shader, keep adding new light to the loop. A HUD shows the rendering FPS in
real time. The HUD text is also slughorn vector shapes.

## Requirements

- Zig 0.17.0
- GLFW 3.x and OpenGL 3.3 core (Fedora: `sudo dnf install glfw-devel mesa-libGL-devel`)
- For headless testing: `xvfb-run` (Xvfb) and Mesa (llvmpipe works)

The build fetches slughorn as a package, pinned to a commit in `build.zig.zon`. Zig's bundled
clang/libc++ compiles it, so you don't need CMake.

## Build and run

```sh
zig build run                                  # debug
zig build -Doptimize=ReleaseFast run -- --no-vsync
zig build run -- --seed spiral --tail 0.97
```

Options: `--width N`, `--height N`, `--no-vsync`, `--seed none|stars|rings|text|spiral`,
`--tail X`, `--show-help`, `--frames N`, `--screenshot FILE.ppm`, `--selftest`, `--help`.

## Controls

| Input | Action |
|---|---|
| Left drag | Pan the picture plane |
| Right drag | Roll (horizontal) and zoom (vertical) |
| Middle drag, or Shift/Ctrl + left drag | Tilt the plane (yaw/pitch) |
| Mouse wheel | Zoom |
| Arrow keys | Pan |
| Q / E | Roll |
| W / S (also `=` / `-`) | Zoom in / out |
| J / L, I / K | Yaw, pitch |
| `[` / `]` | Shorter / longer feedback tail |
| `,` / `.` | Hue shift per pass |
| 0–4, Tab | Choose / cycle seed shape (none, stars, rings, text, spiral) |
| Space | Pause seed animation |
| B | Toggle a bright border on the plane (the monitor bezel) |
| M | Seed follows the mouse cursor |
| C / R | Clear buffers / reset everything |
| H / F1 / V / Esc | HUD / help overlay / vsync / quit |

The **tail** is the gain applied to the previous frame on each pass. The HUD shows it next to
the number of frames it takes an echo to fade to 1%.

## Testing (headless)

```sh
zig build test    # unit tests: math, camera, controls, FPS, shapes, slughorn shim, geometry, HUD
zig build smoke   # runs the app under xvfb-run with --selftest
```

`--selftest` renders frames on the real GL context and reads back the framebuffers. It checks
that:

- vector content and the HUD are drawn
- FPS is measured
- the image persists through the feedback loop alone after the seed is removed
- panning the plane moves the echo
- a zero tail clears the loop
- resizing rebuilds the buffers

## Layout

| File | Purpose |
|---|---|
| `src/c/slughorn_c.{h,cpp}` | `extern "C"` shim over `slughorn::Atlas` |
| `src/slughorn.zig` | Zig wrapper for the shim |
| `src/shapes.zig` | Procedural paths (star, ring, heart, flower, spiral, box) and the stroke font |
| `src/geometry.zig` | Slug quad vertices and text layout |
| `src/camera.zig`, `src/math.zig` | Picture-plane transform |
| `src/controls.zig` | Mouse/keyboard → plane and feedback parameters |
| `src/feedback.zig`, `src/fps.zig` | Tail parameters, FPS counter |
| `src/scene.zig` | Seed animations and HUD content |
| `src/shaders.zig`, `src/renderer.zig` | GL 3.3 renderer (ping-pong RGBA16F feedback buffers) |
| `src/main.zig` | Window, input, frame loop, CLI, selftest |

The Slug fragment shader is adapted from slughorn's `example/slughorn-example-glfw.cpp`
(MIT, © 2026 AlphaPixel LLC).
