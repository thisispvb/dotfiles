use framework "AppKit"
use framework "Foundation"

on run
	-- -n asks Launch Services for a separate process even when VLC is open.
	set launchTask to current application's NSTask's launchedTaskWithLaunchPath:"/usr/bin/open" arguments:{"-n", "-b", "org.videolan.vlc"}
	launchTask's waitUntilExit()

	if (launchTask's terminationStatus() as integer) is not 0 then
		set failureAlert to current application's NSAlert's alloc()'s init()
		failureAlert's setMessageText:"VLC could not be opened"
		failureAlert's setInformativeText:"Install VLC.app, then try again."
		failureAlert's addButtonWithTitle:"OK"
		failureAlert's runModal()
	end if
end run
