#include <stdlib.h>
#include <assert.h>
#include <pixman.h>
#include <time.h>
#include <unistd.h>
#include <wlr/render/drm_syncobj.h>
#include <wlr/util/transform.h>
#include "render/egl.h"
#include "render/gles2.h"
#include "util/matrix.h"

#define MAX_QUADS 86 // 4kb

static const struct wlr_render_pass_impl render_pass_impl;

static struct wlr_gles2_render_pass *get_render_pass(struct wlr_render_pass *wlr_pass) {
	assert(wlr_pass->impl == &render_pass_impl);
	struct wlr_gles2_render_pass *pass = wl_container_of(wlr_pass, pass, base);
	return pass;
}

static bool render_pass_submit(struct wlr_render_pass *wlr_pass) {
	struct wlr_gles2_render_pass *pass = get_render_pass(wlr_pass);
	struct wlr_gles2_renderer *renderer = pass->buffer->renderer;
	struct wlr_gles2_render_timer *timer = pass->timer;
	bool ok = false;

	push_gles2_debug(renderer);

	if (timer) {
		// clear disjoint flag
		GLint64 disjoint;
		renderer->procs.glGetInteger64vEXT(GL_GPU_DISJOINT_EXT, &disjoint);
		// set up the query
		renderer->procs.glQueryCounterEXT(timer->id, GL_TIMESTAMP_EXT);
		// get end-of-CPU-work time in GL time domain
		renderer->procs.glGetInteger64vEXT(GL_TIMESTAMP_EXT, &timer->gl_cpu_end);
		// get end-of-CPU-work time in CPU time domain
		clock_gettime(CLOCK_MONOTONIC, &timer->cpu_end);
	}

	if (pass->signal_timeline != NULL) {
		EGLSyncKHR sync = wlr_egl_create_sync(renderer->egl, -1);
		if (sync == EGL_NO_SYNC_KHR) {
			goto out;
		}

		int sync_file_fd = wlr_egl_dup_fence_fd(renderer->egl, sync);
		wlr_egl_destroy_sync(renderer->egl, sync);
		if (sync_file_fd < 0) {
			goto out;
		}

		ok = wlr_drm_syncobj_timeline_import_sync_file(pass->signal_timeline, pass->signal_point, sync_file_fd);
		close(sync_file_fd);
		if (!ok) {
			goto out;
		}
	} else {
		glFlush();
	}

	ok = true;

out:
	glBindFramebuffer(GL_FRAMEBUFFER, 0);

	pop_gles2_debug(renderer);
	wlr_egl_restore_context(&pass->prev_ctx);

	wlr_drm_syncobj_timeline_unref(pass->signal_timeline);
	wlr_buffer_unlock(pass->buffer->buffer);
	free(pass);

	return ok;
}

static void render(const struct wlr_box *box, const pixman_region32_t *clip, GLint attrib) {
	pixman_region32_t region;
	pixman_region32_init_rect(&region, box->x, box->y, box->width, box->height);

	if (clip) {
		pixman_region32_intersect(&region, &region, clip);
	}

	int rects_len;
	const pixman_box32_t *rects = pixman_region32_rectangles(&region, &rects_len);
	if (rects_len == 0) {
		pixman_region32_fini(&region);
		return;
	}

	glEnableVertexAttribArray(attrib);

	for (int i = 0; i < rects_len;) {
		int batch = rects_len - i < MAX_QUADS ? rects_len - i : MAX_QUADS;
		int batch_end = batch + i;

		size_t vert_index = 0;
		GLfloat verts[MAX_QUADS * 6 * 2];
		for (; i < batch_end; i++) {
			const pixman_box32_t *rect = &rects[i];

			verts[vert_index++] = (GLfloat)(rect->x1 - box->x) / box->width;
			verts[vert_index++] = (GLfloat)(rect->y1 - box->y) / box->height;
			verts[vert_index++] = (GLfloat)(rect->x2 - box->x) / box->width;
			verts[vert_index++] = (GLfloat)(rect->y1 - box->y) / box->height;
			verts[vert_index++] = (GLfloat)(rect->x1 - box->x) / box->width;
			verts[vert_index++] = (GLfloat)(rect->y2 - box->y) / box->height;
			verts[vert_index++] = (GLfloat)(rect->x2 - box->x) / box->width;
			verts[vert_index++] = (GLfloat)(rect->y1 - box->y) / box->height;
			verts[vert_index++] = (GLfloat)(rect->x2 - box->x) / box->width;
			verts[vert_index++] = (GLfloat)(rect->y2 - box->y) / box->height;
			verts[vert_index++] = (GLfloat)(rect->x1 - box->x) / box->width;
			verts[vert_index++] = (GLfloat)(rect->y2 - box->y) / box->height;
		}

		glVertexAttribPointer(attrib, 2, GL_FLOAT, GL_FALSE, 0, verts);
		glDrawArrays(GL_TRIANGLES, 0, batch * 6);
	}

	glDisableVertexAttribArray(attrib);

	pixman_region32_fini(&region);
}

