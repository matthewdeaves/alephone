/*
 *  cspaths_darwin.cpp - Standard directory paths for macOS using CoreFoundation / POSIX
 */

#include "cstypes.h"
#include "cspaths.h"
#include <CoreFoundation/CoreFoundation.h>
#include <sys/param.h>
#include <unistd.h>
#include <string>

static std::string _add_app_name(std::string parent)
{
	return parent + "/" + get_application_name();
}

static std::string _add_app_id(std::string parent)
{
	return parent + "/" + get_application_identifier();
}

static std::string _get_local_data_path()
{
	static std::string local_data_dir = "";
	if (local_data_dir.empty())
	{
		const char *home = getenv("HOME");
		if (home)
			local_data_dir = _add_app_name(std::string(home) + "/Library/Application Support");
		else
			local_data_dir = _add_app_name("/Library/Application Support");
	}
	return local_data_dir;
}

static std::string _get_default_data_path()
{
	static std::string default_dir = "";
	if (default_dir.empty())
	{
		char parentdir[MAXPATHLEN];
		CFBundleRef bundle = CFBundleGetMainBundle();
		if (bundle)
		{
			CFURLRef url = CFBundleCopyBundleURL(bundle);
			if (url)
			{
				CFURLRef url2 = CFURLCreateCopyDeletingLastPathComponent(kCFAllocatorDefault, url);
				if (url2)
				{
					if (CFURLGetFileSystemRepresentation(url2, true, (UInt8 *)parentdir, MAXPATHLEN))
						default_dir = parentdir;
					CFRelease(url2);
				}
				CFRelease(url);
			}
		}
	}
	return default_dir;
}

static std::string _get_library_path()
{
	static std::string library_dir = "";
	if (library_dir.empty())
	{
		const char *home = getenv("HOME");
		if (home)
			library_dir = std::string(home) + "/Library";
		else
			library_dir = "/Library";
	}
	return library_dir;
}

std::string get_data_path(CSPathType type)
{
	std::string path = "";
	
	switch (type) {
		case kPathLocalData:
			path = _get_local_data_path();
			break;
		case kPathDefaultData:
			path = _get_default_data_path();
			break;
		case kPathLegacyData:
			break;
		case kPathBundleData: {
			CFBundleRef bundle = CFBundleGetMainBundle();
			if (bundle)
			{
				CFURLRef resUrl = CFBundleCopyResourcesDirectoryURL(bundle);
				if (resUrl)
				{
					char respath[MAXPATHLEN];
					if (CFURLGetFileSystemRepresentation(resUrl, true, (UInt8 *)respath, MAXPATHLEN))
						path = std::string(respath) + "/DataFiles";
					CFRelease(resUrl);
				}
			}
			break;
		}
		case kPathLogs:
			path = _get_library_path() + "/Logs";
			break;
		case kPathPreferences:
			path = _add_app_id(_get_library_path() + "/Preferences");
			break;
		case kPathLegacyPreferences:
			path = _get_local_data_path();
			break;
		case kPathScreenshots:
			path = _get_local_data_path() + "/Screenshots";
			break;
		case kPathSavedGames:
			path = _get_local_data_path() + "/Saved Games";
			break;
		case kPathQuickSaves:
			path = _get_local_data_path() + "/Quick Saves";
			break;
		case kPathImageCache:
			path = _get_local_data_path() + "/Image Cache";
			break;
		case kPathRecordings:
			path = _get_local_data_path() + "/Recordings";
			break;
	}
	return path;
}

std::string get_application_name()
{
	static std::string name = "";
	if (name.empty())
	{
		CFBundleRef bundle = CFBundleGetMainBundle();
		if (bundle)
		{
			CFStringRef cfName = (CFStringRef)CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("CFBundleName"));
			if (cfName)
			{
				char buf[256];
				if (CFStringGetCString(cfName, buf, sizeof(buf), kCFStringEncodingUTF8))
					name = buf;
			}
		}
		if (name.empty()) name = "AlephOne";
	}
	return name;
}

std::string get_application_identifier()
{
	static std::string ident = "";
	if (ident.empty())
	{
		CFBundleRef bundle = CFBundleGetMainBundle();
		if (bundle)
		{
			CFStringRef cfIdent = CFBundleGetIdentifier(bundle);
			if (cfIdent)
			{
				char buf[256];
				if (CFStringGetCString(cfIdent, buf, sizeof(buf), kCFStringEncodingUTF8))
					ident = buf;
			}
		}
		if (ident.empty()) ident = "org.bungie.source.AlephOne";
	}
	return ident;
}
