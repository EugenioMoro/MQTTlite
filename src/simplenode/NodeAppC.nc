#include "printf.h"
#include "NodeApp.h"

configuration NodeAppC{
}
implementation{
	components MainC;
	components LedsC;
	components NodeApp as App;
	components new TimerMilliC() as GeneralPurposeTimer;
	components new TimerMilliC() as ResendTimer;
	components RandomC;
	components SerialPrintfC;
	components ActiveMessageC;
	components new AMSenderC(AM_CHANNEL);
	components new AMReceiverC(AM_CHANNEL);
	
		
	App.Boot -> MainC;
	App.Leds -> LedsC;
	App.PublishTimer -> GeneralPurposeTimer;
	App.ResendTimer -> ResendTimer;
	App.Random -> RandomC;
	App.Packet -> AMSenderC;
	App.AMPacket -> AMSenderC;
	App.AMSend -> AMSenderC;
	App.AMControl -> ActiveMessageC;
	App.Receive -> AMReceiverC;
}