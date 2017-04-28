# MessageProxy: An Open Source iMessage API 

This API is primarily designed to be used with AndromedaB however it is still possible to use independently. This project uses GCDWebserver for network requests. You can more or less deduce the API from the `ViewController.swift` in the code blocks. 

### Features

1. Getting and sending messages
2. **GROUP CHATS!** This includes named and unnamed iMessage group chats (i.e. Person 1, person 2, person 3 AND "The Sushi Brigade")
3. Loading of attachments of any type. *todo:* allow sending!

### Configuration/Setup!

To achieve notifications for the AndromedaB application I have setup IFTTT notifications through the maker API. You need to generate a token [here](https://ifttt.com/maker_webhooks) and then rename `CONFIG_EXAMPLE.plist` to just `CONFIG.plist`. Fill in your token and also add a protection key. This is just a password/API key for your server, don't ever share it otherwise nasties can steal your messages! Once you've got the server running, configure an IFTTT maker recipe with the event name as `imessageRecieved`

1. `Value1`: this is the from field
2. `Value2`: this is the message content
3. `Value3`: this is an advanced field which contains a search keyword which if included as the link field of a Pushbullet link push in the format `http://imessageproxy.andromedab.shusain93:8735/{{Value3}}/` (copy and paste!) it will automatically launch the application to the correct conversation if clicked as a notification.

### Getting it to stay running

If you're using this everyday, I recommend using a `while true; do ./path/to/binary/of/iMessageProxy; done` to make sure that when it does crash (attachments are still odd) it'll relaunch instantly.