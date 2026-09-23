/* End-to-end requests over a real Wayland connection, no live session/GPU. */
#undef NDEBUG
#include <assert.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <wlr/backend/headless.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_subcompositor.h>
#include <wlr/types/wlr_output.h>
#include <wlr/types/wlr_minerva_timing.h>
#include "fifo-v1-client.h"
#include "commit-timing-v1-client.h"

struct observed {
	struct wlr_surface *surface;
	struct wl_listener commit, destroy;
	atomic_int count;
	atomic_llong last_ns;
	bool unlock_on_destroy;
	uint32_t locked_seq;
};
struct server {
	struct wl_display *display;
	struct wlr_backend *backend;
	struct wlr_output *output;
	struct wl_listener surface;
	struct observed seen[4];
	atomic_int controls;
	int created, control;
};
static long long now_ns(void) {
	struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
	return (long long)t.tv_sec*1000000000+t.tv_nsec;
}
static void committed(struct wl_listener *l, void *data) {
	struct observed *o=wl_container_of(l,o,commit);
	atomic_store(&o->last_ns,now_ns()); atomic_fetch_add(&o->count,1);
}
static void destroyed(struct wl_listener *l, void *data) {
	struct observed *o=wl_container_of(l,o,destroy);
	if (o->unlock_on_destroy) {
		wlr_surface_unlock_cached(o->surface, o->locked_seq);
		// Cleanup listeners may release locks, but must not revive timers.
		assert(o->surface->minerva.timer == NULL);
		assert(atomic_load(&o->count) == 0);
	}
	wl_list_remove(&o->commit.link); wl_list_remove(&o->destroy.link); o->surface=NULL;
}
static void created(struct wl_listener *l, void *data) {
	struct server *s=wl_container_of(l,s,surface); assert(s->created<4);
	struct observed *o=&s->seen[s->created++]; o->surface=data;
	o->commit.notify=committed; o->destroy.notify=destroyed;
	wl_signal_add(&o->surface->events.commit,&o->commit);
	wl_signal_add(&o->surface->events.destroy,&o->destroy);
}
static int control(int fd, uint32_t mask, void *data) {
	struct server *s=data; char c; assert(read(fd,&c,1)==1);
	if(c=='Q') wl_display_terminate(s->display);
	if(c=='V') wlr_surface_send_enter(s->seen[0].surface,s->output);
	if(c=='H') wlr_surface_send_leave(s->seen[0].surface,s->output);
	if(c=='L') wlr_minerva_timing_latched(s->seen[0].surface);
	if(c=='F') {
		struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
		wlr_surface_send_frame_done(s->seen[0].surface,&now);
	}
	if(c=='K') {
		s->seen[2].locked_seq=wlr_surface_lock_pending(s->seen[2].surface);
		s->seen[2].unlock_on_destroy=true;
	}
	atomic_fetch_add(&s->controls,1);
	return 0;
}
static void *serve(void *data) { struct server *s=data; wl_display_run(s->display); return NULL; }
struct client {
	struct wl_compositor *compositor;
	struct wl_subcompositor *subcompositor;
	struct wp_fifo_manager_v1 *fifo;
	struct wp_commit_timing_manager_v1 *timing;
};
static void global(void *data,struct wl_registry *r,uint32_t id,const char *name,uint32_t version) {
	struct client *c=data;
	if(!strcmp(name,"wl_compositor")) c->compositor=wl_registry_bind(r,id,&wl_compositor_interface,4);
	if(!strcmp(name,"wl_subcompositor")) c->subcompositor=wl_registry_bind(r,id,&wl_subcompositor_interface,1);
	if(!strcmp(name,"wp_fifo_manager_v1")) c->fifo=wl_registry_bind(r,id,&wp_fifo_manager_v1_interface,1);
	if(!strcmp(name,"wp_commit_timing_manager_v1")) c->timing=wl_registry_bind(r,id,&wp_commit_timing_manager_v1_interface,1);
}
static void removed(void *data,struct wl_registry *r,uint32_t id) { }
static const struct wl_registry_listener registry_listener={global,removed};
static void stamp(struct wp_commit_timer_v1 *t,long long ns) {
	uint64_t sec=(uint64_t)(ns/1000000000);
	wp_commit_timer_v1_set_timestamp(t,sec>>32,(uint32_t)sec,ns%1000000000);
}
static void pause_ms(int ms) { struct timespec t={ms/1000,(ms%1000)*1000000}; nanosleep(&t,NULL); }
static void wait_count(struct observed *o,int count) {
	for(int i=0;i<200 && atomic_load(&o->count)<count;i++) pause_ms(5);
	assert(atomic_load(&o->count)==count);
}
static void command(struct server *s, int fd, char c) {
	int expected=atomic_load(&s->controls)+1;
	assert(write(fd,&c,1)==1);
	for(int i=0;i<200 && atomic_load(&s->controls)<expected;i++) pause_ms(5);
	assert(atomic_load(&s->controls)==expected);
}
int main(int argc, char **argv) {
	int sockets[2], pipefd[2]; assert(socketpair(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0,sockets)==0); assert(pipe(pipefd)==0);
	struct server s={0}; s.display=wl_display_create(); assert(s.display);
	struct wlr_compositor *compositor=wlr_compositor_create(s.display,4,NULL); assert(compositor);
	assert(wlr_subcompositor_create(s.display)); assert(wlr_minerva_timing_create(s.display));
	s.surface.notify=created; wl_signal_add(&compositor->events.new_surface,&s.surface);
	s.backend=wlr_headless_backend_create(wl_display_get_event_loop(s.display)); assert(s.backend);
	s.output=wlr_headless_add_output(s.backend,320,240); assert(s.output);
	s.output->enabled=true;
	assert(wl_client_create(s.display,sockets[0]));
	struct wl_event_source *ctrl=wl_event_loop_add_fd(wl_display_get_event_loop(s.display),pipefd[0],WL_EVENT_READABLE,control,&s); assert(ctrl);
	pthread_t thread; assert(pthread_create(&thread,NULL,serve,&s)==0);
	struct wl_display *d=wl_display_connect_to_fd(sockets[1]); assert(d);
	struct client c={0}; struct wl_registry *registry=wl_display_get_registry(d);
	wl_registry_add_listener(registry,&registry_listener,&c); assert(wl_display_roundtrip(d)>=0);
	assert(c.compositor && c.fifo && c.timing && c.subcompositor);
	struct wl_surface *surface=wl_compositor_create_surface(c.compositor);
	struct wp_fifo_v1 *fifo=wp_fifo_manager_v1_get_fifo(c.fifo,surface);
	struct wp_commit_timer_v1 *timer=wp_commit_timing_manager_v1_get_timer(c.timing,surface);
	assert(wl_display_roundtrip(d)>=0);
	if (argc == 2) {
		const struct wl_interface *expected = &wp_commit_timer_v1_interface;
		uint32_t code = WP_COMMIT_TIMER_V1_ERROR_INVALID_TIMESTAMP;
		if (!strcmp(argv[1], "invalid-ns")) {
			wp_commit_timer_v1_set_timestamp(timer,0,0,1000000000);
		} else if (!strcmp(argv[1], "duplicate-timestamp")) {
			stamp(timer,now_ns()); stamp(timer,now_ns());
			code = WP_COMMIT_TIMER_V1_ERROR_TIMESTAMP_EXISTS;
		} else if (!strcmp(argv[1], "duplicate-fifo")) {
			struct wp_fifo_v1 *other=wp_fifo_manager_v1_get_fifo(c.fifo,surface);
			wp_fifo_v1_destroy(other);
			expected=&wp_fifo_manager_v1_interface;
			code=WP_FIFO_MANAGER_V1_ERROR_ALREADY_EXISTS;
		} else if (!strcmp(argv[1], "duplicate-timer")) {
			struct wp_commit_timer_v1 *other=wp_commit_timing_manager_v1_get_timer(c.timing,surface);
			wp_commit_timer_v1_destroy(other);
			expected=&wp_commit_timing_manager_v1_interface;
			code=WP_COMMIT_TIMING_MANAGER_V1_ERROR_COMMIT_TIMER_EXISTS;
		} else {
			wl_surface_destroy(surface); surface=NULL;
			if (!strcmp(argv[1], "dead-timer")) {
				stamp(timer,now_ns()); code=WP_COMMIT_TIMER_V1_ERROR_SURFACE_DESTROYED;
			} else {
				assert(!strcmp(argv[1], "dead-fifo-set") || !strcmp(argv[1], "dead-fifo-wait"));
				if (!strcmp(argv[1], "dead-fifo-set")) wp_fifo_v1_set_barrier(fifo);
				else wp_fifo_v1_wait_barrier(fifo);
				expected=&wp_fifo_v1_interface; code=WP_FIFO_V1_ERROR_SURFACE_DESTROYED;
			}
		}
		assert(wl_display_roundtrip(d)<0);
		assert(wl_display_get_error(d)==EPROTO);
		const struct wl_interface *actual=NULL;
		assert(wl_display_get_protocol_error(d,&actual,NULL)==code);
		assert(actual && !strcmp(actual->name,expected->name));
		wp_commit_timer_v1_destroy(timer); wp_fifo_v1_destroy(fifo);
		if (surface) wl_surface_destroy(surface);
		goto finish_client;
	}
	command(&s,pipefd[1],'V');
	wp_fifo_v1_set_barrier(fifo); wl_surface_commit(surface);
	wp_fifo_v1_wait_barrier(fifo); wp_fifo_v1_set_barrier(fifo); wl_surface_commit(surface);
	wp_fifo_v1_wait_barrier(fifo); wl_surface_commit(surface);
	assert(wl_display_roundtrip(d)>=0); assert(atomic_load(&s.seen[0].count)==1);
	// A frame callback can be sent even after a failed output commit.
	command(&s,pipefd[1],'F'); pause_ms(10);
	assert(atomic_load(&s.seen[0].count)==1);
	command(&s,pipefd[1],'L'); wait_count(&s.seen[0],2);
	command(&s,pipefd[1],'L'); wait_count(&s.seen[0],3);
	long long due=now_ns()+80000000;
	stamp(timer,due); wl_surface_commit(surface); wl_surface_commit(surface);
	wp_commit_timer_v1_destroy(timer); // destruction must preserve the queued constraint
	assert(wl_display_roundtrip(d)>=0); assert(atomic_load(&s.seen[0].count)==3);
	wait_count(&s.seen[0],5); assert(atomic_load(&s.seen[0].last_ns)>=due);
	wp_fifo_v1_set_barrier(fifo); wl_surface_commit(surface);
	wp_fifo_v1_wait_barrier(fifo); wl_surface_commit(surface);
	assert(wl_display_roundtrip(d)>=0); assert(atomic_load(&s.seen[0].count)==6);
	command(&s,pipefd[1],'H'); wait_count(&s.seen[0],7);
	// A synchronized child's timestamp delays the parent transaction too.
	struct wl_surface *child=wl_compositor_create_surface(c.compositor);
	struct wl_subsurface *sub=wl_subcompositor_get_subsurface(c.subcompositor,child,surface);
	struct wp_commit_timer_v1 *child_timer=wp_commit_timing_manager_v1_get_timer(c.timing,child);
	due=now_ns()+80000000; stamp(child_timer,due); wl_surface_commit(child); wl_surface_commit(surface);
	assert(wl_display_roundtrip(d)>=0); assert(atomic_load(&s.seen[0].count)==7);
	wait_count(&s.seen[0],8); wait_count(&s.seen[1],1);
	assert(atomic_load(&s.seen[0].last_ns)>=due); assert(atomic_load(&s.seen[1].last_ns)>=due);
	wp_commit_timer_v1_destroy(child_timer); wl_subsurface_destroy(sub); wl_surface_destroy(child);
	// Simulate an acquire-lock owner releasing its lock during destruction.
	struct wl_surface *closing=wl_compositor_create_surface(c.compositor);
	struct wp_commit_timer_v1 *closing_timer=wp_commit_timing_manager_v1_get_timer(c.timing,closing);
	assert(wl_display_roundtrip(d)>=0);
	command(&s,pipefd[1],'K');
	stamp(closing_timer,now_ns()+80000000); wl_surface_commit(closing);
	assert(wl_display_roundtrip(d)>=0);
	wl_surface_destroy(closing);
	assert(wl_display_roundtrip(d)>=0);
	pause_ms(100);
	wp_commit_timer_v1_destroy(closing_timer);
	// Maximum protocol timestamp must neither overflow nor delay other surfaces.
	struct wl_surface *future=wl_compositor_create_surface(c.compositor);
	struct wp_commit_timer_v1 *future_timer=wp_commit_timing_manager_v1_get_timer(c.timing,future);
	wp_commit_timer_v1_set_timestamp(future_timer,UINT32_MAX,UINT32_MAX,999999999);
	wl_surface_commit(future);
	assert(wl_display_roundtrip(d)>=0);
	assert(atomic_load(&s.seen[3].count)==0);
	wl_surface_commit(surface); assert(wl_display_roundtrip(d)>=0);
	wait_count(&s.seen[0],9);
	wl_surface_destroy(future); wp_commit_timer_v1_destroy(future_timer);
	wp_fifo_v1_destroy(fifo); wl_surface_destroy(surface);
	assert(wl_display_roundtrip(d)>=0);
finish_client:
	wp_fifo_manager_v1_destroy(c.fifo); wp_commit_timing_manager_v1_destroy(c.timing);
	wl_subcompositor_destroy(c.subcompositor); wl_compositor_destroy(c.compositor); wl_registry_destroy(registry);
	wl_display_disconnect(d);
	assert(write(pipefd[1],"Q",1)==1); pthread_join(thread,NULL);
	wl_display_destroy_clients(s.display); wl_list_remove(&s.surface.link);
	wl_event_source_remove(ctrl); wlr_backend_destroy(s.backend); wl_display_destroy(s.display);
	close(pipefd[0]); close(pipefd[1]); puts("FIFO, ordering, timestamps, teardown, visibility, synchronized children: OK");
}
