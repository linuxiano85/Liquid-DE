/* SPDX-License-Identifier: MIT
 * Minerva's presentation constraints. Commit state belongs to wl_surface,
 * not to the protocol object: destroying an object must not cancel commits.
 * GPU acquire fences continue to use wlroots' independent cached-state locks.
 */
#include <assert.h>
#include <limits.h>
#include <stdlib.h>
#include <time.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_minerva_timing.h>
#include "fifo-v1-protocol.h"
#include "commit-timing-v1-protocol.h"

struct timing_globals {
	struct wl_global *fifo, *timing;
	struct wl_listener destroy;
};

static bool synchronized(struct wlr_surface *surface) {
	struct wlr_subsurface *sub;
	while ((sub = wlr_subsurface_try_from_wlr_surface(surface))) {
		if (sub->synchronized) return true;
		surface = sub->parent;
	}
	return false;
}

static bool visible(struct wlr_surface *surface) {
	struct wlr_surface_output *out;
	wl_list_for_each(out, &surface->current_outputs, link) {
		if (!out->suspended && out->output->enabled) return true;
	}
	return false;
}

static int wake(void *data) {
	wlr_minerva_surface_drain(data);
	return 0;
}

static void arm(struct wlr_surface *surface, int ms) {
	if (surface->minerva.destroying) return;
	if (!surface->minerva.timer) {
		struct wl_display *d = wl_client_get_display(wl_resource_get_client(surface->resource));
		surface->minerva.timer = wl_event_loop_add_timer(wl_display_get_event_loop(d), wake, surface);
		if (!surface->minerva.timer) {
			wl_resource_post_no_memory(surface->resource);
			return;
		}
	}
	wl_event_source_timer_update(surface->minerva.timer, ms);
}

static int timestamp_delay(const struct wlr_minerva_commit_constraints *c,
		const struct timespec *now) {
	if (!c->has_timestamp || c->seconds < (uint64_t)now->tv_sec ||
			(c->seconds == (uint64_t)now->tv_sec && c->nanoseconds <= (uint32_t)now->tv_nsec)) return 0;
	uint64_t sec = c->seconds - (uint64_t)now->tv_sec;
	/* Saturate without overflowing even for UINT64_MAX timestamps. */
	if (sec > INT_MAX / 1000) return INT_MAX;
	int64_t ns = (int64_t)sec * 1000000000 + c->nanoseconds - now->tv_nsec;
	int64_t ms = (ns + 999999) / 1000000;
	return ms > INT_MAX ? INT_MAX : (int)ms;
}

/* A synchronized child's timestamp must also delay its parent's transaction.
 * Read cached states only: uncommitted pending state cannot delay a parent. */
static int children_delay(struct wlr_surface *surface, const struct timespec *now) {
	int delay = 0;
	struct wlr_subsurface *sub;
	struct wl_list *lists[] = {&surface->pending.subsurfaces_below, &surface->pending.subsurfaces_above};
	for (size_t i = 0; i < 2; i++) {
		wl_list_for_each(sub, lists[i], pending.link) {
			if (!synchronized(sub->surface)) continue;
			struct wlr_surface_state *s;
			wl_list_for_each(s, &sub->surface->cached, cached_state_link) {
				int d = timestamp_delay(&s->minerva, now);
				if (d > delay) delay = d;
			}
			int d = children_delay(sub->surface, now);
			if (d > delay) delay = d;
		}
	}
	return delay;
}

bool wlr_minerva_timing_ready(struct wlr_surface *surface, struct wlr_surface_state *state) {
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	int delay = timestamp_delay(&state->minerva, &now);
	int child_delay = children_delay(surface, &now);
	if (child_delay > delay) delay = child_delay;
	bool barrier = state->minerva.wait_barrier && surface->minerva.barrier &&
		!synchronized(surface) && visible(surface);
	if (!delay && !barrier) return true;
	/* Recheck visibility as outputs can disappear without a frame callback. */
	arm(surface, barrier && (!delay || delay > 100) ? 100 : delay);
	if (barrier) {
		struct wlr_surface_output *out;
		wl_list_for_each(out, &surface->current_outputs, link) {
			if (!out->suspended && out->output->enabled) wlr_output_schedule_frame(out->output);
		}
	}
	return false;
}

void wlr_minerva_timing_latched(struct wlr_surface *surface) {
	if (!surface->minerva.barrier) return;
	surface->minerva.barrier = false;
	/* Defer draining: applying a commit here can mutate the scene iterator. */
	if (!wl_list_empty(&surface->cached)) arm(surface, 1);
}

void wlr_minerva_timing_finish(struct wlr_surface *surface) {
	/* Role and destroy listeners can release cached-state locks. Disable
	 * draining before invoking them: teardown must never apply a commit or
	 * leave a timer pointing at the surface after it has been freed. */
	surface->minerva.destroying = true;
	if (surface->minerva.timer) {
		wl_event_source_remove(surface->minerva.timer);
		surface->minerva.timer = NULL;
	}
	if (surface->minerva.fifo) wl_resource_set_user_data(surface->minerva.fifo, NULL);
	if (surface->minerva.timing) wl_resource_set_user_data(surface->minerva.timing, NULL);
}

static void destroy_object(struct wl_client *client, struct wl_resource *resource) {
	wl_resource_destroy(resource);
}

