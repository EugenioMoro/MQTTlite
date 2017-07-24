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
	
	//this boolean is checked at the sendDone event, if it's true then the resend timer will be set
	bool waitForAck=FALSE;
	uint8_t i;
	uint8_t pancAddr;
	
	//this is for random topic subscribing
	uint8_t currentTopic=0;
	uint8_t currentQos;
	
	//this data structure is to store to which topic the node is sub and what qos level 
	//the first bool refers to subscription and second bool relates to qos
	//this data structure is initialized with 0es, if a node will not subscribe to a topic then there's no need to change it 
	bool topics[3][2]= {{0,0},{0,0},{0,0}};
	
	//this is te topic to which the node will publish
	uint8_t selfTopic;
	//this is the data to publish and the current qos(qos changes randomly at every publish)
	uint16_t data;
	uint8_t pubQos;
	
	//this function sends the connect message in broadcast
	void SendConnect() {
		printf("NODE %u: Sending connect message\n", TOS_NODE_ID);
		nodeState=CONNECTING;
		if(!radioIsBusy) {
			//build packet and bind it to node's packet pkt''
			ConnectMessagePKT * connpkt = (ConnectMessagePKT * )(call Packet.getPayload(&pkt, sizeof(ConnectMessagePKT)));
			connpkt->pktID = CONNECT_ID;
			connpkt->nodeID = (uint8_t)TOS_NODE_ID;
			//this message should be acknowledged
			waitForAck=TRUE;
			//try and send the packet
			if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(ConnectMessagePKT)) == SUCCESS) {
				radioIsBusy=TRUE;
			}
		}
	}
	
	//this function is called to send a puback message
	void sendPuback(){
		printf("NODE %u: Sending puback message\n", TOS_NODE_ID);
		if(!radioIsBusy){
			PubackPKT* pubpkt = (PubackPKT*) (call Packet.getPayload(&pkt, sizeof(SubackPKT)));
			pubpkt->pktId=PUBACK_ID;
			pubpkt->nodeId=(uint8_t)TOS_NODE_ID;
			if(call AMSend.send(pancAddr, &pkt, sizeof(PubackPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
		}
	}
	
	//this function publishes a pre-filled data variable with random qos to the self-topic
	void publishSomething(){
		PublishPKT * pubpkt = (PublishPKT *)(call Packet.getPayload(&pkt, sizeof(PublishPKT)));
		pubpkt->pktId=PUBLISH_ID;
		pubpkt->nodeId=(uint8_t)TOS_NODE_ID;
		pubpkt->topicId=selfTopic;
		pubpkt->data= data;
		if(call Random.rand16()%2){
			currentQos=1;
			pubpkt->qos=1;
			pubQos=1;
			waitForAck=TRUE;
			printf("NODE %u: publishing to topic %u with Qos 1\n", TOS_NODE_ID, selfTopic);
			nodeState=PUBLISHING;
		} else {
			currentQos=0;
			pubpkt->qos=0;
			pubQos=0;
			printf("NODE %u: publishing to topic %u with Qos 0\n", TOS_NODE_ID, selfTopic);
		}
		if(call AMSend.send(pancAddr, &pkt, sizeof(PublishPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
	}
	//this should be called each time the node resends a publish message, it will use the chosen qos and not a new random one
	void resendPublish(){
		PublishPKT * pubpkt = (PublishPKT *)(call Packet.getPayload(&pkt, sizeof(PublishPKT)));
		pubpkt->pktId=PUBLISH_ID;
		pubpkt->nodeId=(uint8_t)TOS_NODE_ID;
		pubpkt->topicId=selfTopic;
		pubpkt->data= data;
		if(currentQos){
			pubpkt->qos=1;
			pubQos=1;
			waitForAck=TRUE;
			printf("NODE %u: publishing to topic %u with Qos 1\n", TOS_NODE_ID, selfTopic);
			nodeState=PUBLISHING;
		} else {
			pubpkt->qos=0;
			pubQos=0;
			printf("NODE %u: publishing to topic %u with Qos 0\n", TOS_NODE_ID, selfTopic);
		}
		if(call AMSend.send(pancAddr, &pkt, sizeof(PublishPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
	}
	
	//this function will send a subscribe message to a given topic and qos
	//it has also the task to update the data structure keeping trace of the topics to which the node is subscribed
	void sendSubscribe(uint8_t topicId, bool qos) {
		topics[topicId][0] = TRUE;
		topics[topicId][1] = qos;
		if( ! radioIsBusy) {
			//build packet
			SubscribePKT * subpkt = (SubscribePKT * )(call Packet.getPayload(&pkt,sizeof(SubscribePKT)));
			subpkt->pktId = SUBSCRIBE_ID;
			subpkt->nodeId = (uint8_t) TOS_NODE_ID;
			subpkt->topicId = topicId;
			subpkt->qos = qos;
			//message needs to be acked
			waitForAck = TRUE;
			if(call AMSend.send(pancAddr, &pkt, sizeof(SubscribePKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
			printf("NODE %u: Sending subscribe for topic %u with QoS %u\n", TOS_NODE_ID,
					topicId, qos);
		}
	}
	
	//this function will set the publish timer to an hard-coded interval
	//it will also make sure that each node has a phase difference of 1 second
	//it has been wrapped into a function for readability
	void startPublishing(){
		call PublishTimer.startPeriodicAt(TOS_NODE_ID*1000, PUBLISH_INTERVAL); //gives some random phase to the publish messages
	}
	
	//this task will randomly subscribe to each topic
	//note that this function works for a topic that is set globally: for the topic set in current topic the function will decide
	task void randomSubscribe(){
		//if attempt to subscribe has been done 3 times (1 attempt per topic) then set subscribed and stop
		if(currentTopic>2){
			nodeState=SUBSCRIBED;
			printf("NODE %u: subscribe procedure done, starting publish procedure\n", TOS_NODE_ID);
			startPublishing();
			return;
		}
		//RANDOMLY DECIDES IF SUBSCRIBE OR NOT, if subscribing then send the new sub message, else recurse yourself after incrementing the topic (choose for next topic) 
		//the current topic is not incremented if a subscribe message is sent(because we need to wait for an ack)
		//NOTE: the choices are biased for testing purpose
		if(1-((call Random.rand16()%2)*(call Random.rand16()%2))){
			currentQos=(uint8_t)(1-((call Random.rand16()%2)*(call Random.rand16()%2)));
			sendSubscribe(currentTopic, currentQos);
		} else { currentTopic++; post randomSubscribe();}
	}
	
	//this function should reflect anything that the node could do with the new received data
	//here is only print, but could be anything. NOTE:if heavy processing, then should be a task
	void processData(uint16_t val, uint8_t topicId){
		printf("NODE %u: new data '%u' received for topic %u\n", TOS_NODE_ID, data, topicId);
	}
	
	//this task il called when the node has connected to the panc and the subscribe procedure should start
	task void triggerSub(){
		nodeState=SUBSCRIBING;
		post randomSubscribe();
	}
	
	//this task is called if an ack for a subscribe message is not received
	task void triggerSubResend(){
		post randomSubscribe();
	}
	

	event void Boot.booted(){
		call Leds.led0On();
		call AMControl.start();
		nodeState = ORPHAN;
		//choose the topic to which the node will publish
		selfTopic=(uint8_t)(call Random.rand16()%3);
		printf("NODE %u: Booted\n", TOS_NODE_ID);
	}

	event void AMControl.stopDone(error_t error){
		// TODO Auto-generated method stub
	}

	//if successful, start the connect procedure
	event void AMControl.startDone(error_t error){
	if (error == SUCCESS) {
		SendConnect();
    } else {
    	call AMControl.start();
    }
	}

	//after the message is sent, we check if this message requires an ack, if so: set a timer
	//this is done beacuse we want the timer to start only if and after a successful transmission
	event void AMSend.sendDone(message_t *msg, error_t error){
		if(waitForAck){
			call ResendTimer.startOneShot(ACK_TO);
		}
		radioIsBusy=FALSE;
	}

	//here we have a ack timeout, we switch the current state of the node and thus decide which message should be resent
	event void ResendTimer.fired(){
		printf("NODE %u: Ack not received, resending...\n", TOS_NODE_ID);
		switch (nodeState){
			case CONNECTING:SendConnect(); return;
			case SUBSCRIBING:sendSubscribe(currentTopic,currentQos); return;
			case PUBLISHING:resendPublish(); return; //note that data to publish is consistent at each resend and set globally when it sends the first message
			default: return;
		}
	}
	event message_t * Receive.receive(message_t * msg, void * payload, uint8_t len) {
		//printf("Message received at node\n"); //debug reasons
		
		//if it's a connack then set the panc address, stop the timer, set the state t connected and start the subscribe procedure
		if(len == sizeof(ConnackMessagePKT)) {
			ConnackMessagePKT* connackPKT = (ConnackMessagePKT *) payload;
			if(connackPKT->pktID == CONNACK_ID && connackPKT->nodeID == TOS_NODE_ID) {
				call ResendTimer.stop();
				nodeState = CONNECTED;
				printf("NODE %u: CONNACK received, node connected\n", TOS_NODE_ID);
				waitForAck=FALSE;
				pancAddr=connackPKT->pancID;
				post triggerSub();
				return msg;
			}
		}
		
		//if a suback is received, then continue the subscribe procedure 
		if(len==sizeof(SubackPKT)){
			SubackPKT* subackPkt = (SubackPKT *) payload;
			if(subackPkt->pktId==SUBACK_ID && subackPkt->nodeId==TOS_NODE_ID){
				call ResendTimer.stop();
				printf("NODE %u: SUBACK received\n", TOS_NODE_ID);
				waitForAck=FALSE;
				if(nodeState==SUBSCRIBING){ //possibly useless, should protect from  a duplicated ack 
					currentTopic++;
					post randomSubscribe();
					}
			}
		}
		
		//simply reset the node state to idle (subscribed is considered as idle)
		if(len==sizeof(PubackPKT)){
			PubackPKT* puback = (PubackPKT*) payload;
			if(puback->pktId==PUBACK_ID && puback->nodeId==TOS_NODE_ID){
				call ResendTimer.stop();
				printf("NODE %u: PUBACK received\n", TOS_NODE_ID);
				nodeState=SUBSCRIBED;
				waitForAck=FALSE;
			}
		}
		
		//the node receives a publish packet
		if(len==sizeof(PublishPKT)){
			PublishPKT* pubpkt = (PublishPKT*) payload;
			//if the node is subscribed to this topic then deal with the packet
			if(topics[pubpkt->topicId][0]){
				printf("NODE %u: Received publish from panc\n", TOS_NODE_ID);
				//if qos is 1 then send puback
				if(topics[pubpkt->topicId][1]) sendPuback();
			} else {
			printf("NODE %u: Received publish but I'm not subscribed to topic %u\n", TOS_NODE_ID, pubpkt->topicId); 
			return msg;
			}
			
		}
			
	return msg; }
	
	//this event starts the publish procedure
	event void PublishTimer.fired(){
		if(nodeState==PUBLISHING){
			printf("NODE %u: New data is available to publish, discarding old data\n", TOS_NODE_ID);
			call ResendTimer.stop();
			waitForAck=FALSE;
		}
		//a random data is set globally, this means that the data is consistent at each resend if the qos for this pub is 1
		data = call Random.rand16();
		publishSomething();
	}
}