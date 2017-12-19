on run {msgText, targetPhoneNum, fileUrl}
    tell application "Messages"
        activate
    end tell
--We are using UI automation, get ready! This is a pretty okay method I made myself but it requires a pretty fast ish computer otherwise autocomplete fails. UI scripting without any feedback is hard
    tell application "Finder"
        activate
        # It's very important that the image gets saved to the desktop
        set targetFile to POSIX file fileUrl as string
        # Open and select the target file in finder
        reveal targetFile
        # Get the name of the target file
        set sel to get the selection
        set target_file_name to the name of (item 1 of sel)
    end tell
    
    tell application "System Events"
        tell process "Finder"
            #This part will not work if the file is not on the desktop
            tell group 1 of scroll area 1
                # Find the image on the desktop that shares the same name as the target file
                set target to the first image whose value of attribute "AXFilename" is target_file_name
                # This call performs a right click the file
                tell target to perform action "AXShowMenu"
                # Select share menu item
                keystroke "Share"
                keystroke return
                # Select messages sub menu item
                keystroke "Messages"
                keystroke return
                # At least on my computer, this next loading part takes FOREVER, delay so that we don't paste users before the window has shown up
                delay 5.0
                repeat with personString in my theSplit(targetPhoneNum, ", ")
                    keystroke personString
                    delay 2.0
                    keystroke ","
                    delay 0.5
                end repeat
                # Send Message
                keystroke return
                keystroke msgText
                keystroke return using command down
            end tell
        end tell
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