static void set_proj_matrix(GLint loc, float proj[9], const struct wlr_box *box) {
	float gl_matrix[9];
	wlr_matrix_identity(gl_matrix);
	wlr_matrix_translate(gl_matrix, box->x, box->y);
	wlr_matrix_scale(gl_matrix, box->width, box->height);
	wlr_matrix_multiply(gl_matrix, proj, gl_matrix);
	glUniformMatrix3fv(loc, 1, GL_FALSE, gl_matrix);
}

static void set_tex_matrix(GLint loc, enum wl_output_transform trans,
		const struct wlr_fbox *box) {
	float tex_matrix[9];
	wlr_matrix_identity(tex_matrix);
	wlr_matrix_translate(tex_matrix, box->x, box->y);
	wlr_matrix_scale(tex_matrix, box->width, box->height);
	wlr_matrix_translate(tex_matrix, .5, .5);

	// since textures have a different origin point we have to transform
	// differently if we are rotating
	if (trans & WL_OUTPUT_TRANSFORM_90) {
		wlr_matrix_transform(tex_matrix, wlr_output_transform_invert(trans));
	} else {
		wlr_matrix_transform(tex_matrix, trans);
	}
	wlr_matrix_translate(tex_matrix, -.5, -.5);

	glUniformMatrix3fv(loc, 1, GL_FALSE, tex_matrix);
}

static void setup_blending(enum wlr_render_blend_mode mode) {
	switch (mode) {
	case WLR_RENDER_BLEND_MODE_PREMULTIPLIED:
		glEnable(GL_BLEND);
		break;
	case WLR_RENDER_BLEND_MODE_NONE:
		glDisable(GL_BLEND);
		break;
	}
}

static void minerva_uniforms(GLuint p, struct wlr_box box, struct wlr_minerva_style style) {
 struct wlr_minerva_radii r=style.corners, h=style.hole.corners;
 struct wlr_box b=style.hole.area;
 glUniform2f(glGetUniformLocation(p,"minerva_size"),box.width,box.height);
 glUniform4f(glGetUniformLocation(p,"minerva_radii"),r.top_left,r.top_right,r.bottom_right,r.bottom_left);
 glUniform4f(glGetUniformLocation(p,"minerva_hole"),b.x,b.y,b.width,b.height);
 glUniform4f(glGetUniformLocation(p,"minerva_hole_radii"),h.top_left,h.top_right,h.bottom_right,h.bottom_left);
}

