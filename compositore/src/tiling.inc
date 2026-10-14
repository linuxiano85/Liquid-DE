// Window policy. The layout arithmetic is isolated in colonne.c.
static void tiling_limits(struct finestra *f,int *w,int *h,int *mw,int *mh) {
    *w=80; *h=60+finestra_barra_alta(f); *mw=*mh=0;
    if(f->razza==FINESTRA_XDG) {
        struct wlr_xdg_toplevel_state *s=&f->toplevel->current;
        if((int)s->min_width>*w) *w=s->min_width;
        if((int)s->min_height+finestra_barra_alta(f)>*h) *h=s->min_height+finestra_barra_alta(f);
        *mw=s->max_width; *mh=s->max_height;
    } else if(f->xsup->size_hints) {
        xcb_size_hints_t *s=f->xsup->size_hints;
        if(s->min_width>*w) *w=s->min_width;
        if(s->min_height+finestra_barra_alta(f)>*h) *h=s->min_height+finestra_barra_alta(f);
        *mw=s->max_width; *mh=s->max_height;
    }
}
static const char *tiling_exclusion(struct finestra *f) {
    if(!f->mappata_ora || !f->albero) return "non-mappata";
    if(finestra_ha_genitore(f)) return "dialogo";
    if(f->tiling_floating) return "flottante-manuale";
    if(f->tiling_blocked) return "limiti-incompatibili";
    for(int i=0;i<f->m->tiling_rule_count;i++)
        if(!strcmp(finestra_classe(f),f->m->tiling_rules[i].app) && !f->m->tiling_rules[i].enabled) return "regola-app";
    int w,h,mw,mh; tiling_limits(f,&w,&h,&mw,&mh);
    if((mw>0 && mw<=w) || (mh>0 && mh<=h-finestra_barra_alta(f))) return "dimensione-fissa";
    return NULL;
}
static bool tiling_eligible(struct finestra *f) {
    return tiling_exclusion(f)==NULL;
}
static void tiling_constraints_changed(struct finestra *f) {
    int next[4]; tiling_limits(f,&next[0],&next[1],&next[2],&next[3]);
    if(!memcmp(next,f->tiling_limits,sizeof(next))) return;
    memcpy(f->tiling_limits,next,sizeof(next));
    if(tiling_su(f->m,f->scrivania) && f->mappata_ora) tiling_queue(f->m);
}
static struct schermo *tiling_screen(struct minerva *m,struct wlr_output *out) {
    struct schermo *s,*first=NULL;
    wl_list_for_each(s,&m->schermi_elenco,link) if(s->out->enabled) {
        if(s->out==out) return s;
        if(!first) first=s;
    }
    return first;
}
static int64_t tiling_insert(struct finestra *f,int64_t at,bool before) {
    int64_t key=at+(before ? -1:1);
    struct finestra *g; bool collision=key==0; // zero means not joined yet
    wl_list_for_each(g,&f->m->finestre_elenco,link)
        if(g!=f && g->scrivania==f->scrivania && g->tiling_output==f->tiling_output && g->tiling_col==key) collision=true;
    if(!collision) return key;
    size_t cap=wl_list_length(&f->m->finestre_elenco),n=0;
    struct finestra **ordered=calloc(cap+1,sizeof(*ordered));
    if(!ordered) return -(int64_t)(++f->m->tiling_serial)*1024;
    wl_list_for_each(g,&f->m->finestre_elenco,link)
        if(g!=f && g->tiling_col && g->scrivania==f->scrivania && g->tiling_output==f->tiling_output)
            ordered[n++]=g;
    for(size_t i=0;i<n;i++) for(size_t j=i+1;j<n;j++)
        if(ordered[j]->tiling_col<ordered[i]->tiling_col) {
            struct finestra *t=ordered[i];ordered[i]=ordered[j];ordered[j]=t;
        }
    size_t target=n;
    for(size_t i=0;i<n;i++) {
        if(ordered[i]->tiling_col==at) target=i;
        ordered[i]->tiling_col=(int64_t)(i+1)*2048;
    }
    key=target<n ? (int64_t)(target+1)*2048+(before ? -1024:1024):(int64_t)(n+1)*2048;
    free(ordered);return key;
}
static void tiling_restore(struct finestra *f) {
    wlr_minerva_node_set_viewport(&f->cornice->node,NULL);
    if(!f->tiling_saved || f->schermo_intero) return;
    f->tiling_saved=false;
    if(f->razza==FINESTRA_XDG) decorazione_applica(f);
    f->ingrandita=f->tiling_classic_max;
    f->agganciata=f->tiling_classic_snap;
    struct wlr_box b=f->tiling_classic;
    struct wlr_box area; finestra_utile(f,&area);
    int minw,minh,maxw,maxh;tiling_limits(f,&minw,&minh,&maxw,&maxh);
    if(b.width<minw) b.width=minw;
    if(b.height<minh) b.height=minh;
    if(maxw>0 && b.width>maxw) b.width=maxw;
    if(maxh>0 && b.height>maxh+finestra_barra_alta(f)) b.height=maxh+finestra_barra_alta(f);
    // Le dimensioni iniziali del client (o del monitor precedente) possono
    // superare lo schermo corrente. Non lasciare comandi fuori dallo schermo
    // al ritorno in Classico, quando i minimi dell'app permettono di rientrare.
    if(area.width>0 && minw<=area.width && b.width>area.width) b.width=area.width;
    if(area.height>0 && minh<=area.height && b.height>area.height) b.height=area.height;
    if(b.x+b.width<area.x+32 || b.x>area.x+area.width-32) b.x=area.x;
    if(b.y<area.y || b.y>area.y+area.height-32) b.y=area.y;
    if(b.width<=area.width) {
        if(b.x<area.x) b.x=area.x;
        if(b.x+b.width>area.x+area.width) b.x=area.x+area.width-b.width;
    } else b.x=area.x;
    if(b.height<=area.height) {
        if(b.y+b.height>area.y+area.height) b.y=area.y+area.height-b.height;
    } else b.y=area.y;
    finestra_posiziona(f,b.x,b.y,b.width,b.height);
    // La barra e la maniglia seguono la finestra: senza, dopo essere usciti
    // dal tiling la barra del titolo resta della misura vecchia e i pulsanti
    // (chiudi, riduci) e il punto di trascinamento finiscono fuori posto, e
    // la finestra non si sposta né si chiude più col mouse (solo Super+Q).
    barra_aggiorna(f);
    if(f->razza==FINESTRA_XDG) wlr_xdg_toplevel_set_tiled(f->toplevel,0);
    finestra_di_ingrandita(f,f->ingrandita);
    annuncia(f->m,"mossa",f);
}
static void tiling_check_position(struct finestra *f) {
    if(!f->tiling_col) return;
    struct finestra *g;bool collision=false;int64_t last=f->tiling_col;
    wl_list_for_each(g,&f->m->finestre_elenco,link) {
        if(g==f || !g->tiling_col || g->scrivania!=f->scrivania || g->tiling_output!=f->tiling_output) continue;
        if(g->tiling_col==f->tiling_col) collision=true;
        if(g->tiling_col>last) last=g->tiling_col;
    }
    if(collision) {
        f->tiling_col=f->m->tiling_manual ? last+2048:-(int64_t)(++f->m->tiling_serial)*1024;
        f->tiling_row=++f->m->tiling_serial;
    }
}
static void tiling_join(struct finestra *f) {
    tiling_check_position(f);
    if(!f->tiling_col) {
        f->tiling_col=-(int64_t)(++f->m->tiling_serial)*1024;
        f->tiling_row=f->m->tiling_serial;
        f->tiling_percent=0;
        for(int i=0;i<f->m->tiling_rule_count;i++) {
            struct tiling_rule *r=&f->m->tiling_rules[i];
            if(strcmp(finestra_classe(f),r->app)) continue;
            f->tiling_percent=r->percent;
            if(r->position>=0) {
                // Find the desired insertion position among existing columns.
                int64_t after=INT64_MIN;
                for(int k=0;k<=r->position;k++) {
                    int64_t next=INT64_MAX; struct finestra *g;
                    wl_list_for_each(g,&f->m->finestre_elenco,link)
                        if(g!=f && g->tiling_col && g->scrivania==f->scrivania && g->tiling_output==f->tiling_output && g->tiling_col>after && g->tiling_col<next) next=g->tiling_col;
                    if(next==INT64_MAX) { after=after==INT64_MIN ? 0:after+1024; break; }
                    if(k==r->position) { after=tiling_insert(f,next,true); break; }
                    after=next;
                }
                f->tiling_col=after;
                if(!f->tiling_col) f->tiling_col=1;
            }
            break;
        }
    }
    if(!f->tiling_saved && !f->schermo_intero) {
        finestra_box(f,&f->tiling_classic);
        // A restore followed immediately by "tile" can precede the client's
        // configure acknowledgement. Preserve the requested classic size.
        if(f->razza==FINESTRA_XDG && (f->toplevel->base->configure_idle ||
                !wl_list_empty(&f->toplevel->base->configure_list)) &&
                f->toplevel->scheduled.width>0 && f->toplevel->scheduled.height>0) {
            f->tiling_classic.width=f->toplevel->scheduled.width;
            f->tiling_classic.height=f->toplevel->scheduled.height+finestra_barra_alta(f);
        }
        f->tiling_classic_max=f->ingrandita; f->tiling_classic_snap=f->agganciata;
        f->tiling_saved=true; f->ingrandita=f->agganciata=false;
        if(f->razza==FINESTRA_XDG) decorazione_applica(f);
        finestra_di_ingrandita(f,false);
        barra_aggiorna(f);
    }
}
// Focus timestamps survive coalesced events, hidden workspaces and layout changes.
static int tiling_recency_compare(const void *a,const void *b) {
    const struct finestra *x=*(struct finestra *const *)a,*y=*(struct finestra *const *)b;
    if(x->tiling_focus_recency!=y->tiling_focus_recency)
        return x->tiling_focus_recency>y->tiling_focus_recency ? -1:1;
    return x->birth>y->birth ? -1:x->birth<y->birth ? 1:0;
}
// Preferred sizes belong to slots, not to the app that occupied them before.
static void tiling_promote(struct finestra *f) {
    struct minerva *m=f->m;
    if(!f->tiling_col || m->tiling_manual || !tiling_eligible(f) || f->ridotta) return;
    size_t cap=wl_list_length(&m->finestre_elenco),n=0;
    struct slot {struct finestra *window;int width,height;};
    struct finestra **v=calloc(cap+1,sizeof(*v));
    struct slot *slots=calloc(cap+1,sizeof(*slots));
    if(!v || !slots) {free(v);free(slots);return;}
    struct finestra *g;
    wl_list_for_each(g,&m->finestre_elenco,link)
        if(g->tiling_col && g->scrivania==f->scrivania && g->tiling_output==f->tiling_output
                && !g->ridotta && tiling_eligible(g)) v[n++]=g;
    for(size_t i=0;i<n;i++) for(size_t j=i+1;j<n;j++)
        if(v[j]->tiling_col<v[i]->tiling_col) {g=v[i];v[i]=v[j];v[j]=g;}
    for(size_t i=0;i<n;i++) slots[i]=(struct slot){v[i],v[i]->tiling_width,v[i]->tiling_height};
    qsort(v,n,sizeof(*v),tiling_recency_compare);
    bool changed=false;
    for(size_t i=0;i<n;i++) if(v[i]!=slots[i].window) changed=true;
    if(changed) for(size_t i=n;i-->0;) {
        v[i]->tiling_width=slots[i].width;v[i]->tiling_height=slots[i].height;
        v[i]->tiling_col=-(int64_t)(++m->tiling_serial)*1024;
    }
    free(slots);free(v);
}
static void tiling_navigation_reset(struct minerva *m) {
    free(m->tiling_navigation);m->tiling_navigation=NULL;m->tiling_navigation_count=0;
}
static int tiling_release_ready(void *data) {
    struct minerva *m=data;
    wl_event_source_remove(m->tiling_focus_release);m->tiling_focus_release=NULL;
    tiling_queue(m);return 0;
}
static void tiling_focus_changed(struct finestra *f) {
    if(!f) return;
    struct minerva *m=f->m;
    if(!m->tiling_navigating) tiling_navigation_reset(m);
    if(!m->tiling_focus_first || m->tiling_manual || !tiling_su(m,f->scrivania)
            || !tiling_eligible(f)) return;
    m->tiling_focus_pending=f;m->tiling_focus_birth=f->birth;
    tiling_queue(m);
}
static void tiling_master_reset(struct minerva *m) {
    struct schermo *s;wl_list_for_each(s,&m->schermi_elenco,link)
        memset(s->tiling_master_width,0,sizeof(s->tiling_master_width));
    struct finestra *f;wl_list_for_each(f,&m->finestre_elenco,link)
        if(tiling_disposizione(m,f->scrivania)==TILING_MAESTRO) f->tiling_width=0;
}
// Logical order remains independent from visual column/row assignment.
// Recompute the whole plan after constraint fallback, before issuing sizes.
static int tiling_grid_columns(struct schermo *s,struct colonna_finestra *v,size_t n,int gap) {
    if(s->utile.width<=0 || s->utile.height<=0) return 1;
    int preferred=n<=4 ? 2:(int)ceil(sqrt((double)n*fmin(1.0,(double)s->utile.width/s->utile.height)));
    if(preferred>(int)n) preferred=(int)n;
    if(preferred<1) preferred=1;
    // Prefer a balanced grid, then try nearby shapes before floating an app.
    // A wide or tall client may fit a different shape on the same monitor.
    int *sizes=calloc(n*3,sizeof(int));
    if(!sizes) return preferred;
    for(int distance=0;distance<(int)n;distance++) for(int side=0;side<2;side++) {
        int cols=preferred+(side ? distance:-distance);
        if(cols<1 || cols>(int)n || (!distance && side)) continue;
        memset(sizes,0,n*3*sizeof(int));
        int *width=sizes,*maximum=sizes+n,*height=sizes+n*2;
        bool valid=true;
        for(size_t i=0;i<n;i++) {
            int c=(int)i%cols,r=(int)i/cols;
            if(v[i].minima_larghezza>width[c]) width[c]=v[i].minima_larghezza;
            if(v[i].massima_larghezza>0 && (!maximum[c] || v[i].massima_larghezza<maximum[c])) maximum[c]=v[i].massima_larghezza;
            if(v[i].minima_altezza>height[r]) height[r]=v[i].minima_altezza;
        }
        int totalw=(cols+1)*gap,rows=((int)n+cols-1)/cols,totalh=(rows+1)*gap;
        for(int c=0;c<cols;c++) {
            totalw+=width[c];
            if(maximum[c] && maximum[c]<width[c]) valid=false;
        }
        for(int r=0;r<rows;r++) totalh+=height[r];
        if(valid && totalw<=s->utile.width && totalh<=s->utile.height) {free(sizes);return cols;}
    }
    free(sizes);return preferred;
}
static void tiling_plan(struct minerva *m,struct schermo *s,
        struct colonna_finestra *v,size_t n,int layout) {
    for(size_t i=0;i<n;i++) {
        struct finestra *f=v[i].finestra;
        int w,h,mw,mh;tiling_limits(f,&w,&h,&mw,&mh);
        v[i]=(struct colonna_finestra){.finestra=f,.colonna=f->tiling_col,.riga=f->tiling_row,
            .altezza=f->tiling_height,.minima_larghezza=w,.minima_altezza=h,.massima_larghezza=mw,
            .massima_altezza=mh>0 ? mh+finestra_barra_alta(f):0};
    }
    // The same stable order is used by all arrangements and swaps.
    for(size_t i=0;i<n;i++) for(size_t j=i+1;j<n;j++)
        if(v[j].colonna<v[i].colonna) {struct colonna_finestra t=v[i];v[i]=v[j];v[j]=t;}
    int master_width=0;
    if(layout==TILING_MAESTRO && n>1) {
        struct finestra *master=v[0].finestra;
        int percent=master->tiling_percent>0 ? master->tiling_percent:m->tiling_percent;
        if(m->tiling_master_adaptive && master->tiling_percent==0)
            percent=n==2 ? 50:n==3 ? 60:65;
        int preferred=s->tiling_master_width[master->scrivania-1];
        master_width=preferred>0 ? preferred:master->tiling_width>0 ? master->tiling_width:
            (s->utile.width-3*m->tiling_gap)*percent/100;
    }
    int grid_cols=layout==TILING_GRIGLIA ? tiling_grid_columns(s,v,n,m->tiling_gap):2;
    int rows=((int)n+grid_cols-1)/grid_cols;
    struct colonna_finestra *grid_rows=NULL;
    if(layout==TILING_GRIGLIA && n>1) {
        grid_rows=calloc((size_t)rows,sizeof(*grid_rows));
        if(grid_rows) {
            for(int r=0;r<rows;r++) grid_rows[r]=(struct colonna_finestra){.riga=(uint64_t)r,.minima_altezza=60,.larghezza=80};
            for(size_t i=0;i<n;i++) {
                struct finestra *f=v[i].finestra;
                int r=(int)i/grid_cols;
                if(v[i].minima_altezza>grid_rows[r].minima_altezza) grid_rows[r].minima_altezza=v[i].minima_altezza;
                if(f->tiling_height>0) grid_rows[r].altezza=f->tiling_height;
            }
            colonne_disponi(grid_rows,(size_t)rows,0,0,80,s->utile.height,m->tiling_gap,0,NULL);
        }
    }
    for(size_t i=0;i<n;i++) {
        struct finestra *f=v[i].finestra;
        int width;
        if(layout==TILING_MAESTRO && n>1) {
            v[i].colonna=i==0 ? 0:1;v[i].riga=i;
            width=i==0 ? master_width:s->utile.width-3*m->tiling_gap-master_width;
            v[i].fissa=i==0;
        } else if(layout==TILING_GRIGLIA && n>1) {
            v[i].colonna=i%(size_t)grid_cols;v[i].riga=i/(size_t)grid_cols;
            width=(s->utile.width-(grid_cols+1)*m->tiling_gap)/grid_cols;
            int cell=grid_rows ? grid_rows[i/(size_t)grid_cols].h:(s->utile.height-(rows+1)*m->tiling_gap)/rows;
            v[i].cella_altezza=cell;v[i].altezza=cell;
            if(!v[i].massima_altezza || v[i].massima_altezza>cell) v[i].massima_altezza=cell;
            
        } else {
            width=(s->utile.width-(int)(n+1)*m->tiling_gap)/(int)n;
        }
        if(f->tiling_width>0 && !(layout==TILING_MAESTRO && (n==1 || s->tiling_master_width[f->scrivania-1]>0))) {
            width=f->tiling_width;v[i].fissa=true;
        }
        else if(f->tiling_percent>0 && !(layout==TILING_MAESTRO && n>1)) {
            width=(s->utile.width-3*m->tiling_gap)*f->tiling_percent/100;v[i].fissa=true;
        }
        v[i].larghezza=width;
    }
    free(grid_rows);
}
static void tiling_reflow(void *data) {
    struct minerva *m=data; m->tiling_idle=NULL;
    // A queued focus/constraint update must never fight an interactive grab.
    // Release and cancellation explicitly queue the final layout.
    if(m->tiling_busy || m->presa!=PRESA_NIENTE) return;
    m->tiling_busy=true;
    struct finestra *f;
    wl_list_for_each(f,&m->finestre_elenco,link) f->tiling_blocked=false;
    wl_list_for_each(f,&m->finestre_elenco,link) {
        if(!tiling_su(m,f->scrivania) || !tiling_eligible(f)) { tiling_restore(f); continue; }
        struct schermo *s=tiling_screen(m,f->tiling_output);
        if(!f->tiling_output) {
            int w,h; finestra_geometria(f,&w,&h);
            struct wlr_output *out=wlr_output_layout_output_at(m->schermi,f->posto_x+w/2,f->posto_y+h/2);
            s=tiling_screen(m,out);
        }
        if(!s) continue;
        f->tiling_output=s->out;
        tiling_join(f);
        if(f->schermo_intero) wlr_minerva_node_set_viewport(&f->cornice->node,NULL);
    }
    if(m->tiling_focus_pending && !m->tiling_focus_release && m->seat->pointer_state.button_count==0 && !m->seat->drag) {
        struct finestra *target=NULL;
        wl_list_for_each(f,&m->finestre_elenco,link)
            if(f==m->tiling_focus_pending && f->birth==m->tiling_focus_birth) {target=f;break;}
        m->tiling_focus_pending=NULL;
        if(target && target==finestra_attiva(m) && m->tiling_focus_first
                && tiling_su(m,target->scrivania)) tiling_promote(target);
    }
    {
        size_t cap=wl_list_length(&m->finestre_elenco);
        struct colonna_finestra *v=calloc(cap+1,sizeof(*v));
        if(!v) { m->tiling_busy=false; return; }
        struct schermo *s;
        wl_list_for_each(s,&m->schermi_elenco,link) if(s->out->enabled) for(int desk=1;desk<=10;desk++) {
            if(!tiling_su(m,desk)) continue;
            int layout=tiling_disposizione(m,desk);
            size_t n=0;
            wl_list_for_each(f,&m->finestre_elenco,link) {
                if(!tiling_eligible(f) || f->tiling_output!=s->out || f->scrivania!=desk || f->ridotta) continue;
                int w,h,mw,mh; tiling_limits(f,&w,&h,&mw,&mh);
                f->tiling_percent=0;
                for(int k=0;k<m->tiling_rule_count;k++)
                    if(!strcmp(finestra_classe(f),m->tiling_rules[k].app)) {f->tiling_percent=m->tiling_rules[k].percent;break;}
                v[n++]=(struct colonna_finestra){.finestra=f,.colonna=f->tiling_col,.riga=f->tiling_row,
                    .larghezza=0,.minima_larghezza=w,.minima_altezza=h,
                    .massima_larghezza=mw,.massima_altezza=mh>0 ? mh+finestra_barra_alta(f):0};
            }
            // Rebuild after every exclusion: stale grid rows or master
            // columns must not force unrelated windows out of the layout.
            while(n) {
                tiling_plan(m,s,v,n,layout);
                int canvas_h=s->utile.height;
                int incompatible=colonne_adatta_scorribile(v,n,s->utile.width,s->utile.height,m->tiling_gap,&canvas_h);
                s->tiling_canvas_h[desk-1]=canvas_h;
                if(incompatible<0) break;
                struct finestra *excluded=v[incompatible].finestra;
                excluded->tiling_blocked=true;tiling_restore(excluded);
                wlr_log(WLR_INFO,"minerva: finestra flottante: limiti incompatibili col tiling");
                memmove(v+incompatible,v+incompatible+1,(n-(size_t)incompatible-1)*sizeof(*v));n--;
            }
            struct finestra *focus=finestra_attiva(m);
            int d=desk-1;
            if(s->tiling_lastfocus[d]!=(uintptr_t)focus) s->tiling_manual_scroll[d]=false;
            s->tiling_lastfocus[d]=(uintptr_t)focus;
            s->tiling_scroll[d]=colonne_disponi(v,n,s->utile.x,s->utile.y,s->utile.width,s->tiling_canvas_h[d],
                m->tiling_gap,s->tiling_scroll[d],s->tiling_manual_scroll[d] ? NULL:focus);
            int extent=s->utile.width;
            for(size_t i=0;i<n;i++) {
                int edge=v[i].x-s->utile.x+s->tiling_scroll[d]+v[i].w+m->tiling_gap;
                if(edge>extent) extent=edge;
            }
            s->tiling_canvas_w[d]=extent;
            int maxy=s->tiling_canvas_h[d]-s->utile.height;
            if(s->tiling_scroll_y[d]>maxy) s->tiling_scroll_y[d]=maxy;
            if(s->tiling_scroll_y[d]<0) s->tiling_scroll_y[d]=0;
            if(!s->tiling_manual_scroll[d]) for(size_t i=0;i<n;i++) if(v[i].finestra==focus) {
                int top=v[i].y-s->utile.y,bottom=top+v[i].h;
                if(top<s->tiling_scroll_y[d]+m->tiling_gap) s->tiling_scroll_y[d]=top-m->tiling_gap;
                else if(bottom>s->tiling_scroll_y[d]+s->utile.height-m->tiling_gap)
                    s->tiling_scroll_y[d]=bottom-s->utile.height+m->tiling_gap;
                if(v[i].h>s->utile.height-2*m->tiling_gap) s->tiling_scroll_y[d]=top-m->tiling_gap;
                break;
            }
            for(size_t i=0;i<n;i++) {
                struct finestra *logical=v[i].finestra;
                logical->tiling_logical=(struct wlr_box){v[i].x-s->utile.x+s->tiling_scroll[d],v[i].y-s->utile.y,v[i].w,v[i].h};
                v[i].y-=s->tiling_scroll_y[d];
            }
            for(size_t i=0;i<n;i++) {
                f=v[i].finestra;
                f->tiling_box=(struct wlr_box){v[i].x,v[i].y,v[i].w,v[i].h};
                if(f->schermo_intero) continue;
                if(f->ingrandita) {
                    v[i].x=s->utile.x; v[i].y=s->utile.y;
                    v[i].w=s->utile.width; v[i].h=s->utile.height;
                    int minw,minh,maxw,maxh;tiling_limits(f,&minw,&minh,&maxw,&maxh);
                    if(maxw>0 && v[i].w>maxw) v[i].w=maxw;
                    if(maxh>0 && v[i].h>maxh+finestra_barra_alta(f)) v[i].h=maxh+finestra_barra_alta(f);
                }
                struct wlr_box old; finestra_box(f,&old);
                if(f->tiling_target_width!=v[i].w || f->tiling_target_height!=v[i].h)
                    f->tiling_rejected_width=f->tiling_rejected_height=0;
                f->tiling_target_width=v[i].w;f->tiling_target_height=v[i].h;
                if(old.x!=v[i].x || old.y!=v[i].y || old.width!=v[i].w || old.height!=v[i].h) {
                    finestra_posiziona(f,v[i].x,v[i].y,v[i].w,v[i].h);
                    annuncia(m,"mossa",f);
                }
                // The output clips overflowing tiles, while the content bounds also
                // contain clients which ignore their last configure.
                struct wlr_box clip={0,0,v[i].w,v[i].h};
                struct wlr_box output_clip={s->utile.x-v[i].x,s->utile.y-v[i].y,s->utile.width,s->utile.height};
                if(!wlr_box_intersection(&clip,&clip,&output_clip)) clip=(struct wlr_box){0,0,0,0};
                wlr_minerva_node_set_viewport(&f->cornice->node,&clip);
                if(f->razza==FINESTRA_XDG) wlr_xdg_toplevel_set_tiled(f->toplevel,
                    WLR_EDGE_TOP|WLR_EDGE_BOTTOM|WLR_EDGE_LEFT|WLR_EDGE_RIGHT);
            }
        }
        free(v);
    }
    m->tiling_busy=false;
}
static void tiling_queue(struct minerva *m) {
    if(!m->tiling_busy && !m->tiling_idle) m->tiling_idle=wl_event_loop_add_idle(m->loop,tiling_reflow,m);
}
static void tiling_recall(struct finestra *f) {
    if(!tiling_su(f->m,f->scrivania) || !tiling_eligible(f)) return;
    if(!f->tiling_col) tiling_join(f);
    // Older IPC clients keep recall-only ordering. The shell explicitly
    // configures the focus policy; disabling it keeps every activation stable.
    if(f->m->tiling_focus_configured) {tiling_focus_changed(f);return;}
    if(!f->m->tiling_manual) {
        int64_t old=f->tiling_col,new=-(int64_t)(++f->m->tiling_serial)*1024;
        struct finestra *g;
        wl_list_for_each(g,&f->m->finestre_elenco,link)
            if(g->tiling_col==old && g->scrivania==f->scrivania && g->tiling_output==f->tiling_output) g->tiling_col=new;
    }
    tiling_queue(f->m);
}
static void tiling_resize(struct finestra *f,int width,int height) {
    struct minerva *m=f->m;
    int layout=tiling_disposizione(m,f->scrivania);
    bool master_role=false;
    if(layout==TILING_MAESTRO) {
        struct schermo *s=tiling_screen(m,f->tiling_output);
        int64_t first=f->tiling_col;
        struct finestra *g;
        wl_list_for_each(g,&m->finestre_elenco,link)
            if(g->tiling_saved && !g->ridotta && g->scrivania==f->scrivania
                    && g->tiling_output==f->tiling_output && g->tiling_col<first) first=g->tiling_col;
        master_role=f->tiling_col==first;
        if(s && width>0) s->tiling_master_width[f->scrivania-1]=master_role ? width:
            s->utile.width-3*m->tiling_gap-width;
    }
    struct finestra *g;
    wl_list_for_each(g,&m->finestre_elenco,link) {
        if(!g->tiling_saved || g->ridotta || g->tiling_output!=f->tiling_output || g->scrivania!=f->scrivania) continue;
        if(width>0) {
            if(g->tiling_box.x==f->tiling_box.x) g->tiling_width=width;
            else if(layout==TILING_MAESTRO) {
                struct schermo *s=tiling_screen(m,f->tiling_output);
                if(s) g->tiling_width=s->utile.width-3*m->tiling_gap-width;
            } else if(layout==TILING_GRIGLIA) g->tiling_width=0;
        }
        if(height>0 && (height!=f->tiling_box.height || master_role)
                && (g==f || (layout==TILING_GRIGLIA && g->tiling_box.y==f->tiling_box.y)))
            // A full-height master has no adjustable row. Its height must
            // not become a giant preferred stack row after another app opens.
            g->tiling_height=layout==TILING_MAESTRO && master_role ? 0:height;
    }
    tiling_queue(m);
}
static void tiling_swap(struct finestra *f,struct finestra *g) {
    int64_t key=f->tiling_col;f->tiling_col=g->tiling_col;g->tiling_col=key;
    uint64_t row=f->tiling_row;f->tiling_row=g->tiling_row;g->tiling_row=row;
    // User sizing belongs to the destination slot, so swapping applications
    // does not alter every column and row in a manually sized layout.
    int width=f->tiling_width;f->tiling_width=g->tiling_width;g->tiling_width=width;
    int height=f->tiling_height;f->tiling_height=g->tiling_height;g->tiling_height=height;
}
static bool tiling_navigation_box(struct minerva *m,struct finestra *f,struct wlr_box *box) {
    for(size_t i=0;i<m->tiling_navigation_count;i++) {
        struct tiling_navigation_item *item=&m->tiling_navigation[i];
        if(item->window==f && item->birth==f->birth) {*box=item->box;return true;}
    }
    return false;
}
static bool tiling_direction(struct minerva *m,const char *dir,bool move) {
    struct finestra *f=finestra_attiva(m),*g,*best=NULL;
    if(!tiling_attivo(m) || !f || !dir || !*dir) return false;
    if(!tiling_eligible(f)) {if(!move) fuoco_in_direzione(m,dir);return true;}
    if(f->schermo_intero && move) return true;
    struct wlr_keyboard *kb=wlr_seat_get_keyboard(m->seat);
    bool chronological=m->tiling_focus_first && !m->tiling_manual;
    bool sequence=chronological && !move && kb && (wlr_keyboard_get_modifiers(kb)&WLR_MODIFIER_LOGO);
    if(!sequence) tiling_navigation_reset(m);
    else if(!m->tiling_navigation) {
        // Preserve spatial traversal while Super is held. Promotion must not
        // strand the keyboard in a ping-pong between the first two windows.
        size_t cap=wl_list_length(&m->finestre_elenco);
        m->tiling_navigation=calloc(cap+1,sizeof(*m->tiling_navigation));
        if(m->tiling_navigation) wl_list_for_each(g,&m->finestre_elenco,link) {
            if(!g->mappata_ora || g->ridotta || g->scrivania!=f->scrivania || g->tiling_output!=f->tiling_output) continue;
            struct wlr_box box;if(g->tiling_saved) box=g->tiling_box;else finestra_box(g,&box);
            m->tiling_navigation[m->tiling_navigation_count++]=(struct tiling_navigation_item){g,g->birth,box};
        }
        if(!m->tiling_navigation) sequence=false;
    }
    // ── Navigazione DIREZIONALE ─────────────────────────────────────────
    //
    // Super+sinistra/destra/su/giù seleziona la finestra che sta DAVVERO in
    // quella direzione, per posizione sullo schermo (come i3): in una griglia
    // 2×2 su/giù attraversa le righe, destra/sinistra le colonne; in
    // «maestro» destra/sinistra passa fra il maestro e la pila. Non c'entra
    // l'ordine di apertura.
    struct wlr_box b=f->tiling_box;
    tiling_navigation_box(m,f,&b);
    int best_punti=INT_MAX;
    int best_cross=INT_MAX;
    wl_list_for_each(g,&m->finestre_elenco,link) {
        if(g==f || !g->mappata_ora || g->ridotta || (move && g->schermo_intero) || g->scrivania!=f->scrivania) continue;
        bool tiled=tiling_eligible(g) && g->tiling_saved;
        if(move && !tiled) continue;
        struct wlr_box q;
        if(tiled) q=g->tiling_box; else finestra_box(g,&q);
        if(sequence && !tiling_navigation_box(m,g,&q)) continue;
        struct wlr_output *output=tiled ? g->tiling_output:wlr_output_layout_output_at(m->schermi,q.x+q.width/2,q.y+q.height/2);
        if(output!=f->tiling_output) continue;
        int punti=INT_MAX;
        switch(dir[0]) {
        case 'l':
            if(q.x+q.width<=b.x) {
                bool allineata=q.y<b.y+b.height && q.y+q.height>b.y;
                punti=allineata ? b.x-(q.x+q.width)
                                : 100000+abs((q.y+q.height/2)-(b.y+b.height/2));
            }
            break;
        case 'r':
            if(q.x>=b.x+b.width) {
                bool allineata=q.y<b.y+b.height && q.y+q.height>b.y;
                punti=allineata ? q.x-(b.x+b.width)
                                : 100000+abs((q.y+q.height/2)-(b.y+b.height/2));
            }
            break;
        case 'u':
            if(q.y+q.height<=b.y) {
                bool allineata=q.x<b.x+b.width && q.x+q.width>b.x;
                punti=allineata ? b.y-(q.y+q.height)
                                : 100000+abs((q.x+q.width/2)-(b.x+b.width/2));
            }
            break;
        case 'd':
            if(q.y>=b.y+b.height) {
                bool allineata=q.x<b.x+b.width && q.x+q.width>b.x;
                punti=allineata ? q.y-(b.y+b.height)
                                : 100000+abs((q.x+q.width/2)-(b.x+b.width/2));
            }
            break;
        default:
            return false;
        }
        if(punti==INT_MAX) continue;
        int cross=(dir[0]=='l' || dir[0]=='r') ? abs((q.y+q.height/2)-(b.y+b.height/2)):
            abs((q.x+q.width/2)-(b.x+b.width/2));
        if(chronological && tiling_disposizione(m,f->scrivania)==TILING_MAESTRO && dir[0]=='r')
            cross=q.y;
        if(punti<best_punti || (punti==best_punti && cross<best_cross) ||
                (punti==best_punti && cross==best_cross && best && g->tiling_col<best->tiling_col)) {
            best_punti=punti;best_cross=cross;best=g;
        }
    }
    if(!best && chronological && !move && tiling_disposizione(m,f->scrivania)==TILING_MAESTRO
            && (dir[0]=='u' || dir[0]=='d')) {
        // Up/down also connects the full-height master to the ordered stack.
        wl_list_for_each(g,&m->finestre_elenco,link) {
            if(g==f || !g->tiling_saved || g->ridotta || !tiling_eligible(g)
                    || g->scrivania!=f->scrivania || g->tiling_output!=f->tiling_output) continue;
            struct wlr_box q=g->tiling_box;
            if(sequence && !tiling_navigation_box(m,g,&q)) continue;
            if((dir[0]=='d' && q.x>b.x) || (dir[0]=='u' && q.x<b.x)) {
                if(!best || q.y<best_punti) {best=g;best_punti=q.y;}
            }
        }
    }
    if(move && best) {
        // Scambia le chiavi di recenza: riordina le due finestre.
        tiling_swap(f,best);
    }
    if(best) {
        if(f->schermo_intero) finestra_schermo_intero(f,false);
        if(f->ingrandita) finestra_ingrandisci(f,false);
        m->tiling_navigating=sequence;
        fuoco_finestra(m,move ? f:best);
        m->tiling_navigating=false;
    }
    tiling_queue(m); return best!=NULL;
}

