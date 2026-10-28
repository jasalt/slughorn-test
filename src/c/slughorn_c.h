// Minimal C ABI over the slughorn C++ Atlas so Zig can drive it.
#ifndef SLUGHORN_C_H
#define SLUGHORN_C_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sh_atlas sh_atlas;

// Mirrors slughorn::Atlas::TextureData::Format ordering.
enum {
	SH_FORMAT_RGBA32F = 0,
	SH_FORMAT_RGBA16F = 1,
	SH_FORMAT_RGBA16UI = 2,
	SH_FORMAT_RG16UI = 3,
};

typedef struct sh_texture {
	const void* bytes;
	size_t size;
	uint32_t width;
	uint32_t height;
	uint32_t format;
} sh_texture;

typedef struct sh_shape {
	uint32_t band_tex_x, band_tex_y;
	uint32_t band_max_x, band_max_y;
	float band_scale_x, band_scale_y;
	float band_offset_x, band_offset_y;
	float bearing_x, bearing_y;
	float width, height;
	float advance;
} sh_shape;

sh_atlas* sh_atlas_create(void);
void sh_atlas_destroy(sh_atlas* atlas);

// Path recording for the shape currently being authored. Coordinates are em-space.
void sh_begin_shape(sh_atlas* atlas);
void sh_move_to(sh_atlas* atlas, float x, float y);
void sh_line_to(sh_atlas* atlas, float x, float y);
void sh_quad_to(sh_atlas* atlas, float cx, float cy, float x, float y);
void sh_cubic_to(sh_atlas* atlas, float c1x, float c1y, float c2x, float c2y, float x, float y);
void sh_close(sh_atlas* atlas);
size_t sh_pending_curve_count(const sh_atlas* atlas);

// Registers the pending path under `key`. Returns 0 on success, -1 on error.
int sh_end_shape(sh_atlas* atlas, uint32_t key);

// Packs all shapes into the curve/band textures. Returns 0 on success, -1 on error.
int sh_build(sh_atlas* atlas);

void sh_curve_texture(const sh_atlas* atlas, sh_texture* out);
void sh_band_texture(const sh_atlas* atlas, sh_texture* out);

// Returns 1 and fills `out` if `key` is registered, 0 otherwise.
int sh_get_shape(const sh_atlas* atlas, uint32_t key, sh_shape* out);

// Message of the last failed call (empty string if none).
const char* sh_last_error(const sh_atlas* atlas);

#ifdef __cplusplus
}
#endif

#endif