static void render_pass_add_texture(struct wlr_render_pass *wlr_pass,
		const struct wlr_render_texture_options *options) {
	struct wlr_gles2_render_pass *pass = get_render_pass(wlr_pass);
	struct wlr_gles2_renderer *renderer = pass->buffer->renderer;
	struct wlr_gles2_texture *texture = gles2_get_texture(options->texture);

	struct wlr_gles2_tex_shader *shader = NULL;

	switch (texture->target) {
	case GL_TEXTURE_2D:
		if (texture->has_alpha) {
			shader = &renderer->shaders.tex_rgba;
		} else {
			shader = &renderer->shaders.tex_rgbx;
		}
		break;
	case GL_TEXTURE_EXTERNAL_OES:
		// EGL_EXT_image_dma_buf_import_modifiers requires
		// GL_OES_EGL_image_external
		assert(renderer->exts.OES_egl_image_external);
		shader = &renderer->shaders.tex_ext;
		break;
	default:
		abort();
	}

	struct wlr_box dst_box;
	struct wlr_fbox src_fbox;
	wlr_render_texture_options_get_src_box(options, &src_fbox);
	wlr_render_texture_options_get_dst_box(options, &dst_box);
	float alpha = wlr_render_texture_options_get_alpha(options);

	src_fbox.x /= options->texture->width;
	src_fbox.y /= options->texture->height;
	src_fbox.width /= options->texture->width;
	src_fbox.height /= options->texture->height;

	push_gles2_debug(renderer);

	if (options->wait_timeline != NULL) {
		int sync_file_fd =
			wlr_drm_syncobj_timeline_export_sync_file(options->wait_timeline, options->wait_point);
		if (sync_file_fd < 0) {
			return;
		}

		EGLSyncKHR sync = wlr_egl_create_sync(renderer->egl, sync_file_fd);
		close(sync_file_fd);
		if (sync == EGL_NO_SYNC_KHR) {
			return;
		}

		bool ok = wlr_egl_wait_sync(renderer->egl, sync);
		wlr_egl_destroy_sync(renderer->egl, sync);
		if (!ok) {
			return;
		}
	}

	setup_blending(!texture->has_alpha && alpha == 1.0 && !wlr_minerva_has_radii(options->minerva.corners) ?
		WLR_RENDER_BLEND_MODE_NONE : options->blend_mode);

	glUseProgram(shader->program);
	minerva_uniforms(shader->program, dst_box, options->minerva);

	glActiveTexture(GL_TEXTURE0);
	glBindTexture(texture->target, texture->tex);

	switch (options->filter_mode) {
	case WLR_SCALE_FILTER_BILINEAR:
		glTexParameteri(texture->target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(texture->target, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		break;
	case WLR_SCALE_FILTER_NEAREST:
		glTexParameteri(texture->target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(texture->target, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		break;
	}

	glUniform1i(shader->tex, 0);
	glUniform1f(shader->alpha, alpha);
	set_proj_matrix(shader->proj, pass->projection_matrix, &dst_box);
	set_tex_matrix(shader->tex_proj, options->transform, &src_fbox);

	render(&dst_box, options->clip, shader->pos_attrib);

	glBindTexture(texture->target, 0);
	pop_gles2_debug(renderer);
}

static void render_pass_add_rect(struct wlr_render_pass *wlr_pass,
		const struct wlr_render_rect_options *options) {
	struct wlr_gles2_render_pass *pass = get_render_pass(wlr_pass);
	struct wlr_gles2_renderer *renderer = pass->buffer->renderer;

	const struct wlr_render_color *color = &options->color;
	struct wlr_box box;
	struct wlr_buffer *wlr_buffer = pass->buffer->buffer;
	wlr_render_rect_options_get_box(options, wlr_buffer, &box);

	push_gles2_debug(renderer);
	enum wlr_render_blend_mode blend_mode =
		color->a == 1.0 && !wlr_minerva_has_radii(options->minerva.corners) && options->minerva.hole.area.width == 0 ? WLR_RENDER_BLEND_MODE_NONE : options->blend_mode;
	if (blend_mode == WLR_RENDER_BLEND_MODE_NONE &&
			options->clip == NULL &&
			box.x == 0 && box.y == 0 &&
			box.width == wlr_buffer->width &&
			box.height == wlr_buffer->height) {
		glClearColor(color->r, color->g, color->b, color->a);
		glClear(GL_COLOR_BUFFER_BIT);
	} else {
		setup_blending(blend_mode);
		glUseProgram(renderer->shaders.quad.program);
		minerva_uniforms(renderer->shaders.quad.program, box, options->minerva);
		set_proj_matrix(renderer->shaders.quad.proj, pass->projection_matrix, &box);
		glUniform4f(renderer->shaders.quad.color, color->r, color->g, color->b, color->a);
		render(&box, options->clip, renderer->shaders.quad.pos_attrib);
	}

	pop_gles2_debug(renderer);
}

static bool minerva_blur_pezzo(struct wlr_render_pass *base,
  const struct wlr_render_rect_options *options, const struct wlr_render_texture_options *mask_options) {
 struct wlr_gles2_render_pass *pass=get_render_pass(base);
 struct wlr_gles2_renderer *r=pass->buffer->renderer;
 struct wlr_texture *mask=mask_options ? mask_options->texture : NULL;
 if (mask_options) {
  /* Unsupported masks must not silently become a fully blurred rectangle. */
  if (!mask || !wlr_texture_is_gles2(mask) ||
    gles2_get_texture(mask)->target != GL_TEXTURE_2D) return false;
  if (mask_options->wait_timeline) {
   int fd=wlr_drm_syncobj_timeline_export_sync_file(
    mask_options->wait_timeline,mask_options->wait_point);
   if (fd<0) return false;
   EGLSyncKHR sync=wlr_egl_create_sync(r->egl,fd);
   close(fd);
   if (sync==EGL_NO_SYNC_KHR) return false;
   bool waited=wlr_egl_wait_sync(r->egl,sync);
   wlr_egl_destroy_sync(r->egl,sync);
   if (!waited) return false;
  }
 }
 int fw=pass->buffer->buffer->width, fh=pass->buffer->buffer->height;
 struct wlr_box box=options->box;
 /* Capture only the affected rectangle and the filter footprint, bounded by
  * the framebuffer. The pool is shared across calls, never GPU->CPU readback. */
 /* This renderer uses FLIPPED_180 projection: buffer coordinates already
  * match GL framebuffer coordinates. Flipping y again captures the opposite
  * edge of the output for a filter which isn't vertically centered. */
 if (box.width<=0 || box.height<=0) return true;
 float radius=options->minerva.blur_radius;
 if (radius==0) radius=3;
 if (!isfinite(radius) || radius<=0 || radius>6) return false;
 int padding=(int)ceilf(radius*4)+8;
 /* La griglia: l'origine della cattura COMPLETA, anche fuori schermo. */
 int64_t gx=(int64_t)box.x-padding, gy=(int64_t)box.y-padding;
 int64_t left=gx, bottom=gy;
 int64_t right=(int64_t)box.x+box.width+padding, top=(int64_t)box.y+box.height+padding;
 /* ── Solo il pezzo che serve ──────────────────────────────────────────
  * Il filtro ridà pixel solo dentro il ritaglio (il danno): catturare e
  * sfocare tutto il rettangolo — per una finestra ingrandita, quasi lo
  * schermo — costava 4,2 ms a fotogramma per un quadrato di 70 pixel
  * (misurato il 23 settembre 2026). Basta il ritaglio allargato del
  * margine del filtro. */
 if (options->clip && !pixman_region32_empty(options->clip)) {
  const pixman_box32_t *e=pixman_region32_extents(options->clip);
  if (left<(int64_t)e->x1-padding) left=(int64_t)e->x1-padding;
  if (bottom<(int64_t)e->y1-padding) bottom=(int64_t)e->y1-padding;
  if (right>(int64_t)e->x2+padding) right=(int64_t)e->x2+padding;
  if (top>(int64_t)e->y2+padding) top=(int64_t)e->y2+padding;
 }
 if (left<0) left=0;
 if (bottom<0) bottom=0;
 if (right>fw) right=fw;
 if (top>fh) top=fh;
 /* ── E sulla stessa griglia della cattura completa ────────────────────
  * La sfocatura lavora a metà risoluzione: un texel è la media di due
  * pixel. Se il pezzo partisse da un pixel dispari rispetto alla cattura
  * completa, le coppie sarebbero altre e il risultato diverso di un
  * livello qua e là: le cuciture di prima, da un'altra porta. Origine
  * della stessa parità della griglia, e misure pari. */
 if ((left-gx)&1) left = left>0 ? left-1 : left+1;
 if ((bottom-gy)&1) bottom = bottom>0 ? bottom-1 : bottom+1;
 if ((right-left)&1) right = right<fw ? right+1 : right-1;
 if ((top-bottom)&1) top = top<fh ? top+1 : top-1;
 if (right<=left || top<=bottom) return true;
 int x=left, y=bottom, w=right-left, h=top-bottom;
 if ((uint64_t)w*h*6 > 128u*1024u*1024u) return false;
 int sw=(w+1)/2,sh=(h+1)/2;
 GLint old_fbo; glGetIntegerv(GL_FRAMEBUFFER_BINDING,&old_fbo);
 if (!r->minerva_blur.fbo) {
  glGenTextures(3,r->minerva_blur.tex); glGenFramebuffers(1,&r->minerva_blur.fbo);
 }
 glActiveTexture(GL_TEXTURE0);
 bool resize=r->minerva_blur.width!=w||r->minerva_blur.height!=h;
 for(int i=0;i<3;i++) {
  glBindTexture(GL_TEXTURE_2D,r->minerva_blur.tex[i]);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  if(resize) glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,i?sw:w,i?sh:h,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
 }
 r->minerva_blur.width=w; r->minerva_blur.height=h;
 glBindTexture(GL_TEXTURE_2D,r->minerva_blur.tex[0]);
 glCopyTexSubImage2D(GL_TEXTURE_2D,0,0,0,x,y,w,h);
 GLuint p=r->minerva_blur.program;
 glUseProgram(p); glUniform1i(glGetUniformLocation(p,"tex"),0);
 glUniform1f(glGetUniformLocation(p,"composite"),0);
 glDisable(GL_BLEND); glDisable(GL_SCISSOR_TEST);
 GLfloat projection[9]; matrix_projection(projection,sw,sh,WL_OUTPUT_TRANSFORM_FLIPPED_180);
 struct wlr_box small={0,0,sw,sh};
 GLint pos=glGetAttribLocation(p,"pos");
 glBindFramebuffer(GL_FRAMEBUFFER,r->minerva_blur.fbo); glViewport(0,0,sw,sh);
 bool ok=true;
 for(int i=0;i<2;i++) {
  glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,r->minerva_blur.tex[i+1],0);
  if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE) { ok=false; break; }
  glBindTexture(GL_TEXTURE_2D,r->minerva_blur.tex[i]);
  glUniform2f(glGetUniformLocation(p,"step_uv"),i?0:radius/w,i?radius/h:0);
  set_proj_matrix(glGetUniformLocation(p,"proj"),projection,&small);
  render(&small,NULL,pos);
 }
 glBindFramebuffer(GL_FRAMEBUFFER,old_fbo); glViewport(0,0,fw,fh);
 if(ok) {
  glUniform1f(glGetUniformLocation(p,"composite"),1);
  glUniform4f(glGetUniformLocation(p,"capture"),x,y,w,h);
  glUniform1f(glGetUniformLocation(p,"has_mask"),0);
  if(mask && wlr_texture_is_gles2(mask)) {
   struct wlr_gles2_texture *m=gles2_get_texture(mask);
   if(m->target==GL_TEXTURE_2D) {
    glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_2D,m->tex);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glUniform1i(glGetUniformLocation(p,"mask"),1);glUniform1f(glGetUniformLocation(p,"has_mask"),1);
   }
  }
  glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,r->minerva_blur.tex[2]);
  minerva_uniforms(p,box,options->minerva);
  set_proj_matrix(glGetUniformLocation(p,"proj"),pass->projection_matrix,&box);
  setup_blending(WLR_RENDER_BLEND_MODE_PREMULTIPLIED);
  render(&box,options->clip,pos);
 }
 glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_2D,0);
 glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,0);
 return ok;
}

