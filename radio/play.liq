#!/usr/bin/liquidsoap

#enable STDOUT logging for upstart
set("log.stdout", true)

#enable telnet server
set("server.telnet", true)
set("server.telnet.port",8001)
set("server.telnet.bind_addr","127.0.0.1")

#define two stations, station2 is fallback stream for station1
station1	= input.http(id="station1", "http://init/liquidsoap")
station2	= input.http(id="station2", "http://init/liquidsoap")

#define net outage channel
announce	= mksafe(single(id="announce",   "say:unstable network!"));
net_outage 	= mksafe(amplify(0.1,add([sine(),noise()])));
#net_outage 	= mksafe(single(id="net_outage", "/home/radio/sound/net_outage.ogg")) #play a file instead of sine signal

#announce net outage every minute
net_outage      = smooth_add(
	normal=net_outage,
	special=switch([
		( { 0s }, announce )
	])
)

#set station2 as fallback for station1 and net_outage as fallback for station2
radio = fallback(
	id="http_input fallback",
	track_sensitive=false,
	[
		station1,
		station2,
		net_outage
	]
)

radio=mksafe(radio)

#soundcard out
out(radio)

#output stream - http://localhost:8000/radio
output.harbor(
	protocol="http", port=8000, mount="/radio",
	format="audio/ogg",	
	%vorbis.cbr(samplerate=44100, channels=2, bitrate=160), 
	radio 
)


#avoid buffer overruns
output.dummy(fallible=true, station1);
output.dummy(fallible=true, station2);

