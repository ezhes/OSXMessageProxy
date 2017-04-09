on run {msgText, targetPhoneNum}
	tell application "Messages"
		activate
	end tell
    set the clipboard to msgText
	tell application "System Events"
		keystroke "n" using {command down}
		delay 0.8
		repeat with personString in my theSplit(targetPhoneNum, ", ")
			keystroke personString
			delay 2.0
			keystroke ","
			delay 0.5
		end repeat
		-- Jump to our message field with another return
		keystroke return
		delay 0.5
        keystroke "v" using command down
        keystroke return
		delay 0.5
		keystroke return
	end tell
end run

on theSplit(theString, theDelimiter)
	-- save delimiters to restore old settings
	set oldDelimiters to AppleScript's text item delimiters
	-- set delimiters to delimiter to be used
	set AppleScript's text item delimiters to theDelimiter
	-- create the array
	set theArray to every text item of theString
	-- restore the old setting
	set AppleScript's text item delimiters to oldDelimiters
	-- return the result
	return theArray
end theSplit