/* ── Mettere da parte un pezzo di fotogramma, e rimetterlo ─────────────────
 *
 * Il danno incrementale del blur ridisegna lo sfondo in una FASCIA attorno
 * al pezzo che cambia (vedi wlr_scene.c, «le fasce»): la sfocatura al bordo
 * del pezzo deve leggere sfondo vero, e appena fuori dal pezzo nel
 * fotogramma c'è l'immagine finale di prima — la finestra già sfocata, col
 * suo testo sopra. Prima di disegnare, la fascia si copia qui così com'è;
 * alla fine si rimette, e fuori dal pezzo il fotogramma non cambia di un
 * pixel.
 *
 * Il rettangolo che contiene la regione, non la regione: una copia sola sulla
 * GPU, e al ripristino si ritaglia con la regione vera. */
static bool minerva_salva(struct wlr_render_pass *base, const pixman_region32_t *region) {
 struct wlr_gles2_render_pass *pass=get_render_pass(base);
 struct wlr_gles2_renderer *r=pass->buffer->renderer;
 int fw=pass->buffer->buffer->width, fh=pass->buffer->buffer->height;
 r->minerva_salvato.width=0; r->minerva_salvato.height=0;
 if (pixman_region32_empty(region)) return true;
 const pixman_box32_t *e=pixman_region32_extents(region);
 int x1=e->x1<0?0:e->x1, y1=e->y1<0?0:e->y1;
 int x2=e->x2>fw?fw:e->x2, y2=e->y2>fh?fh:e->y2;
 if (x2<=x1 || y2<=y1) return true;
 int w=x2-x1, h=y2-y1;
 if (!r->minerva_salvato.tex) glGenTextures(1,&r->minerva_salvato.tex);
 glActiveTexture(GL_TEXTURE0);
 glBindTexture(GL_TEXTURE_2D,r->minerva_salvato.tex);
 if (r->minerva_salvato.tex_width!=w || r->minerva_salvato.tex_height!=h) {
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,w,h,0,GL_RGBA,GL_UNSIGNED_BYTE,NULL);
  r->minerva_salvato.tex_width=w; r->minerva_salvato.tex_height=h;
 }
 /* Stesse coordinate della cattura del blur: con la proiezione di questo
  * renderer quelle del buffer sono già quelle di GL. */
 glCopyTexSubImage2D(GL_TEXTURE_2D,0,0,0,x1,y1,w,h);
 glBindTexture(GL_TEXTURE_2D,0);
 r->minerva_salvato.x=x1; r->minerva_salvato.y=y1;
 r->minerva_salvato.width=w; r->minerva_salvato.height=h;
 return true;
}

