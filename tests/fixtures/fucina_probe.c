#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static double now(void) {
    struct timespec t; if (clock_gettime(CLOCK_MONOTONIC, &t)) abort();
    return t.tv_sec + t.tv_nsec / 1e9;
}
static void check(int v) { if (!v) { perror("probe"); exit(1); } }
static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static int turn;
static const int rounds = 20000;
static void *peer(void *unused) {
    (void)unused;
    for (int i=0;i<rounds;i++) {
        check(!pthread_mutex_lock(&mutex));
        while (turn != 1) check(!pthread_cond_wait(&cond,&mutex));
        turn=0; check(!pthread_cond_signal(&cond)); check(!pthread_mutex_unlock(&mutex));
    }
    return NULL;
}
int main(int argc,char **argv) {
    check(argc==3); double t=now(); const char *mode=argv[1];
    if (!strcmp(mode,"syscall")) {
        volatile long sum=0; for (int i=0;i<1000000;i++) sum+=syscall(SYS_getppid);
        check(sum>0);
    } else if (!strcmp(mode,"pipe")) {
        int a[2],b[2]; check(!pipe(a) && !pipe(b)); pid_t pid=fork(); check(pid>=0);
        char c='x';
        if (!pid) {
            close(a[1]);close(b[0]);
            for(int i=0;i<rounds;i++) { check(read(a[0],&c,1)==1); check(write(b[1],&c,1)==1); }
            _exit(0);
        }
        close(a[0]);close(b[1]);
        for(int i=0;i<rounds;i++) { check(write(a[1],&c,1)==1);check(read(b[0],&c,1)==1);check(c=='x'); }
        close(a[1]); close(b[0]); int status;check(waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
    } else if (!strcmp(mode,"futex")) {
        pthread_t thread; check(!pthread_create(&thread,NULL,peer,NULL));
        for(int i=0;i<rounds;i++) {
            check(!pthread_mutex_lock(&mutex));
            while(turn != 0) check(!pthread_cond_wait(&cond,&mutex));
            turn=1;check(!pthread_cond_signal(&cond));check(!pthread_mutex_unlock(&mutex));
        }
        check(!pthread_join(thread,NULL));
    } else if (!strcmp(mode,"memory")) {
        const size_t count=128*1024*1024/sizeof(uint64_t);
        uint64_t *p=mmap(NULL,count*sizeof(*p),PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
        check(p!=MAP_FAILED);
        for (int n=0;n<8;n++) {
            for(size_t i=0;i<count;i++) p[i]=(uint64_t)i*0x9e3779b97f4a7c15ULL ^ (uint64_t)n;
            for(size_t i=0;i<count;i++) check(p[i]==((uint64_t)i*0x9e3779b97f4a7c15ULL ^ (uint64_t)n));
        }
        check(!munmap(p,count*sizeof(*p)));
    } else if (!strcmp(mode,"fsync")) {
        char name[4096];check(snprintf(name,sizeof(name),"%s/probe-file",argv[2])<(int)sizeof(name));
        char buf[4096],out[4096];memset(buf,0x5a,sizeof(buf));
        int fd=open(name,O_CREAT|O_EXCL|O_RDWR|O_CLOEXEC,0600);check(fd>=0);
        for(int i=0;i<64;i++) {check(pwrite(fd,buf,sizeof(buf),0)==sizeof(buf));check(!fdatasync(fd));check(pread(fd,out,sizeof(out),0)==sizeof(out));check(!memcmp(buf,out,sizeof(buf)));}
        check(!close(fd));check(!unlink(name));
    } else return 2;
    printf("%.9f\n",now()-t);return 0;
}
