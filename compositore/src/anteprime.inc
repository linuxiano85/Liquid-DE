// On-demand, bounded window snapshots. No frame callbacks are sent to hidden
// clients, no output or focus is changed. Runtime files live in a private dir.
#include <cairo.h>
#include <pthread.h>
#include <sys/eventfd.h>
#include <wlr/util/transform.h>
#include <drm_fourcc.h>
#include <wlr/render/drm_format_set.h>
#include <wlr/render/pass.h>
#include <wlr/render/wlr_texture.h>

#define ANTEPRIME_MAX 64
static struct {
    uintptr_t window;
    uint64_t birth, signature, stamp;
    char path[512],previous[512];
} anteprime[ANTEPRIME_MAX];
static char anteprime_dir[400];
static uint64_t anteprime_ultima;
static uint64_t anteprime_generation;
static uint64_t anteprime_capture_max_us,anteprime_capture_count,anteprime_warm_ticks;
static bool anteprime_enabled;
static struct wl_event_source *anteprime_timer;
static bool anteprime_timer_armed;
static uint64_t anteprime_timer_due;
static void anteprima_pianifica(struct minerva *m);

static uint64_t anteprima_now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC,&ts);
    return (uint64_t)ts.tv_sec*1000+ts.tv_nsec/1000000;
}

static void anteprima_dimentica(struct finestra *f) {
    for(int i=0;i<ANTEPRIME_MAX;i++) if(anteprime[i].window==(uintptr_t)f) {
        if(anteprime[i].path[0]) unlink(anteprime[i].path);
        if(anteprime[i].previous[0]) unlink(anteprime[i].previous);
        memset(&anteprime[i],0,sizeof(anteprime[i]));
    }
}
static void anteprime_pulisci(void) {
    anteprime_generation++;
    for(int i=0;i<ANTEPRIME_MAX;i++) {
        if(anteprime[i].path[0]) unlink(anteprime[i].path);
        if(anteprime[i].previous[0]) unlink(anteprime[i].previous);
        memset(&anteprime[i],0,sizeof(anteprime[i]));
    }
    if(anteprime_dir[0]) rmdir(anteprime_dir);
    anteprime_dir[0]=0;
}
// Only CPU pixels and filenames cross the worker boundary. All wlroots,
// buffer, surface and scene access stays on the compositor thread.
struct anteprima_job {
    uintptr_t window;
    uint64_t birth, signature, stamp, generation;
    int width,height;
    unsigned char *pixels;
    char path[512],tmp[512];
    bool ok;
};
static pthread_mutex_t anteprime_mutex=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t anteprime_cond=PTHREAD_COND_INITIALIZER;
static pthread_t anteprime_worker;
static bool anteprime_worker_started,anteprime_stop,anteprime_working;
static struct anteprima_job *anteprime_work,*anteprime_done;
static int anteprime_fd=-1;
static struct wl_event_source *anteprime_source;
static void *anteprima_encode(void *unused) {
    (void)unused;
    for(;;) {
        pthread_mutex_lock(&anteprime_mutex);
        while(!anteprime_work && !anteprime_stop) pthread_cond_wait(&anteprime_cond,&anteprime_mutex);
        if(anteprime_stop && !anteprime_work) {pthread_mutex_unlock(&anteprime_mutex);break;}
        struct anteprima_job *job=anteprime_work;anteprime_work=NULL;
        pthread_mutex_unlock(&anteprime_mutex);
        cairo_surface_t *cs=cairo_image_surface_create_for_data(job->pixels,CAIRO_FORMAT_ARGB32,
            job->width,job->height,job->width*4);
        job->ok=cairo_surface_write_to_png(cs,job->tmp)==CAIRO_STATUS_SUCCESS;
        cairo_surface_destroy(cs);
        if(job->ok) job->ok=rename(job->tmp,job->path)==0;
        if(!job->ok) unlink(job->tmp);
        free(job->pixels);job->pixels=NULL;
        pthread_mutex_lock(&anteprime_mutex);anteprime_done=job;pthread_mutex_unlock(&anteprime_mutex);
        uint64_t one=1;ssize_t written=write(anteprime_fd,&one,sizeof(one));(void)written;
    }
    return NULL;
}
static void anteprima_payload(int slot,char *reply,size_t len) {
    char escaped[sizeof(anteprime[slot].path)*6];json_stringa(escaped,sizeof(escaped),anteprime[slot].path);
    snprintf(reply,len,"ok {\"id\":\"0x%llx\",\"birth\":%llu,\"path\":\"%s\",\"stamp\":%llu}",
        (unsigned long long)anteprime[slot].window,(unsigned long long)anteprime[slot].birth,escaped,(unsigned long long)anteprime[slot].stamp);
}
// ── Dove mettere una miniatura nuova ──────────────────────────────────────
//
// Prima la voce che la finestra ha già; poi un posto vuoto; solo a cache
// piena si sacrifica la miniatura più vecchia (lo `stamp` più basso).
//
// Prima si andava a rotazione (`anteprime_slot++ % ANTEPRIME_MAX`) anche con
// posti liberi: chiusa una finestra, il suo posto restava vuoto e la
// miniatura nuova andava a coprire quella di una finestra ancora aperta,
// che spariva dalle Stanze finché non veniva rifotografata (11 ottobre 2026).
static int anteprima_posto(uintptr_t window) {
    int vuoto = -1;
    int vecchio = 0;
    for (int i = 0; i < ANTEPRIME_MAX; i++) {
        if (anteprime[i].window == window)
            return i;
        if (anteprime[i].window == 0) {
            if (vuoto < 0)
                vuoto = i;
        } else if (anteprime[i].stamp < anteprime[vecchio].stamp
                   || anteprime[vecchio].window == 0) {
            vecchio = i;
        }
    }
    return vuoto >= 0 ? vuoto : vecchio;
}