static bool minerva_ripristina(struct wlr_render_pass *base, const pixman_region32_t *region) {
 struct wlr_gles2_render_pass *pass=get_render_pass(base);
 struct wlr_gles2_renderer *r=pass->buffer->renderer;
 if (r->minerva_salvato.width<=0 || r->minerva_salvato.height<=0) return true;
 struct wlr_box box={r->minerva_salvato.x,r->minerva_salvato.y,
  r->minerva_salvato.width,r->minerva_salvato.height};
 /* Il programma del blur nella sua fase di composizione: senza angoli, senza
  * buco e senza maschera copia il pixel della texture così com'è. */
 GLuint p=r->minerva_blur.program;
 glUseProgram(p);
 glUniform1i(glGetUniformLocation(p,"tex"),0);
 glUniform1f(glGetUniformLocation(p,"composite"),1);
 glUniform1f(glGetUniformLocation(p,"has_mask"),0);
 glUniform4f(glGetUniformLocation(p,"capture"),box.x,box.y,box.width,box.height);
 minerva_uniforms(p,box,(struct wlr_minerva_style){0});
 glActiveTexture(GL_TEXTURE0);
 glBindTexture(GL_TEXTURE_2D,r->minerva_salvato.tex);
 set_proj_matrix(glGetUniformLocation(p,"proj"),pass->projection_matrix,&box);
 setup_blending(WLR_RENDER_BLEND_MODE_NONE);
 render(&box,region,glGetAttribLocation(p,"pos"));
 glBindTexture(GL_TEXTURE_2D,0);
 r->minerva_salvato.width=0;
 return true;
}

