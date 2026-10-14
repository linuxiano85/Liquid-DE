/* SPDX-License-Identifier: GPL-3.0-or-later
 * Opt-in GTK4 default decorations for Minerva. No polling or GTK initialization.
 * Custom application titlebars are content and are deliberately preserved.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gio/gio.h>
#include <gtk/gtk.h>
#include <unistd.h>

static GListModel *(*windows)(void);
static GdkSurface *(*surface_of)(GtkNative *);
static GdkToplevelState (*state_of)(GdkToplevel *);
static gboolean (*decorated)(GtkWindow *);
static void (*set_decorated)(GtkWindow *, gboolean);
static GtkWidget *(*titlebar)(GtkWindow *);
static gboolean trace;
static GQuark observer_key;

typedef struct {
    GtkWindow *window;                 /* owned by the qdata owner */
    GdkSurface *surface;
    gulong state_handler;
    gboolean baseline, applying, hidden;
} Observer;

static void update(Observer *o) {
    const GdkToplevelState tiled = GDK_TOPLEVEL_STATE_TILED |
        GDK_TOPLEVEL_STATE_TOP_TILED | GDK_TOPLEVEL_STATE_RIGHT_TILED |
        GDK_TOPLEVEL_STATE_BOTTOM_TILED | GDK_TOPLEVEL_STATE_LEFT_TILED;
    gboolean hide = o->surface && (state_of((GdkToplevel *)o->surface) & tiled)
        && !titlebar(o->window) && o->baseline;
    gboolean desired = hide ? FALSE : o->baseline;
    gboolean changed = o->hidden != hide;
    o->hidden = hide;
    if (decorated(o->window) != desired) {
        o->applying = TRUE;
        set_decorated(o->window, desired);
        o->applying = FALSE;
    }
    if (trace && changed)
        g_printerr("MINERVA_HEADER gtk window=%p tiled=%d decorated=%d\n",
            (void *)o->window, hide, decorated(o->window));
}

static void state_changed(GObject *surface, GParamSpec *pspec, Observer *o) {
    (void)surface; (void)pspec;
    update(o);
}

static void detach(Observer *o) {
    if (o->surface) {
        g_signal_handler_disconnect(o->surface, o->state_handler);
        g_clear_object(&o->surface);
    }
}

static void unrealized(GtkWindow *window, Observer *o) {
    (void)window;
    detach(o);
}

static void realized(GtkWindow *window, Observer *o) {
    detach(o);
    GdkSurface *surface = surface_of((GtkNative *)window);
    if (!surface || !g_object_class_find_property(G_OBJECT_GET_CLASS(surface), "state"))
        return;
    o->surface = g_object_ref(surface);
    o->state_handler = g_signal_connect(surface, "notify::state", G_CALLBACK(state_changed), o);
    update(o);
}

static void preference_changed(GObject *window, GParamSpec *pspec, Observer *o) {
    (void)window;
    if (o->applying) return;
    if (g_str_equal(pspec->name, "decorated"))
        o->baseline = decorated(o->window);
    update(o);
}

static void observer_free(gpointer data) {
    Observer *o = data;
    detach(o);
    g_free(o);
}

static void observe(GtkWindow *window) {
    if (g_object_get_qdata(G_OBJECT(window), observer_key)) return;
    Observer *o = g_new0(Observer, 1);
    o->window = window;
    o->baseline = decorated(window);
    g_object_set_qdata_full(G_OBJECT(window), observer_key, o, observer_free);
    g_signal_connect(window, "realize", G_CALLBACK(realized), o);
    g_signal_connect(window, "unrealize", G_CALLBACK(unrealized), o);
    g_signal_connect(window, "notify::decorated", G_CALLBACK(preference_changed), o);
    g_signal_connect(window, "notify::titlebar", G_CALLBACK(preference_changed), o);
    /* A window added to the model can already have a native surface. */
    if (surface_of((GtkNative *)window)) realized(window, o);
}

static void items_changed(GListModel *model, guint position, guint removed,
        guint added, gpointer unused) {
    (void)removed; (void)unused;
    for (guint i = position; i < position + added; i++) {
        GObject *window = g_list_model_get_item(model, i);
        if (window) { observe((GtkWindow *)window); g_object_unref(window); }
    }
}

static gboolean start(gpointer unused) {
    (void)unused;
    GListModel *model = windows();
    observer_key = g_quark_from_static_string("minerva-tiled-header-observer");
    g_signal_connect(model, "items-changed", G_CALLBACK(items_changed), NULL);
    items_changed(model, 0, 0, g_list_model_get_n_items(model), NULL);
    return G_SOURCE_REMOVE;
}

__attribute__((constructor)) static void initialize(void) {
    /* The launcher uses an FD so paths with spaces work. Do not leak that
     * preload or descriptor to Shelly's package helpers and child processes. */
    if (!g_strcmp0(g_getenv("MINERVA_TILED_HEADERS_FD"), "9")) {
        const char *preload = g_getenv("LD_PRELOAD");
        static const char own[] = "/proc/self/fd/9";
        const gsize length = sizeof(own) - 1;
        if (preload && g_str_has_prefix(preload, own) &&
                (preload[length] == '\0' || preload[length] == ':')) {
            char *remaining = preload[length] ? g_strdup(preload + length + 1) : NULL;
            if (remaining) g_setenv("LD_PRELOAD", remaining, TRUE);
            else g_unsetenv("LD_PRELOAD");
            g_free(remaining);
            close(9);
        }
        g_unsetenv("MINERVA_TILED_HEADERS_FD");
    }
    if (g_strcmp0(g_getenv("MINERVA_TILED_HEADERS"), "1")) return;
    /* Do not link GTK: Qt, COSMIC, GTK3 and CLI processes remain unaffected. */
#define LOAD(target, symbol) do { *(void **)(&target) = dlsym(RTLD_DEFAULT, symbol); if (!target) return; } while (0)
    LOAD(windows, "gtk_window_get_toplevels");
    LOAD(surface_of, "gtk_native_get_surface");
    LOAD(state_of, "gdk_toplevel_get_state");
    LOAD(decorated, "gtk_window_get_decorated");
    LOAD(set_decorated, "gtk_window_set_decorated");
    LOAD(titlebar, "gtk_window_get_titlebar");
#undef LOAD
    trace = g_getenv("MINERVA_TILED_HEADERS_TRACE") != NULL;
    g_idle_add(start, NULL);
}