static int anteprima_finished(int fd,uint32_t mask,void *data) {
    (void)mask;struct minerva *m=data;uint64_t count;ssize_t got=read(fd,&count,sizeof(count));(void)got;
    pthread_mutex_lock(&anteprime_mutex);
    struct anteprima_job *job=anteprime_done;anteprime_done=NULL;anteprime_working=false;
    pthread_mutex_unlock(&anteprime_mutex);
    if(!job) return 0;
    struct finestra *f,*found=NULL;
    wl_list_for_each(f,&m->finestre_elenco,link)
        if((uintptr_t)f==job->window && f->birth==job->birth && f->mappata_ora) {found=f;break;}
    if(job->ok && found && anteprime_enabled && !m->bloccato && job->generation==anteprime_generation) {
        int slot = anteprima_posto(job->window);
        // At most two versions per slot; preserve the previous ready file
        // while Qt loads its replacement asynchronously.
        if(anteprime[slot].previous[0]) unlink(anteprime[slot].previous);
        // memcpy e non snprintf: sono due campi della stessa voce, e GCC senza
        // LTO non riesce a escludere che si sovrappongano (-Werror=restrict
        // fermava la build). Stessa misura, stringa già terminata.
        _Static_assert(sizeof(anteprime[0].previous)==sizeof(anteprime[0].path),"misure diverse");
        memcpy(anteprime[slot].previous,anteprime[slot].path,sizeof(anteprime[slot].previous));
        snprintf(anteprime[slot].path,sizeof(anteprime[slot].path),"%s",job->path);
        anteprime[slot].window=job->window;anteprime[slot].birth=job->birth;anteprime[slot].signature=job->signature;anteprime[slot].stamp=job->stamp;
        char reply[4096];anteprima_payload(slot,reply,sizeof(reply));
        char event[4120];snprintf(event,sizeof(event),"evento anteprima %s",reply+3);if(m->canale)canale_annuncia(m->canale,"anteprima",event);
    } else {unlink(job->path);char dir[512];snprintf(dir,sizeof(dir),"%s",job->path);char *slash=strrchr(dir,'/');if(slash){*slash=0;rmdir(dir);}}
    free(job);anteprima_pianifica(m);return 0;
}
static bool anteprima_worker_init(struct minerva *m) {
    if(anteprime_worker_started) return true;
    anteprime_fd=eventfd(0,EFD_NONBLOCK|EFD_CLOEXEC);
    if(anteprime_fd<0) return false;
    anteprime_source=wl_event_loop_add_fd(m->loop,anteprime_fd,WL_EVENT_READABLE,anteprima_finished,m);
    if(!anteprime_source || pthread_create(&anteprime_worker,NULL,anteprima_encode,NULL)) {
        if(anteprime_source) wl_event_source_remove(anteprime_source);
        close(anteprime_fd);anteprime_fd=-1;return false;
    }
    anteprime_worker_started=true;return true;
}
static void anteprime_arresta(void) {
    if(!anteprime_worker_started) return;
    pthread_mutex_lock(&anteprime_mutex);anteprime_stop=true;pthread_cond_signal(&anteprime_cond);pthread_mutex_unlock(&anteprime_mutex);
    pthread_join(anteprime_worker,NULL);
    if(anteprime_done) {unlink(anteprime_done->path);free(anteprime_done->pixels);free(anteprime_done);anteprime_done=NULL;}
    wl_event_source_remove(anteprime_source);close(anteprime_fd);anteprime_worker_started=false;
}
struct anteprima_pass {
    struct wlr_render_pass *pass;
    double scale;
    int x,y;
    uint64_t signature;
};
static void anteprima_superficie(struct wlr_surface *s,int x,int y,void *data) {
    struct anteprima_pass *p=data;
    p->signature=(p->signature ^ ((uint64_t)s->current.seq + (uintptr_t)s)) * 1099511628211ULL;
    if(!p->pass) return;
    struct wlr_texture *t=wlr_surface_get_texture(s);
    if(!t) return;
    struct wlr_fbox src;
    wlr_surface_get_buffer_source_box(s,&src);
    struct wlr_box dst={
        (int)round((x-p->x)*p->scale),(int)round((y-p->y)*p->scale),
        (int)round(s->current.width*p->scale),(int)round(s->current.height*p->scale)};
    if(dst.width<=0 || dst.height<=0) return;
    wlr_render_pass_add_texture(p->pass,&(struct wlr_render_texture_options){
        .texture=t,.src_box=src,.dst_box=dst,
        .transform=wlr_output_transform_invert(s->current.transform)});
}
static void comando_anteprima(struct minerva *m,const char *id,char *reply,size_t len) {
    if(m->bloccato) { anteprime_pulisci(); snprintf(reply,len,"no bloccato"); return; }
    if(!anteprime_enabled) {snprintf(reply,len,"no anteprime disattivate");return;}
    struct finestra *f=finestra_da_indirizzo(m,id);
    if(!f) { snprintf(reply,len,"no finestra assente"); return; }
    if(f->razza==FINESTRA_XDG && (f->toplevel->base->configure_idle || !wl_list_empty(&f->toplevel->base->configure_list))) {snprintf(reply,len,"no geometria in transizione");return;}
    struct wlr_surface *surface=finestra_superficie(f);
    if(!surface || !wlr_surface_get_texture(surface)) { snprintf(reply,len,"no buffer assente"); return; }
    uint64_t now=anteprima_now();
    int slot=-1;
    for(int i=0;i<ANTEPRIME_MAX;i++) if(anteprime[i].window==(uintptr_t)f) {slot=i;break;}
    // XWayland may repaint only exposed regions after an output resize.
    // Hidden X11 buffers are not a complete replacement for the last photo.
    if(f->razza==FINESTRA_X11 && !finestra_visibile(f)) {
        f->preview_dirty=false;
        if(slot>=0) goto answer;
        snprintf(reply,len,"no contenuto non visibile");return;
    }
    struct anteprima_pass p={.signature=1469598103934665603ULL};
    wlr_surface_for_each_surface(surface,anteprima_superficie,&p);
    if(slot>=0 && (p.signature==anteprime[slot].signature || now-anteprime[slot].stamp<2000)) goto answer;
    if(now-anteprime_ultima<80) {
        if(slot>=0) goto answer;
        snprintf(reply,len,"no riprova"); return;
    }
    if(!anteprima_worker_init(m) || anteprime_working) {if(slot>=0) goto answer;snprintf(reply,len,"no in preparazione");return;}
    struct timespec capture_start;clock_gettime(CLOCK_MONOTONIC,&capture_start);
    int w,h; finestra_geometria(f,&w,&h);
    if(w<=0 || h<=0) { snprintf(reply,len,"no geometria"); return; }
    if(m->traccia_finestre && f->razza==FINESTRA_X11)
        wlr_log(WLR_INFO,"MINERVA-WINDOW fotografia X11 %u geometria=%dx%d superficie=%dx%d seq=%u",
            f->xsup->window_id,w,h,surface->current.width,surface->current.height,surface->current.seq);
    if(f->razza==FINESTRA_X11 && (w!=surface->current.width || h!=surface->current.height)) {
        f->preview_dirty=false;
        if(slot>=0) goto answer;
        snprintf(reply,len,"no geometria in transizione");return;
    }
    p.scale=fmin(1.0,fmin(480.0/w,270.0/h));
    if(f->razza==FINESTRA_XDG) {
        p.x=f->toplevel->base->geometry.x; p.y=f->toplevel->base->geometry.y;
    }
    int tw=fmax(1,round(w*p.scale)),th=fmax(1,round(h*p.scale));
    uint64_t modifier=DRM_FORMAT_MOD_LINEAR;
    struct wlr_drm_format fmt={.format=DRM_FORMAT_ARGB8888,.len=1,.capacity=1,.modifiers=&modifier};
    struct wlr_buffer *buffer=wlr_allocator_create_buffer(m->allocator,tw,th,&fmt);
    if(!buffer) { snprintf(reply,len,"no allocazione"); return; }
    p.pass=wlr_renderer_begin_buffer_pass(m->renderer,buffer,NULL);
    bool ok=false;
    if(p.pass) {
        wlr_render_pass_add_rect(p.pass,&(struct wlr_render_rect_options){
            .box={0,0,tw,th},.color={0,0,0,0},.blend_mode=WLR_RENDER_BLEND_MODE_NONE});
        wlr_surface_for_each_surface(surface,anteprima_superficie,&p);
        ok=wlr_render_pass_submit(p.pass);
    }
    struct wlr_texture *texture=ok ? wlr_texture_from_buffer(m->renderer,buffer):NULL;
    unsigned char *pixels=calloc((size_t)tw*th,4);
    ok=texture && pixels && wlr_texture_read_pixels(texture,&(struct wlr_texture_read_pixels_options){
        .data=pixels,.format=DRM_FORMAT_ARGB8888,.stride=(uint32_t)tw*4});
    struct timespec capture_end;clock_gettime(CLOCK_MONOTONIC,&capture_end);
    uint64_t elapsed=(uint64_t)((capture_end.tv_sec-capture_start.tv_sec)*1000000+(capture_end.tv_nsec-capture_start.tv_nsec)/1000);
    if(elapsed>anteprime_capture_max_us)anteprime_capture_max_us=elapsed;
    anteprime_capture_count++;
    if(texture) wlr_texture_destroy(texture);
    wlr_buffer_drop(buffer);
    if(ok && !anteprime_dir[0]) {
        const char *runtime=getenv("XDG_RUNTIME_DIR");
        if(!runtime || snprintf(anteprime_dir,sizeof(anteprime_dir),"%s/minerva-anteprime-XXXXXX",runtime)>=(int)sizeof(anteprime_dir)
                || !mkdtemp(anteprime_dir)) {anteprime_dir[0]=0;ok=false;}
    }
    if(ok) {
        struct anteprima_job *job=calloc(1,sizeof(*job));
        if(job) {
            *job=(struct anteprima_job){.window=(uintptr_t)f,.birth=f->birth,.signature=p.signature,
                .stamp=now,.generation=anteprime_generation,.width=tw,.height=th,.pixels=pixels};
            // p.signature was traversed twice. Recompute exactly once.
            p.signature=1469598103934665603ULL;p.pass=NULL;
            wlr_surface_for_each_surface(surface,anteprima_superficie,&p);job->signature=p.signature;
            snprintf(job->path,sizeof(job->path),"%s/%llu-%llu.png",anteprime_dir,
                (unsigned long long)f->birth,(unsigned long long)now);
            snprintf(job->tmp,sizeof(job->tmp),"%s/%llu-%llu.tmp",anteprime_dir,
                (unsigned long long)f->birth,(unsigned long long)now);
            pthread_mutex_lock(&anteprime_mutex);anteprime_working=true;anteprime_work=job;
            pthread_cond_signal(&anteprime_cond);pthread_mutex_unlock(&anteprime_mutex);
            pixels=NULL;anteprime_ultima=now;
        } else ok=false;
    }
    free(pixels);
    if(!ok) {snprintf(reply,len,"no cattura");return;}
    if(slot<0) {snprintf(reply,len,"no in preparazione");return;}

answer:
    ;
    anteprima_payload(slot,reply,len);
}