static void fifo_destroy(struct wl_resource *resource) {
	struct wlr_surface *s = wl_resource_get_user_data(resource);
	if (s) s->minerva.fifo = NULL;
}
static void timing_destroy(struct wl_resource *resource) {
	struct wlr_surface *s = wl_resource_get_user_data(resource);
	if (s) s->minerva.timing = NULL;
}
static void set_barrier(struct wl_client *client, struct wl_resource *resource) {
	struct wlr_surface *s = wl_resource_get_user_data(resource);
	if (!s) { wl_resource_post_error(resource, WP_FIFO_V1_ERROR_SURFACE_DESTROYED, "surface destroyed"); return; }
	s->pending.minerva.set_barrier = true;
}
static void wait_barrier(struct wl_client *client, struct wl_resource *resource) {
	struct wlr_surface *s = wl_resource_get_user_data(resource);
	if (!s) { wl_resource_post_error(resource, WP_FIFO_V1_ERROR_SURFACE_DESTROYED, "surface destroyed"); return; }
	s->pending.minerva.wait_barrier = true;
}
static void timestamp(struct wl_client *client, struct wl_resource *resource,
		uint32_t hi, uint32_t lo, uint32_t ns) {
	struct wlr_surface *s = wl_resource_get_user_data(resource);
	if (!s) { wl_resource_post_error(resource, WP_COMMIT_TIMER_V1_ERROR_SURFACE_DESTROYED, "surface destroyed"); return; }
	if (ns >= 1000000000) { wl_resource_post_error(resource, WP_COMMIT_TIMER_V1_ERROR_INVALID_TIMESTAMP, "invalid nanoseconds"); return; }
	if (s->pending.minerva.has_timestamp) { wl_resource_post_error(resource, WP_COMMIT_TIMER_V1_ERROR_TIMESTAMP_EXISTS, "timestamp already set"); return; }
	s->pending.minerva.has_timestamp = true;
	s->pending.minerva.seconds = ((uint64_t)hi << 32) | lo;
	s->pending.minerva.nanoseconds = ns;
}
static const struct wp_fifo_v1_interface fifo_impl = {
	.destroy = destroy_object, .set_barrier = set_barrier, .wait_barrier = wait_barrier,
};
static const struct wp_commit_timer_v1_interface timing_impl = {
	.destroy = destroy_object, .set_timestamp = timestamp,
};
static void get_fifo(struct wl_client *client, struct wl_resource *resource,
		uint32_t id, struct wl_resource *surface_resource) {
	struct wlr_surface *s = wlr_surface_from_resource(surface_resource);
	if (s->minerva.fifo) { wl_resource_post_error(resource, WP_FIFO_MANAGER_V1_ERROR_ALREADY_EXISTS, "fifo already exists"); return; }
	struct wl_resource *r = wl_resource_create(client, &wp_fifo_v1_interface, 1, id);
	if (!r) { wl_client_post_no_memory(client); return; }
	s->minerva.fifo = r;
	wl_resource_set_implementation(r, &fifo_impl, s, fifo_destroy);
}
static void get_timer(struct wl_client *client, struct wl_resource *resource,
		uint32_t id, struct wl_resource *surface_resource) {
	struct wlr_surface *s = wlr_surface_from_resource(surface_resource);
	if (s->minerva.timing) { wl_resource_post_error(resource, WP_COMMIT_TIMING_MANAGER_V1_ERROR_COMMIT_TIMER_EXISTS, "timer already exists"); return; }
	struct wl_resource *r = wl_resource_create(client, &wp_commit_timer_v1_interface, 1, id);
	if (!r) { wl_client_post_no_memory(client); return; }
	s->minerva.timing = r;
	wl_resource_set_implementation(r, &timing_impl, s, timing_destroy);
}
static const struct wp_fifo_manager_v1_interface fifo_manager_impl = {
	.destroy = destroy_object, .get_fifo = get_fifo,
};
static const struct wp_commit_timing_manager_v1_interface timing_manager_impl = {
	.destroy = destroy_object, .get_timer = get_timer,
};
static void bind_fifo(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *r = wl_resource_create(c, &wp_fifo_manager_v1_interface, version, id);
	if (r) wl_resource_set_implementation(r, &fifo_manager_impl, NULL, NULL);
	else wl_client_post_no_memory(c);
}
static void bind_timing(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
	struct wl_resource *r = wl_resource_create(c, &wp_commit_timing_manager_v1_interface, version, id);
	if (r) wl_resource_set_implementation(r, &timing_manager_impl, NULL, NULL);
	else wl_client_post_no_memory(c);
}
static void globals_destroy(struct wl_listener *l, void *data) {
	struct timing_globals *g = wl_container_of(l, g, destroy);
	wl_list_remove(&g->destroy.link);
	wl_global_destroy(g->fifo); wl_global_destroy(g->timing); free(g);
}
bool wlr_minerva_timing_create(struct wl_display *display) {
	struct timing_globals *g = calloc(1, sizeof(*g));
	if (!g) return false;
	g->fifo = wl_global_create(display, &wp_fifo_manager_v1_interface, 1, NULL, bind_fifo);
	g->timing = wl_global_create(display, &wp_commit_timing_manager_v1_interface, 1, NULL, bind_timing);
	if (!g->fifo || !g->timing) {
		if (g->fifo) wl_global_destroy(g->fifo);
		if (g->timing) wl_global_destroy(g->timing);
		free(g); return false;
	}
	g->destroy.notify = globals_destroy;
	wl_display_add_destroy_listener(display, &g->destroy);
	return true;
}
