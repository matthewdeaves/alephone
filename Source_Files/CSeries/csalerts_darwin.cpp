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
