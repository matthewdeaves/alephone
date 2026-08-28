/*

	Copyright (C) 2015 and beyond by Jeremiah Morris
	and the "Aleph One" developers.
 
	This program is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	This license is contained in the file "COPYING",
	which is included with this source code; it is available online at
	http://www.gnu.org/licenses/gpl.html
	
	Framebuffer Object utilities
*/

#include "cseries.h"
#include "OGL_FBO.h"

#ifdef HAVE_OPENGL

#include "OGL_Setup.h"
#include "OGL_Render.h"
#include "OGL_Textures.h"
#include "Logging.h"

// EXT_framebuffer_object post-dates the MacOSX10.3.9 SDK the ppc slice links
// against, so these entry points don't exist in that SDK's static stub at
// all (unlike e.g. ARB_shader_objects, which the 10.3.9 stub does export).
// Resolve them at runtime instead. This also covers any GPU/driver that
// genuinely lacks the extension: Rasterizer_Shader.cpp constructs an
// FBOSwapper unconditionally with no capability check, so without this guard
// that case was a null-function-pointer crash waiting to happen, not just a
// build-time symbol error.
namespace {
	PFNGLGENFRAMEBUFFERSEXTPROC p_glGenFramebuffersEXT = NULL;
	PFNGLBINDFRAMEBUFFEREXTPROC p_glBindFramebufferEXT = NULL;
	PFNGLGENRENDERBUFFERSEXTPROC p_glGenRenderbuffersEXT = NULL;
	PFNGLBINDRENDERBUFFEREXTPROC p_glBindRenderbufferEXT = NULL;
	PFNGLRENDERBUFFERSTORAGEEXTPROC p_glRenderbufferStorageEXT = NULL;
	PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC p_glFramebufferRenderbufferEXT = NULL;
	PFNGLFRAMEBUFFERTEXTURE2DEXTPROC p_glFramebufferTexture2DEXT = NULL;
	PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC p_glCheckFramebufferStatusEXT = NULL;
	PFNGLDELETEFRAMEBUFFERSEXTPROC p_glDeleteFramebuffersEXT = NULL;
	PFNGLDELETERENDERBUFFERSEXTPROC p_glDeleteRenderbuffersEXT = NULL;
	bool fbo_procs_loaded = false;
	bool fbo_procs_available = false;

	void LoadFBOProcs() {
		if (fbo_procs_loaded) return;
		fbo_procs_loaded = true;
		p_glGenFramebuffersEXT = (PFNGLGENFRAMEBUFFERSEXTPROC) SDL_GL_GetProcAddress("glGenFramebuffersEXT");
		p_glBindFramebufferEXT = (PFNGLBINDFRAMEBUFFEREXTPROC) SDL_GL_GetProcAddress("glBindFramebufferEXT");
		p_glGenRenderbuffersEXT = (PFNGLGENRENDERBUFFERSEXTPROC) SDL_GL_GetProcAddress("glGenRenderbuffersEXT");
		p_glBindRenderbufferEXT = (PFNGLBINDRENDERBUFFEREXTPROC) SDL_GL_GetProcAddress("glBindRenderbufferEXT");
		p_glRenderbufferStorageEXT = (PFNGLRENDERBUFFERSTORAGEEXTPROC) SDL_GL_GetProcAddress("glRenderbufferStorageEXT");
		p_glFramebufferRenderbufferEXT = (PFNGLFRAMEBUFFERRENDERBUFFEREXTPROC) SDL_GL_GetProcAddress("glFramebufferRenderbufferEXT");
		p_glFramebufferTexture2DEXT = (PFNGLFRAMEBUFFERTEXTURE2DEXTPROC) SDL_GL_GetProcAddress("glFramebufferTexture2DEXT");
		p_glCheckFramebufferStatusEXT = (PFNGLCHECKFRAMEBUFFERSTATUSEXTPROC) SDL_GL_GetProcAddress("glCheckFramebufferStatusEXT");
		p_glDeleteFramebuffersEXT = (PFNGLDELETEFRAMEBUFFERSEXTPROC) SDL_GL_GetProcAddress("glDeleteFramebuffersEXT");
		p_glDeleteRenderbuffersEXT = (PFNGLDELETERENDERBUFFERSEXTPROC) SDL_GL_GetProcAddress("glDeleteRenderbuffersEXT");
		fbo_procs_available = p_glGenFramebuffersEXT && p_glBindFramebufferEXT && p_glGenRenderbuffersEXT &&
			p_glBindRenderbufferEXT && p_glRenderbufferStorageEXT && p_glFramebufferRenderbufferEXT &&
			p_glFramebufferTexture2DEXT && p_glCheckFramebufferStatusEXT && p_glDeleteFramebuffersEXT &&
			p_glDeleteRenderbuffersEXT;
		if (!fbo_procs_available)
			logWarning("GL_EXT_framebuffer_object entry points not available; bloom/HDR post-processing disabled");
	}
}

