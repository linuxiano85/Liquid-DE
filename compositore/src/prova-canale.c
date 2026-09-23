// Banco white-box: verifica i descrittori realmente accettati dal trasporto.
#include "canale.c"
#include <assert.h>
#include <sys/wait.h>

void minerva_comando(struct minerva *m, const char *riga, char *risposta, size_t n) {
    (void)m; (void)riga;
    snprintf(risposta, n, "ok");
}

int main(int argc, char **argv) {
    if (argc == 3) {
        assert(fcntl(atoi(argv[1]), F_GETFD) == -1 && errno == EBADF);
        assert(fcntl(atoi(argv[2]), F_GETFD) == -1 && errno == EBADF);
        return 0;
    }
    char dir[] = "/tmp/minerva-canale-XXXXXX";
    assert(mkdtemp(dir));
    assert(setenv("XDG_RUNTIME_DIR", dir, 1) == 0);
    struct wl_event_loop *loop = wl_event_loop_create();
    assert(loop);
    struct canale *c = canale_apri(NULL, loop, "test");
    assert(c);
    int client = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    assert(client >= 0);
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", canale_percorso(c));
    assert(connect(client, (struct sockaddr *)&addr, sizeof(addr)) == 0);
    assert(wl_event_loop_dispatch(loop, 0) == 0);
    assert(c->clienti[0].vivo);
    int accepted = c->clienti[0].fd;
    assert(fcntl(accepted, F_GETFD) & FD_CLOEXEC);
    assert(fcntl(accepted, F_GETFL) & O_NONBLOCK);
    assert(fcntl(c->fd, F_GETFD) & FD_CLOEXEC);
    char a[32], b[32];
    snprintf(a, sizeof(a), "%d", accepted);
    snprintf(b, sizeof(b), "%d", c->fd);
    pid_t pid = fork();
    assert(pid >= 0);
    if (!pid) { execl("/proc/self/exe", "prova-canale", a, b, NULL); _exit(127); }
    int status;
    assert(waitpid(pid, &status, 0) == pid);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    assert(write(client, "ping\n", 5) == 5);
    assert(wl_event_loop_dispatch(loop, 0) == 0);
    char reply[16] = {0};
    assert(read(client, reply, sizeof(reply)-1) == 3);
    assert(strcmp(reply, "ok\n") == 0);
    close(client);
    canale_chiudi(c);
    wl_event_loop_destroy(loop);
    assert(rmdir(dir) == 0);
    puts("ok: IPC non bloccante, risposta, CLOEXEC su ascolto e client dopo exec");
    return 0;
}
