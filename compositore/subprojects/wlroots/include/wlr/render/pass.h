/*
 * This an unstable interface of wlroots. No guarantees are made regarding the
 * future consistency of this API.
 */
#ifndef WLR_USE_UNSTABLE
#error "Add -DWLR_USE_UNSTABLE to enable unstable wlroots features"
#endif

#ifndef WLR_RENDER_PASS_H
#define WLR_RENDER_PASS_H

#include <pixman.h>
#include <stdint.h>
#include <wayland-server-core.h>
#include <wlr/render/color.h>
#include <wlr/render/minerva.h>
#include <wlr/util/box.h>

struct wlr_renderer;
struct wlr_buffer;

/**
 * A render pass accumulates drawing operations until submitted to the GPU.
 */
struct wlr_render_pass;

/**
 * An object that can be queried after a render to get the duration of the render.
 */
struct wlr_render_timer;

struct wlr_buffer_pass_options {
	/* Timer to measure the duration of the render pass */
	struct wlr_render_timer *timer;
	/* Color transform to apply to the output of the render pass.
	 * Leave NULL to indicate the default transform (Gamma 2.2 encoding for
	 * sRGB monitors) */
	struct wlr_color_transform *color_transform;

	/* Signal a timeline synchronization point when the render pass completes.
	 *
	 * When a compositor provides a signal timeline, the renderer may skip
	 * implicit signal synchronization.
	 *
	 * Support for this feature is advertised by features.timeline in
	 * struct wlr_renderer.
	 */
	struct wlr_drm_syncobj_timeline *signal_timeline;
	uint64_t signal_point;
};

/**
 * Begin a new render pass with the supplied destination buffer.
 *
 * Callers must call wlr_render_pass_submit() once they are done with the
 * render pass.
 */
struct wlr_render_pass *wlr_renderer_begin_buffer_pass(struct wlr_renderer *renderer,
	struct wlr_buffer *buffer, const struct wlr_buffer_pass_options *options);

/**
 * Submit the render pass.
 *
 * The render pass cannot be used after this function is called.
 */
bool wlr_render_pass_submit(struct wlr_render_pass *render_pass);

/**
 * Blend modes.
 */
enum wlr_render_blend_mode {
	/* Pre-multiplied alpha (default) */
	WLR_RENDER_BLEND_MODE_PREMULTIPLIED,
	/* Blending is disabled */
	WLR_RENDER_BLEND_MODE_NONE,
};

/**
 * Filter modes.
 */
enum wlr_scale_filter_mode {
	/* bilinear texture filtering (default) */
	WLR_SCALE_FILTER_BILINEAR,
	/* nearest texture filtering */
	WLR_SCALE_FILTER_NEAREST,
};

struct wlr_render_texture_options {
	struct wlr_minerva_style minerva;
	/* Source texture */
	struct wlr_texture *texture;
	/* Source coordinates, leave empty to render the whole texture */
	struct wlr_fbox src_box;
	/* Destination coordinates, width/height default to the texture size */
	struct wlr_box dst_box;
	/* Opacity between 0 (transparent) and 1 (opaque), leave NULL for opaque */
	const float *alpha;
	/* Clip region, leave NULL to disable clipping */
	const pixman_region32_t *clip;
	/* Transform applied to the source texture */
	enum wl_output_transform transform;
	/* Filtering */
	enum wlr_scale_filter_mode filter_mode;
	/* Blend mode */
	enum wlr_render_blend_mode blend_mode;
	/* Transfer function the source texture is encoded with */
	enum wlr_color_transfer_function transfer_function;
	/* Primaries describing the color volume of the source texture */
	const struct wlr_color_primaries *primaries;
	/* Color encoding of the source texture for YCbCr conversion to RGB */
	enum wlr_color_encoding color_encoding;
	/* Color range of the source texture */
	enum wlr_color_range color_range;
	/* Default: 1.0 */
	const float *luminance_multiplier;

	/* Wait for a timeline synchronization point before texturing.
	 *
	 * When a compositor provides a wait timeline, the renderer may skip
	 * implicit wait synchronization.
	 *
	 * Support for this feature is advertised by features.timeline in
	 * struct wlr_renderer.
	 */
	struct wlr_drm_syncobj_timeline *wait_timeline;
	uint64_t wait_point;
};

/**
 * Render a texture.
 */
void wlr_render_pass_add_texture(struct wlr_render_pass *render_pass,
	const struct wlr_render_texture_options *options);

/**
 * A color value.
 *
 * Each channel has values between 0 and 1 inclusive. The R, G, B
 * channels need to be pre-multiplied by A.
 */
struct wlr_render_color {
	float r, g, b, a;
};

struct wlr_render_rect_options {
	struct wlr_minerva_style minerva;
	/* Rectangle coordinates */
	struct wlr_box box;
	/* Source color */
	struct wlr_render_color color;
	/* Clip region, leave NULL to disable clipping */
	const pixman_region32_t *clip;
	/* Blend mode */
	enum wlr_render_blend_mode blend_mode;
};

/**
 * Render a rectangle.
 */
void wlr_render_pass_add_rect(struct wlr_render_pass *render_pass,
	const struct wlr_render_rect_options *options);

/* Optional mask carries the same acquire fence as a regular texture draw. */
bool wlr_minerva_render_blur(struct wlr_render_pass *, const struct wlr_render_rect_options *, const struct wlr_render_texture_options *);

/* Minerva: mette da parte i pixel del fotogramma dentro `region` e poi li
 * rimette com'erano. Serve al danno incrementale del blur: lo sfondo si
 * ridisegna in una fascia più larga del pezzo che cambia, perché la
 * sfocatura al bordo del pezzo legga sfondo vero e non l'immagine finale di
 * prima; la fascia, finito il fotogramma, torna com'era. Un renderer che non
 * le ha risponde false, e la scena non allarga niente. */
bool wlr_minerva_render_salva(struct wlr_render_pass *, const pixman_region32_t *region);
bool wlr_minerva_render_ripristina(struct wlr_render_pass *, const pixman_region32_t *region);
#endif