/* ── Pezzi lontani, sfocature separate ─────────────────────────────────────
 *
 * Il danno di un fotogramma è spesso fatto di pezzi lontani: il quadrato di
 * prima e quello di adesso, il cursore del testo e l'orologio. Il rettangolo
 * che li contiene tutti è grande, e sfocarlo intero vuol dire sfocare anche
 * tutto quello che sta in mezzo e non è cambiato. Qui i rettangoli del
 * ritaglio si raggruppano — due stanno insieme se i loro margini di filtro
 * si toccano — e ogni gruppo si sfoca per conto suo. Ogni pezzo è sulla
 * stessa griglia della cattura completa (vedi minerva_blur_pezzo): il
 * risultato è lo stesso, bit per bit. Se dividere non conviene (i gruppi
 * coprono quasi quanto il rettangolo intero), un passaggio solo. */
static bool minerva_blur(struct wlr_render_pass *base,
  const struct wlr_render_rect_options *options, const struct wlr_render_texture_options *mask_options) {
 const pixman_region32_t *clip=options->clip;
 if (!clip || pixman_region32_empty(clip)) return minerva_blur_pezzo(base,options,mask_options);
 int n=0;
 const pixman_box32_t *r=pixman_region32_rectangles(clip,&n);
 enum { GRUPPI_MAX = 16 };
 if (n<=1 || n>GRUPPI_MAX) return minerva_blur_pezzo(base,options,mask_options);
 float radius=options->minerva.blur_radius;
 if (radius==0) radius=3;
 if (!isfinite(radius) || radius<=0 || radius>6) return false;
 int64_t pad=(int64_t)ceilf(radius*4)+8;
 int64_t g[GRUPPI_MAX][4];
 int k=n;
 for (int i=0;i<n;i++) {
  g[i][0]=r[i].x1-pad; g[i][1]=r[i].y1-pad; g[i][2]=r[i].x2+pad; g[i][3]=r[i].y2+pad;
 }
 /* Si fondono finché due gruppi si toccano: al più sedici, basta così. */
 bool fuso=true;
 while (fuso) {
  fuso=false;
  for (int i=0;i<k && !fuso;i++) for (int j=i+1;j<k && !fuso;j++) {
   if (g[i][0]<g[j][2] && g[j][0]<g[i][2] && g[i][1]<g[j][3] && g[j][1]<g[i][3]) {
    if (g[j][0]<g[i][0]) g[i][0]=g[j][0];
    if (g[j][1]<g[i][1]) g[i][1]=g[j][1];
    if (g[j][2]>g[i][2]) g[i][2]=g[j][2];
    if (g[j][3]>g[i][3]) g[i][3]=g[j][3];
    for (int c=0;c<4;c++) g[j][c]=g[k-1][c];
    k--; fuso=true;
   }
  }
 }
 const pixman_box32_t *e=pixman_region32_extents(clip);
 int64_t tutto=(int64_t)(e->x2-e->x1+2*pad)*(int64_t)(e->y2-e->y1+2*pad), pezzi=0;
 for (int i=0;i<k;i++) pezzi+=(g[i][2]-g[i][0])*(g[i][3]-g[i][1]);
 if (k<=1 || pezzi*10>=tutto*8) return minerva_blur_pezzo(base,options,mask_options);
 bool ok=true;
 for (int i=0;i<k;i++) {
  pixman_region32_t sotto;
  pixman_region32_init_rect(&sotto,g[i][0],g[i][1],g[i][2]-g[i][0],g[i][3]-g[i][1]);
  pixman_region32_intersect(&sotto,&sotto,clip);
  struct wlr_render_rect_options o=*options;
  o.clip=&sotto;
  if (!pixman_region32_empty(&sotto)) ok=minerva_blur_pezzo(base,&o,mask_options) && ok;
  pixman_region32_fini(&sotto);
 }
 return ok;
}

