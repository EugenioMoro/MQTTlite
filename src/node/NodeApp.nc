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
	//this is sometimes useful
	bool lastMessageAcked=FALSE;
	
	//this is for random topic subscribing
	uint8_t currentTopic=0;
	uint8_t currentQos;
	
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
	
		void sendSubscribe(uint8_t topicId, bool qos) {
		if( ! radioIsBusy) {
			//build packet
			SubscribePKT * subpkt = (SubscribePKT * )(call Packet.getPayload(&pkt,
					sizeof(SubscribePKT)));
			subpkt->pktId = SUBSCRIBE_ID;
			subpkt->nodeId = TOS_NODE_ID;
			subpkt->topicId = topicId;
			subpkt->qos = qos;
			//message has to be acked
			waitForAck = TRUE;
			if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(SubscribePKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
			printf("Node %u: Sending subscribe for topic %u with QoS %u\n", TOS_NODE_ID, topicId, qos);
		}
	}
	
	void randomSubscribe(){
		//if attempt to subscribe has been done 3 times (1 attempt per topic) then set subscribed and stop
		if(currentTopic>2){
			nodeState=SUBSCRIBED;
			return;
		}
		if(call Random.rand16()%2==1){//RANDOMLY DECIDES IF SUBSCRIBE OR NOT, if subscribing then send the new sub message else recursive
			currentQos=(call Random.rand16()%2);
			sendSubscribe(currentTopic, currentQos);
		}
	}
	
	task void triggerSub(){
		nodeState=SUBSCRIBING;
		randomSubscribe();
	}
	
	task void triggerSubResend(){
		randomSubscribe();
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
			case SUBSCRIBING:sendSubscribe(currentTopic,currentQos); return; 
		}
	}
	event message_t * Receive.receive(message_t * msg, void * payload, uint8_t len) {
		//printf("Message received at node\n");
		if(len == sizeof(ConnackMessagePKT)) {
			ConnackMessagePKT* connackPKT = (ConnackMessagePKT *) payload;
			if(connackPKT->pktID == CONNACK_ID){// && connackPKT->nodeID == TOS_NODE_ID) {
				nodeState = CONNECTED;
				call ResendTimer.stop();
				printf("NODE %u: CONNACK received, node connected\n", TOS_NODE_ID);
				waitForAck=FALSE;
				post triggerSub();
				return msg;
			}
		}
		if(len==sizeof(SubackPKT)){
			SubackPKT* subackPkt = (SubackPKT *) payload;
			if(subackPkt->pktId==SUBACK_ID && subackPkt->nodeId==TOS_NODE_ID){
				call ResendTimer.stop();
				waitForAck=FALSE;
				if(nodeState==SUBSCRIBING){
					currentTopic++;
					post triggerSubResend();
					}
			}
		}
	return msg; }
}