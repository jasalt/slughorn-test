//! Headless unit test root.
test {
    _ = @import("slughorn.zig");
    _ = @import("math.zig");
    _ = @import("camera.zig");
    _ = @import("fps.zig");
    _ = @import("feedback.zig");
}
