# MessageProxy: An Open Source iMessage API 


This API is primarily designed to be used with [AndromedaB (open source!)](https://github.com/shusain93/Andromeda-iMessage) however it is still possible to use independently. This project uses GCDWebserver for network requests. You can more or less deduce the API from the `ViewController.swift` in the code blocks. 

This setup reads the SQL database that the OSX iMessage app uses and so theoretically Apple will break it every time they update iMessage. Further, to send I am using keyboard shortcuts so you need both a sufficiently fast computer to be able handle UI automation (i.e. if it freezes all the time it'll be very unreliable). To combat the troubles of UI scripting, I have set it up to verify a message has been sent and if it fails it will notify over the notification setup your built in IFTTT. There are a few bugs in this: iOS 10 iMessage separates links at the start and end of your messages into brand new, separate ones and so the exact message text can't be found and so worst case scenario you end up accidentally spamming the same message 3 times and getting an error message back.

***You will need to run this on a computer which can act as a server and will never sleep***. If your server sleeps/goes offline not only will you not know about your texts, they will be delivered through iMessage and you won't be able to access any of them while you are away. If you get fired because my server failed create an issue and don't blame me.

### Features

1. Getting and sending messages
2. **GROUP CHATS!** This includes named and unnamed iMessage group chats (i.e. Person 1, person 2, person 3 AND "The Sushi Brigade")
3. Loading of attachments of any type. *todo:* allow sending!

### Configuration/Setup!

To achieve notifications for the AndromedaB application I have setup IFTTT notifications through the maker API. You need to generate a token [here](https://ifttt.com/maker_webhooks) and then rename `CONFIG_EXAMPLE.plist` to just `CONFIG.plist`. Fill in your token and also add a protection key. This is just a password/API key for your server, don't ever share it otherwise nasties can steal your messages! Once you've got the server running, configure an IFTTT maker recipe with the event name as `imessageRecieved`

1. `Value1`: this is the from field
2. `Value2`: this is the message content
3. `Value3`: this is an advanced field which contains a search keyword which if included as the link field of a Pushbullet link push in the format `http://i.eu/{{Value3}}/` (copy and paste!) it will automatically launch the application to the correct conversation if clicked as a notification. http://i.eu will never resolve to anything (on char TLDs are banned) but it has the advantage of being very short so it won't take up much space in the notification tray. 

### Getting it to stay running

If you're using this everyday, I recommend using a `while true; do ./path/to/binary/of/iMessageProxy; done` to make sure that when it does crash (attachments are still odd) it'll relaunch instantly.