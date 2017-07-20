#include <Timer.h>
#include "NodeApp.h"
#include "../common/Packets.h"
module NodeApp{
	uses interface Boot;
	uses interface Leds;
	uses interface Timer<TMilli> as PublishTimer;
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
	uint8_t i;
	//this is sometimes useful
	bool lastMessageAcked=FALSE;
	
	//this is for random topic subscribing
	uint8_t currentTopic=0;
	uint8_t currentQos;
	
	//this data structure is for storing to which topic the node is sub and what qos level 
	//the first bool realtes to subscription and second bool relates to qos
	//this data structure is initialized with 0es and is lazy 
	bool topics[3][2]= {{0,0},{0,0},{0,0}};
	
	
	//publish related
	uint8_t selfTopic;
	uint8_t pubSN=0;
	uint16_t data;
	uint8_t pubQos;
	
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
	
	void publishSomething(){
		PublishPKT * pubpkt = (PublishPKT *)(call Packet.getPayload(&pkt, sizeof(PublishPKT)));
		pubpkt->pktId=PUBLISH_ID;
		pubpkt->nodeId=TOS_NODE_ID;
		pubpkt->topicId=selfTopic;
		pubpkt->data= data;
		pubpkt->pubsn=pubSN;
		if(call Random.rand16()%2){
			pubpkt->qos=1;
			pubQos=1;
			waitForAck=TRUE;
			printf("NODE %u: publishing to topic %u with Qos 1 - SN %u\n", TOS_NODE_ID, selfTopic, pubSN);
			nodeState=PUBLISHING;
		} else {
			pubpkt->qos=0;
			pubQos=0;
			printf("NODE %u: publishing to topic %u with Qos 0\n", TOS_NODE_ID, selfTopic);
		}
		if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(PublishPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
	}
	
		void sendSubscribe(uint8_t topicId, bool qos) {
			topics[topicId][0]=TRUE;
			topics[topicId][1]=qos;
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
	task void startPublishing(){
		call PublishTimer.startPeriodic(5000);
	}
	void randomSubscribe(){
		//if attempt to subscribe has been done 3 times (1 attempt per topic) then set subscribed and stop
		if(currentTopic>2){
			nodeState=SUBSCRIBED;
			printf("NODE %u: subscribe procedure done, starting publish procedure\n", TOS_NODE_ID);
			post startPublishing();
			return;
		}
		if(1-((call Random.rand16()%2)*(call Random.rand16()%2)*(call Random.rand16()%2))){//call Random.rand16()%2==1){//RANDOMLY DECIDES IF SUBSCRIBE OR NOT, if subscribing then send the new sub message else recursive
			currentQos=(1-((call Random.rand16()%2)*(call Random.rand16()%2)));
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
	

	event void Boot.booted(){
		call Leds.led0On();
		call AMControl.start();
		nodeState = ORPHAN;
		selfTopic=(call Random.rand16()%3);
		printf("Node %u: Booted\n", TOS_NODE_ID);
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
			call ResendTimer.startOneShot(100 + call Random.rand16() %4000);
		}
		radioIsBusy=FALSE;
	}


	event void ResendTimer.fired(){
		printf("Node %u: Ack not received, resending...\n", TOS_NODE_ID);
		switch (nodeState){
			case CONNECTING:SendConnect(); return;
			case SUBSCRIBING:sendSubscribe(currentTopic,currentQos); return;
			case PUBLISHING:publishSomething(); return;
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
				printf("NODE %u: SUBACK received\n", TOS_NODE_ID);
				waitForAck=FALSE;
				if(nodeState==SUBSCRIBING){
					currentTopic++;
					post triggerSubResend();
					}
			}
		}
		if(len==sizeof(PubackPKT)){
			PubackPKT* puback = (PubackPKT*) payload;
			if(puback->pktId==PUBACK_ID && puback->nodeId==TOS_NODE_ID){
				call ResendTimer.stop();
				printf("NODE %u: PUBACK received\n", TOS_NODE_ID);
				nodeState=SUBSCRIBED;
				waitForAck=FALSE;
			}
		}
	return msg; }

	event void PublishTimer.fired(){
		if(nodeState==PUBLISHING){
			printf("NODE %u: Cannot publish: node is busy\n", TOS_NODE_ID);
			return;
		}
		if(pubQos) pubSN++;
		data = call Random.rand16();
		publishSomething();
	}
}