// A throttled window has a known deadline. Commits only bring that deadline
// forward for newly mapped/uncached windows; they never restart its delay.
// PNG completion wakes pending work instead of polling the worker thread.
static void anteprima_pianifica(struct minerva *m) {
    if(!anteprime_timer) return;
    uint64_t now=anteprima_now(),due=UINT64_MAX;
    if(anteprime_enabled && !m->bloccato && !anteprime_working) {
        struct finestra *f;
        wl_list_for_each(f,&m->finestre_elenco,link) {
            if(!f->preview_dirty || !f->mappata_ora) continue;
            uint64_t next=now+120;
            for(int i=0;i<ANTEPRIME_MAX;i++)
                if(anteprime[i].window==(uintptr_t)f && anteprime[i].birth==f->birth) {
                    next=anteprime[i].stamp+2000;break;
                }
            if(next<now+1) next=now+1;
            if(next<anteprime_ultima+80) next=anteprime_ultima+80;
            if(next<due) due=next;
        }
    }
    if(due==UINT64_MAX) {
        if(anteprime_timer_armed) wl_event_source_timer_update(anteprime_timer,0);
        anteprime_timer_armed=false;anteprime_timer_due=0;return;
    }
    if(!anteprime_timer_armed || due<anteprime_timer_due) {
        anteprime_timer_armed=true;anteprime_timer_due=due;
        wl_event_source_timer_update(anteprime_timer,(int)(due-now));
    }
}

