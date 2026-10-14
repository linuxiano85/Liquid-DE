#include "colonne.h"
#include <stdlib.h>
static int confronto(const void *a,const void *b) {
    const struct colonna_finestra *x=a,*y=b;
    if(x->colonna!=y->colonna) return x->colonna<y->colonna ? -1:1;
    return (x->riga>y->riga)-(x->riga<y->riga);
}
int colonne_adatta(struct colonna_finestra *v,size_t n,int w,int h,int gap) {
    if(!n) return -1;
    qsort(v,n,sizeof(*v),confronto);
    struct span {size_t begin,end;int width,min,max;bool fixed;};
    struct span *cols=calloc(n,sizeof(*cols));
    if(!cols) return (int)n-1;
    size_t count=0;int minsum=0,fixedsum=0,automatic=0;
    for(size_t i=0;i<n;) {
        size_t end=i+1;while(end<n && v[end].colonna==v[i].colonna) end++;
        struct span c={.begin=i,.end=end,.width=v[i].larghezza,.min=80};
        int height=(int)(end-i+1)*gap;
        for(size_t j=i;j<end;j++) {
            if(v[j].minima_larghezza>c.min) c.min=v[j].minima_larghezza;
            if(v[j].massima_larghezza>0 && (!c.max || v[j].massima_larghezza<c.max)) c.max=v[j].massima_larghezza;
            if(v[j].fissa) {c.fixed=true;c.width=v[j].larghezza;}
            height+=v[j].minima_altezza;
        }
        if((c.max && c.max<c.min) || height>h) {
            size_t excluded=i;
            for(size_t j=i+1;j<end;j++)
                if(height>h ? v[j].minima_altezza>v[excluded].minima_altezza:
                        v[j].minima_larghezza>v[excluded].minima_larghezza) excluded=j;
            free(cols);return (int)excluded;
        }
        cols[count++]=c;minsum+=c.min;
        if(c.fixed) fixedsum+=c.width; else automatic++;
        i=end;
    }
    int room=w-(int)(count+1)*gap;
    if(minsum>room) {
        size_t excluded=0;
        for(size_t i=1;i<n;i++)
            if(v[i].minima_larghezza>v[excluded].minima_larghezza) excluded=i;
        free(cols);return (int)excluded;
    }
    int used=0;
    for(size_t i=0;i<count;i++) {
        struct span *c=&cols[i];
        if(!c->fixed && automatic) c->width=(room-fixedsum)/automatic;
        if(c->max && c->width>c->max) c->width=c->max;
        if(c->width<c->min) c->width=c->min;
        used+=c->width;
    }
    // First adjust automatic columns; fixed sizes are preferences, not a way
    // to push other windows outside the usable output.
    for(int phase=0;phase<2 && used!=room;phase++) {
        bool progress=true;
        while(used!=room && progress) {
            progress=false;
            for(size_t i=0;i<count && used!=room;i++) {
                struct span *c=&cols[i];
                if(!phase && c->fixed) continue;
                int delta=used<room ? 1:-1;
                if(delta<0 && c->width<=c->min) continue;
                if(delta>0 && c->max && c->width>=c->max) continue;
                c->width+=delta;used+=delta;progress=true;
            }
        }
    }
    for(size_t i=0;i<count;i++) for(size_t j=cols[i].begin;j<cols[i].end;j++) v[j].larghezza=cols[i].width;
    free(cols);return -1;
}
// Expand the logical canvas rather than evicting regular applications.
int colonne_adatta_scorribile(struct colonna_finestra *v,size_t n,int w,int h,int gap,int *canvas_h) {
    if(!n) { *canvas_h=h; return -1; }
    qsort(v,n,sizeof(*v),confronto);
    int total=gap, tallest=h;
    for(size_t i=0;i<n;) {
        size_t end=i+1;while(end<n && v[end].colonna==v[i].colonna) end++;
        int width=80,height=gap;
        for(size_t j=i;j<end;j++) {
            if(v[j].minima_larghezza>width) width=v[j].minima_larghezza;
            height+=(v[j].cella_altezza>v[j].minima_altezza ? v[j].cella_altezza:v[j].minima_altezza)+gap;
        }
        total+=width+gap;
        if(height>tallest) tallest=height;
        i=end;
    }
    // A narrow capped client may share a column with a wider client. The
    // column reserves the maximum minimum; each client keeps its own cap.
    int *caps=calloc(n,sizeof(*caps));
    if(!caps) return (int)n-1;
    for(size_t i=0;i<n;i++) {caps[i]=v[i].massima_larghezza;v[i].massima_larghezza=0;}
    int result=colonne_adatta(v,n,total>w ? total:w,tallest,gap);
    for(size_t i=0;i<n;i++) v[i].massima_larghezza=caps[i];
    free(caps);*canvas_h=tallest;return result;
}
int colonne_disponi(struct colonna_finestra *v,size_t n,int x,int y,int w,int h,
        int gap,int scroll,void *focus) {
    if(!n || w<=0 || h<=0) return 0;
    qsort(v,n,sizeof(*v),confronto);
    int cursor=gap;
    for(size_t i=0;i<n;) {
        size_t end=i+1; while(end<n && v[end].colonna==v[i].colonna) end++;
        int width=v[i].larghezza>0 ? v[i].larghezza : (w-3*gap)/2;
        int minwidth=80,maxwidth=0;
        for(size_t j=i;j<end;j++) {
            if(v[j].minima_larghezza>minwidth) minwidth=v[j].minima_larghezza;
            if(v[j].massima_larghezza>0 && (!maxwidth || v[j].massima_larghezza<maxwidth)) maxwidth=v[j].massima_larghezza;
        }
        if(maxwidth && width>maxwidth) width=maxwidth;
        if(width<minwidth) width=minwidth;
        if(width<80) width=80;
        int room=h-(int)(end-i+1)*gap,used=0;
        for(size_t j=i;j<end;j++) {
            int height=v[j].altezza>0 ? v[j].altezza:v[j].minima_altezza;
            if(height<v[j].minima_altezza) height=v[j].minima_altezza;
            if(v[j].massima_altezza && height>v[j].massima_altezza) height=v[j].massima_altezza;
            v[j].h=height;used+=height;
        }
        // Preferred sizes yield to the minimum sizes of their neighbors.
        while(used>room) {
            int eligible=0;
            for(size_t j=i;j<end;j++) if(v[j].h>v[j].minima_altezza) eligible++;
            if(!eligible) break;
            int share=(used-room+eligible-1)/eligible;
            for(size_t j=i;j<end && used>room;j++) {
                int amount=v[j].h-v[j].minima_altezza;
                if(amount>share) amount=share;
                if(amount>used-room) amount=used-room;
                if(amount>0) {v[j].h-=amount;used-=amount;}
            }
        }
        // Automatic rows take unused space first; capped rows cannot consume it.
        for(int phase=0;phase<2 && used<room;phase++) {
            bool progress=true;
            while(used<room && progress) {
                int eligible=0;
                for(size_t j=i;j<end;j++)
                    if((phase || !v[j].altezza) && (!v[j].massima_altezza || v[j].h<v[j].massima_altezza)) eligible++;
                if(!eligible) break;
                int share=(room-used)/eligible;if(share<1) share=1;
                progress=false;
                for(size_t j=i;j<end && used<room;j++) {
                    if(!phase && v[j].altezza) continue;
                    int amount=share;
                    if(v[j].massima_altezza && amount>v[j].massima_altezza-v[j].h) amount=v[j].massima_altezza-v[j].h;
                    if(amount>room-used) amount=room-used;
                    if(amount>0) {v[j].h+=amount;used+=amount;progress=true;}
                }
            }
        }
        int top=gap;
        for(size_t j=i;j<end;j++) {
            if(v[j].cella_altezza>0 && v[j].h>v[j].cella_altezza) v[j].h=v[j].cella_altezza;
            v[j].x=cursor; v[j].y=top;
            v[j].w=v[j].massima_larghezza>0 && v[j].massima_larghezza<width ? v[j].massima_larghezza:width; top+=(v[j].cella_altezza>0 ? v[j].cella_altezza:v[j].h)+gap;
        }
        cursor+=width+gap; i=end;
    }
    if(scroll>cursor-w) scroll=cursor>w ? cursor-w:0;
    if(scroll<0) scroll=0;
    for(size_t i=0;i<n;i++) if(v[i].finestra==focus) {
        if(v[i].x<scroll+gap) scroll=v[i].x-gap;
        else if(v[i].x+v[i].w>scroll+w-gap) scroll=v[i].x+v[i].w-w+gap;
        if(v[i].w>w-2*gap) scroll=v[i].x-gap;
        break;
    }
    for(size_t i=0;i<n;i++) { v[i].x+=x-scroll; v[i].y+=y; }
    return scroll;
}
