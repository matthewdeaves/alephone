/*
 *  csalerts_darwin.cpp - Game alerts and browser launch for macOS (CoreFoundation / CoreServices)
 */

#include "cstypes.h"
#include "csalerts.h"
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>

void system_alert_user(const char* message, short severity)
{
	CFStringRef header = (severity == infoError) ? CFSTR("Warning") : CFSTR("Error");
	CFStringRef msg = CFStringCreateWithCString(kCFAllocatorDefault, message, kCFStringEncodingUTF8);
	CFOptionFlags responseFlags = 0;
	CFUserNotificationDisplayAlert(0, kCFUserNotificationNoteAlertLevel, NULL, NULL, NULL,
		header, msg ? msg : CFSTR(""), NULL, NULL, NULL, &responseFlags);
	if (msg) CFRelease(msg);
}

bool system_alert_choose_scenario(char *chosen_dir)
{
	(void)chosen_dir;
	return false;
}

void system_launch_url_in_browser(const char *url)
{
	CFURLRef cfurl = CFURLCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)url, strlen(url), kCFStringEncodingUTF8, NULL);
	if (cfurl) {
		LSOpenCFURLRef(cfurl, NULL);
		CFRelease(cfurl);
	}
}

// alephone#39: SDL's Cocoa_RegisterApp calls [NSApp finishLaunching] before it
// installs its app delegate, so AppKit takes any non-option argv entry (a film,
// a scenario directory) as a document to open with no delegate to claim it.
// NSDocumentController then fails on the Info.plist's empty NSDocumentClass and
// runs a modal error alert from inside SDL_Init, before any game window exists:
// the app sits frontmost with only a menu bar and never starts. The engine
// already opens its argv files itself (shell_options.files), so tell AppKit to
// leave them alone. Plain C runtime calls, because the PPC toolchain builds no
// Objective-C; registerDefaults: is the volatile domain, nothing is saved.
#include <objc/objc.h>
#if defined(__has_include) && __has_include(<objc/message.h>)
#include <objc/runtime.h>
#include <objc/message.h>
#else
// 10.3.9/10.4u SDKs have no message.h, and their objc-runtime.h pulls in
// objc-class.h's bare `@class`, which C++ rejects. Declare the two calls as
// those SDKs do.
extern "C" id objc_getClass(const char *name);
extern "C" id objc_msgSend(id self, SEL op, ...);
#endif

void system_disable_argv_document_open()
{
	typedef id (*msg_id)(id, SEL);
	typedef void (*msg_void_id)(id, SEL, id);
	id pool_class = (id)objc_getClass("NSAutoreleasePool");
	id defaults_class = (id)objc_getClass("NSUserDefaults");
	if (!pool_class || !defaults_class)
		return;
	id pool = ((msg_id)objc_msgSend)(((msg_id)objc_msgSend)(pool_class, sel_registerName("alloc")), sel_registerName("init"));
	id defaults = ((msg_id)objc_msgSend)(defaults_class, sel_registerName("standardUserDefaults"));
	const void *keys[] = { CFSTR("NSTreatUnknownArgumentsAsOpen") };
	const void *values[] = { CFSTR("NO") };
	CFDictionaryRef dict = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
		&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	if (defaults && dict)
		((msg_void_id)objc_msgSend)(defaults, sel_registerName("registerDefaults:"), (id)dict);
	if (dict) CFRelease(dict);
	((msg_id)objc_msgSend)(pool, sel_registerName("release"));
}
