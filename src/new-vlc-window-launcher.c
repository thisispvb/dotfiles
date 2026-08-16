#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 * Build from the repository root with:
 *
 *   xcrun clang -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -Os \
 *     -o "home/Applications/New VLC Window.app/Contents/MacOS/executable_New VLC Window" \
 *     src/new-vlc-window-launcher.c
 *
 * Launch Services needs a Mach-O entry point to identify the app's supported
 * architectures. A shell script here is incorrectly classified as Intel-only
 * on Apple silicon and causes macOS to request Rosetta.
 */
int main(void) {
	char executable_path[PATH_MAX];
	uint32_t executable_path_size = sizeof(executable_path);

	if (_NSGetExecutablePath(executable_path, &executable_path_size) != 0) {
		fprintf(stderr, "New VLC Window: executable path is too long\n");
		return EXIT_FAILURE;
	}
	char *executable_name = strrchr(executable_path, '/');
	if (executable_name == NULL) {
		fprintf(stderr, "New VLC Window: invalid executable path\n");
		return EXIT_FAILURE;
	}
	*executable_name = '\0';

	char script_path[PATH_MAX];
	int written = snprintf(
		script_path,
		sizeof(script_path),
		"%s/../Resources/Scripts/main.applescript",
		executable_path
	);
	if (written < 0 || (size_t)written >= sizeof(script_path)) {
		fprintf(stderr, "New VLC Window: script path is too long\n");
		return EXIT_FAILURE;
	}

	execl("/usr/bin/osascript", "osascript", script_path, (char *)NULL);
	fprintf(stderr, "New VLC Window: could not start osascript: %s\n", strerror(errno));
	return EXIT_FAILURE;
}