static int anteprima_tick(void *data) {
    struct minerva *m=data;anteprime_timer_armed=false;if(!anteprime_enabled || m->bloccato) return 0;
    anteprime_warm_ticks++;
    struct finestra *f;
    wl_list_for_each(f,&m->finestre_elenco,link) {
        if(!f->preview_dirty || !f->mappata_ora) continue;
        char id[40],reply[4096];snprintf(id,sizeof(id),"0x%llx",(unsigned long long)(uintptr_t)f);
        uint64_t before=anteprime_ultima;comando_anteprima(m,id,reply,sizeof(reply));
        if(anteprime_ultima!=before) {f->preview_dirty=false;break;}
        // A pending configure cannot resolve without a client commit.
        // That commit will mark the window dirty again; polling a frozen
        // or hidden client otherwise keeps an idle desktop awake forever.
        if(!strcmp(reply,"no buffer assente") || !strcmp(reply,"no geometria in transizione"))
            f->preview_dirty=false;
        if(!strncmp(reply,"ok ",3)) {
            // An unchanged signature needs no work. Changed/throttled content
            // remains dirty and is retried without waking the application.
            struct anteprima_pass p={.signature=1469598103934665603ULL};
            struct wlr_surface *surface=finestra_superficie(f);
            if(surface) wlr_surface_for_each_surface(surface,anteprima_superficie,&p);
            for(int i=0;i<ANTEPRIME_MAX;i++) if(anteprime[i].window==(uintptr_t)f && anteprime[i].signature==p.signature) f->preview_dirty=false;
        }
    }
    anteprima_pianifica(m);
    return 0;
}
static void anteprima_segnala(struct finestra *f) {
    f->preview_dirty=true;
    anteprima_pianifica(f->m);
}
static void anteprime_enable(struct minerva *m,bool enabled) {
    anteprime_enabled=enabled;
    if(!anteprime_timer) anteprime_timer=wl_event_loop_add_timer(m->loop,anteprima_tick,m);
    if(enabled && anteprime_timer) {
        struct finestra *f;wl_list_for_each(f,&m->finestre_elenco,link) f->preview_dirty=true;
    } else {anteprime_pulisci();}
    anteprima_pianifica(m);
}