#define glGenFramebuffersEXT p_glGenFramebuffersEXT
#define glBindFramebufferEXT p_glBindFramebufferEXT
#define glGenRenderbuffersEXT p_glGenRenderbuffersEXT
#define glBindRenderbufferEXT p_glBindRenderbufferEXT
#define glRenderbufferStorageEXT p_glRenderbufferStorageEXT
#define glFramebufferRenderbufferEXT p_glFramebufferRenderbufferEXT
#define glFramebufferTexture2DEXT p_glFramebufferTexture2DEXT
#define glCheckFramebufferStatusEXT p_glCheckFramebufferStatusEXT
#define glDeleteFramebuffersEXT p_glDeleteFramebuffersEXT
#define glDeleteRenderbuffersEXT p_glDeleteRenderbuffersEXT

std::vector<FBO *> FBO::active_chain;

FBO::FBO(GLuint w, GLuint h, bool srgb) : _fbo(0), _depthBuffer(0), _h(h), _w(w), _srgb(srgb) {
	LoadFBOProcs();

	glGenTextures(1, &texID);
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texID);
	glTexImage2D(GL_TEXTURE_RECTANGLE_ARB, 0, srgb ? GL_SRGB : GL_RGB8, _w, _h, 0, GL_RGB, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MAG_FILTER, TxtrTypeInfoList[OGL_Txtr_HUD].NearFilter);
	glTexParameteri(GL_TEXTURE_RECTANGLE_ARB, GL_TEXTURE_MIN_FILTER, TxtrTypeInfoList[OGL_Txtr_HUD].FarFilter);

	if (!fbo_procs_available)
		return;

	glGenFramebuffersEXT(1, &_fbo);
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, _fbo);

	glGenRenderbuffersEXT(1, &_depthBuffer);
	glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, _depthBuffer);
	glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_DEPTH_COMPONENT, _w, _h);
	glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_DEPTH_ATTACHMENT_EXT, GL_RENDERBUFFER_EXT, _depthBuffer);

	glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_ARB, texID, 0);
	assert(glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT) == GL_FRAMEBUFFER_COMPLETE_EXT);
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
}

void FBO::activate(bool clear, GLuint fboTarget) {
	if (!active_chain.size() || active_chain.back() != this) {
		active_chain.push_back(this);
		_fboTarget = fboTarget;
		if (fbo_procs_available)
			glBindFramebufferEXT(fboTarget, _fbo);
		glPushAttrib(GL_VIEWPORT_BIT);
		glViewport(0, 0, _w, _h);
		if (_srgb)
			glEnable(GL_FRAMEBUFFER_SRGB_EXT);
		else
			glDisable(GL_FRAMEBUFFER_SRGB_EXT);
		if (clear)
			glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	}
}

void FBO::deactivate() {
	if (active_chain.size() && active_chain.back() == this) {
		active_chain.pop_back();
		glPopAttrib();
		
		GLuint prev_fbo = 0;
		bool prev_srgb = Using_sRGB;
		if (active_chain.size()) {
			prev_fbo = active_chain.back()->_fbo;
			prev_srgb = active_chain.back()->_srgb;
		}
		if (fbo_procs_available)
			glBindFramebufferEXT(_fboTarget, prev_fbo);
		if (prev_srgb)
			glEnable(GL_FRAMEBUFFER_SRGB_EXT);
		else
			glDisable(GL_FRAMEBUFFER_SRGB_EXT);
	}
}

