#include "slughorn_c.h"

#include "slughorn/slughorn.hpp"

#include <exception>
#include <string>

struct sh_atlas {
	slughorn::Atlas atlas;
	slughorn::Atlas::ShapeInfo pending;
	slughorn::CurveDecomposer decomposer{pending.curves};
	std::string error;
};

namespace {

template<typename F>
bool guarded(sh_atlas* a, F&& fn) {
	try {
		fn();
		return true;
	} catch(const std::exception& e) {
		a->error = e.what();
	} catch(...) {
		a->error = "unknown slughorn exception";
	}

	return false;
}

void fillTexture(const slughorn::Atlas::TextureData& td, sh_texture* out) {
	out->bytes = td.bytes.data();
	out->size = td.bytes.size();
	out->width = td.width;
	out->height = td.height;
	out->format = static_cast<uint32_t>(td.format);
}

}

extern "C" {

sh_atlas* sh_atlas_create(void) {
	try {
		return new sh_atlas();
	} catch(...) {
		return nullptr;
	}
}

void sh_atlas_destroy(sh_atlas* a) {
	delete a;
}

void sh_begin_shape(sh_atlas* a) {
	a->pending = slughorn::Atlas::ShapeInfo{};
	a->decomposer.curves.clear();
}

void sh_move_to(sh_atlas* a, float x, float y) {
	guarded(a, [&] {
		a->pending.contourStarts.push_back(a->pending.curves.size());
		a->decomposer.moveTo(x, y);
	});
}

void sh_line_to(sh_atlas* a, float x, float y) {
	guarded(a, [&] { a->decomposer.lineTo(x, y); });
}

void sh_quad_to(sh_atlas* a, float cx, float cy, float x, float y) {
	guarded(a, [&] { a->decomposer.quadTo(cx, cy, x, y); });
}

void sh_cubic_to(sh_atlas* a, float c1x, float c1y, float c2x, float c2y, float x, float y) {
	guarded(a, [&] { a->decomposer.cubicTo(c1x, c1y, c2x, c2y, x, y); });
}

void sh_close(sh_atlas* a) {
	guarded(a, [&] { a->decomposer.close(); });
}

size_t sh_pending_curve_count(const sh_atlas* a) {
	return a->pending.curves.size();
}

int sh_end_shape(sh_atlas* a, uint32_t key) {
	// Drop contour starts that never received a curve (moveTo with nothing after it).
	auto& starts = a->pending.contourStarts;
	const size_t n = a->pending.curves.size();

	std::erase_if(starts, [n](size_t s) { return s >= n; });

	for(size_t i = 1; i < starts.size();) {
		if(starts[i] == starts[i - 1]) starts.erase(starts.begin() + static_cast<std::ptrdiff_t>(i));
		else i++;
	}

	const bool ok = guarded(a, [&] { a->atlas.addShape(slughorn::Key(key), a->pending); });

	sh_begin_shape(a);

	return ok ? 0 : -1;
}

int sh_build(sh_atlas* a) {
	return guarded(a, [&] { a->atlas.build(); }) ? 0 : -1;
}

void sh_curve_texture(const sh_atlas* a, sh_texture* out) {
	fillTexture(a->atlas.getCurveTextureData(), out);
}

void sh_band_texture(const sh_atlas* a, sh_texture* out) {
	fillTexture(a->atlas.getBandTextureData(), out);
}

int sh_get_shape(const sh_atlas* a, uint32_t key, sh_shape* out) {
	const auto shape = a->atlas.getShape(slughorn::Key(key));

	if(!shape) return 0;

	out->band_tex_x = shape->bandTexX;
	out->band_tex_y = shape->bandTexY;
	out->band_max_x = shape->bandMaxX;
	out->band_max_y = shape->bandMaxY;
	out->band_scale_x = shape->bandScaleX;
	out->band_scale_y = shape->bandScaleY;
	out->band_offset_x = shape->bandOffsetX;
	out->band_offset_y = shape->bandOffsetY;
	out->bearing_x = shape->bearingX;
	out->bearing_y = shape->bearingY;
	out->width = shape->width;
	out->height = shape->height;
	out->advance = shape->advance;

	return 1;
}

const char* sh_last_error(const sh_atlas* a) {
	return a->error.c_str();
}

}
