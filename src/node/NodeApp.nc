#include <Timer.h>
#include "NodeApp.h"
#include "../common/Packets.h"
module NodeApp{
	uses interface Boot;
	uses interface Leds;
	uses interface Timer<TMilli> as GeneralPurposeTimer;
	uses interface Timer<TMilli> as ResendTimer;
	uses interface Packet;
	uses interface AMPacket;
	uses interface AMSend;
	uses interface SplitControl as AMControl;
	uses interface Random;
	uses interface Receive;
}
implementation{
	message_t pkt;
	nodeStates nodeState;
	bool radioIsBusy=FALSE;
	bool waitForAck=FALSE;
	uint8_t topics
	
	void SendConnect() {
		printf("NODE %u: Sending connect message\n", TOS_NODE_ID);
		nodeState=CONNECTING;
		if(!radioIsBusy) {
			//build packet and bind it to node's packet pkt''
			ConnectMessagePKT * connpkt = (ConnectMessagePKT * )(call Packet.getPayload(&pkt, sizeof(ConnectMessagePKT)));
			connpkt->pktID = CONNECT_ID;
			connpkt->nodeID = TOS_NODE_ID;
			//this message should be acknowledged
			waitForAck=TRUE;
			//try and send the packet
			if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(ConnectMessagePKT)) == SUCCESS) {
				radioIsBusy=TRUE;
			}
		}
	}
	
	void sendSubscribe(uint8_t topicId){
		
	}
	
			
	event void GeneralPurposeTimer.fired(){
		
	}

	event void Boot.booted(){
		call Leds.led0On();
		call AMControl.start();
		nodeState = ORPHAN;
		printf("Mote %u: Booted\n", TOS_NODE_ID);
	}

	event void AMControl.stopDone(error_t error){
		// TODO Auto-generated method stub
	}

	event void AMControl.startDone(error_t error){
	if (error == SUCCESS) {
		SendConnect();
    } else {
    	call AMControl.start();
    }
	}

	event void AMSend.sendDone(message_t *msg, error_t error){
		if(waitForAck){
			call ResendTimer.startOneShot(call Random.rand16() %4000);
		}
		radioIsBusy=FALSE;
	}


	event void ResendTimer.fired(){
		printf("NODE %u: Ack not received, resending...\n", TOS_NODE_ID);
		switch (nodeState){
			case CONNECTING:SendConnect(); return;
			case SUBSCRIBING: return; 
		}
	}
	event message_t * Receive.receive(message_t * msg, void * payload, uint8_t len) {
		printf("Message received at node\n");
		if(len == sizeof(ConnackMessagePKT)) {
			ConnackMessagePKT* connackPKT = (ConnackMessagePKT *) payload;
			if(connackPKT->pktID == CONNACK_ID){// && connackPKT->nodeID == TOS_NODE_ID) {
				nodeState = CONNECTED;
				call ResendTimer.stop();
				printf("NODE %u: CONNACK received, node connected\n", TOS_NODE_ID);
				waitForAck=FALSE;
			}
		}
	return msg; }
}