static void tiling_scroll_manual(struct minerva *m,const char *direction) {
    tiling_navigation_reset(m);
    struct finestra *f=finestra_attiva(m);
    struct schermo *s=tiling_screen(m,f ? f->tiling_output:NULL);
    if(!s || !tiling_attivo(m) || !direction || strlen(direction)!=1 || !strchr("lrud",direction[0])) return;
    int d=m->scrivania_attiva-1;
    if(direction[0]=='l') s->tiling_scroll[d]-=s->utile.width/2;
    if(direction[0]=='r') s->tiling_scroll[d]+=s->utile.width/2;
    if(direction[0]=='u') s->tiling_scroll_y[d]-=s->utile.height/2;
    if(direction[0]=='d') s->tiling_scroll_y[d]+=s->utile.height/2;
    s->tiling_lastfocus[d]=(uintptr_t)f;s->tiling_manual_scroll[d]=true;tiling_queue(m);
}
// Nearest visible slot includes gutters; a drop in a gap no longer appends
// the dragged window to the end. Preview and commit share this function.
static struct finestra *tiling_drop_target(struct minerva *m,struct finestra *f,struct wlr_output *out) {
    struct finestra *g,*best=NULL;double distance=HUGE_VAL;
    wl_list_for_each(g,&m->finestre_elenco,link) {
        if(g==f || !g->tiling_saved || g->ridotta || g->schermo_intero || g->scrivania!=f->scrivania || g->tiling_output!=out) continue;
        struct schermo *s=tiling_screen(m,out);struct wlr_box box=g->tiling_box,visible;
        if(!s || !wlr_box_intersection(&visible,&box,&s->utile)) continue;
        double dx=fmax(fmax(visible.x-m->cursore->x,0),m->cursore->x-visible.x-visible.width);
        double dy=fmax(fmax(visible.y-m->cursore->y,0),m->cursore->y-visible.y-visible.height);
        double score=dx*dx+dy*dy;
        if(score<distance || (score==distance && best && g->tiling_col<best->tiling_col)) {distance=score;best=g;}
    }
    return best;
}
