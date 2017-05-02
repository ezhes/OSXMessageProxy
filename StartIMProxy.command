#Move into the script location. We have a precondition that the app is here
cd "${0%/*}"
#Prepare our data folder if it's not there
mkdir -p ~/OSXMessageProxyLogs/crashes
#Run loop
while true; do 
	echo "Starting server at `date`" >>  ~/OSXMessageProxyLogs/`date +%Y-%m-%d`.txt;
	#Launch MessageProxy but filter out the adressbook spam
	MessageProxy.app/Contents/MacOS/MessageProxy 2>&1 | grep -v "dynamic accessors" | tee -a ~/OSXMessageProxyLogs/`date +%Y-%m-%d`.txt;
	echo "Server stopped/crashed at `date`" >>  ~/OSXMessageProxyLogs/`date +%Y-%m-%d`.txt;
	#We quit, check for crash reports, and copy them
	cp ~/Library/Logs/DiagnosticReports/MessageProxy* ~/OSXMessageProxyLogs/crashes
	#Remove them so we don't copy a million of them
	rm ~/Library/Logs/DiagnosticReports/MessageProxy*
	done