static const struct wlr_render_pass_impl render_pass_impl = {
	.minerva_salva = minerva_salva,
	.minerva_ripristina = minerva_ripristina,
	.minerva_blur = minerva_blur,
	.submit = render_pass_submit,
	.add_texture = render_pass_add_texture,
	.add_rect = render_pass_add_rect,
};

static const char *reset_status_str(GLenum status) {
	switch (status) {
	case GL_GUILTY_CONTEXT_RESET_KHR:
		return "guilty";
	case GL_INNOCENT_CONTEXT_RESET_KHR:
		return "innocent";
	case GL_UNKNOWN_CONTEXT_RESET_KHR:
		return "unknown";
	default:
		return "<invalid>";
	}
}

struct wlr_gles2_render_pass *begin_gles2_buffer_pass(struct wlr_gles2_buffer *buffer,
		struct wlr_egl_context *prev_ctx, struct wlr_gles2_render_timer *timer,
		struct wlr_drm_syncobj_timeline *signal_timeline, uint64_t signal_point) {
	struct wlr_gles2_renderer *renderer = buffer->renderer;
	struct wlr_buffer *wlr_buffer = buffer->buffer;

	if (renderer->procs.glGetGraphicsResetStatusKHR) {
		GLenum status = renderer->procs.glGetGraphicsResetStatusKHR();
		if (status != GL_NO_ERROR) {
			wlr_log(WLR_ERROR, "GPU reset (%s)", reset_status_str(status));
			wl_signal_emit_mutable(&renderer->wlr_renderer.events.lost, NULL);
			return NULL;
		}
	}

	GLint fbo = gles2_buffer_get_fbo(buffer);
	if (!fbo) {
		return NULL;
	}

	struct wlr_gles2_render_pass *pass = calloc(1, sizeof(*pass));
	if (pass == NULL) {
		return NULL;
	}

	wlr_render_pass_init(&pass->base, &render_pass_impl);
	wlr_buffer_lock(wlr_buffer);
	pass->buffer = buffer;
	pass->timer = timer;
	pass->prev_ctx = *prev_ctx;
	if (signal_timeline != NULL) {
		pass->signal_timeline = wlr_drm_syncobj_timeline_ref(signal_timeline);
		pass->signal_point = signal_point;
	}

	matrix_projection(pass->projection_matrix, wlr_buffer->width, wlr_buffer->height,
		WL_OUTPUT_TRANSFORM_FLIPPED_180);

	push_gles2_debug(renderer);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);

	glViewport(0, 0, wlr_buffer->width, wlr_buffer->height);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	glDisable(GL_SCISSOR_TEST);
	pop_gles2_debug(renderer);

	return pass;
}