void FBO::draw() {
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, texID);
	glEnable(GL_TEXTURE_RECTANGLE_ARB);
	OGL_RenderTexturedRect(0, 0, _w, _h, 0, _h, _w, 0);
	glDisable(GL_TEXTURE_RECTANGLE_ARB);
}

void FBO::prepare_drawing_mode(bool blend) {
	glMatrixMode(GL_PROJECTION);
	glPushMatrix();
	glLoadIdentity();
	glMatrixMode(GL_MODELVIEW);
	glPushMatrix();
	glLoadIdentity();
	
	glDisable(GL_DEPTH_TEST);
	if (!blend)
		glDisable(GL_BLEND);
	
	glOrtho(0, _w, _h, 0, -1, 1);
	glColor4f(1.0, 1.0, 1.0, 1.0);
}

void FBO::reset_drawing_mode() {
	glEnable(GL_BLEND);
	glEnable(GL_DEPTH_TEST);
	glMatrixMode(GL_PROJECTION);
	glPopMatrix();
	glMatrixMode(GL_MODELVIEW);
	glPopMatrix();
}

void FBO::draw_full(bool blend) {
	prepare_drawing_mode(blend);
	draw();
	reset_drawing_mode();
}

FBO::~FBO() {
	if (fbo_procs_available) {
		glDeleteFramebuffersEXT(1, &_fbo);
		glDeleteRenderbuffersEXT(1, &_depthBuffer);
	}
}


void FBOSwapper::activate() {
	if (active)
		return;
	if (draw_to_first)
		first.activate(clear_on_activate);
	else
		second.activate(clear_on_activate);
	active = true;
	clear_on_activate = false;
}

void FBOSwapper::deactivate() {
	if (!active)
		return;
	if (draw_to_first)
		first.deactivate();
	else
		second.deactivate();
	active = false;
}

void FBOSwapper::swap() {
	deactivate();
	draw_to_first = !draw_to_first;
	clear_on_activate = true;
}

void FBOSwapper::draw(bool blend) {
	current_contents().draw_full(blend);
}

void FBOSwapper::filter(bool blend) {
	activate();
	draw(blend);
	swap();
}

void FBOSwapper::copy(FBO& other, bool srgb) {
	clear_on_activate = true;
	activate();
	other.draw_full(false);
	swap();
}

void FBOSwapper::blend(FBO& other, bool srgb) {
	activate();
	if (!srgb)
		glDisable(GL_FRAMEBUFFER_SRGB_EXT);
	else
		glEnable(GL_FRAMEBUFFER_SRGB_EXT);
	other.draw_full(true);
	deactivate();
}

void FBOSwapper::blend_multisample(FBO& other) {
	swap();
	activate();
	
	// set up FBO passed in as texture #1
	glActiveTextureARB(GL_TEXTURE1_ARB);
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, other.texID);
	glEnable(GL_TEXTURE_RECTANGLE_ARB);
	glActiveTextureARB(GL_TEXTURE0_ARB);
	
	glClientActiveTextureARB(GL_TEXTURE1_ARB);
	glEnableClientState(GL_TEXTURE_COORD_ARRAY);
	GLint multi_coordinates[8] = { 0, GLint(other._h), GLint(other._w), GLint(other._h), GLint(other._w), 0, 0, 0 };
	glTexCoordPointer(2, GL_INT, 0, multi_coordinates);
	glClientActiveTextureARB(GL_TEXTURE0_ARB);
	
	draw(true);
	
	// tear down multitexture stuff
	glActiveTextureARB(GL_TEXTURE1_ARB);
	glDisable(GL_TEXTURE_RECTANGLE_ARB);
	glActiveTextureARB(GL_TEXTURE0_ARB);
	
	glClientActiveTextureARB(GL_TEXTURE1_ARB);
	glDisableClientState(GL_TEXTURE_COORD_ARRAY);
	glClientActiveTextureARB(GL_TEXTURE0_ARB);
	
	deactivate();
}

#endif
