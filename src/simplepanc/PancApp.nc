#include "../common/Packets.h"
#include "PancApp.h"

module PancApp{
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
	bool radioIsBusy=FALSE;
	message_t pkt;
	
	//this is a data structure that contains all the information for all the connected nodes
	node nodes[MAX_NODES];
	
	//this acts as an index for the nodes data structure
	uint8_t nodeCount=0;
	uint8_t i;//general iterator
	
	//this boolean is checked at the sendDone event, if it's true then the resend timer will be set
	bool waitForAck=FALSE;
	
	bool oldWaitForAck=FALSE; //i need to backup waitforack when i wait for the radio to be free again
	
	//current publish relay related variables
	uint16_t currentData;
	uint8_t currentNode=0;
	uint8_t currentTopic;
	uint8_t publisherNode;
	uint8_t currentTrials=0;

	
	//all the packets that could be received, in order to keep memory under control (i have had problem of overflows)
	ConnectMessagePKT* connectPKT;
	SubscribePKT* subpkt;
	PublishPKT* pubpkt;
	PubackPKT* puback;
	
	//same thing for all the possible sent packets
	ConnackMessagePKT * connpkt;
	SubackPKT* sendSubpkt;
	PubackPKT* sendPubpkt;
	
	//this functions sends a publish to a specific node, which is globally set elsewhere	
	void sendData(bool needsAck){
		while(radioIsBusy){
			oldWaitForAck=waitForAck; //here we backup the need (or not need) for an ack for this specific publish message
			waitForAck=FALSE; //otherwise it will disturb other transmissions
			printf("PANC: radio is busy, waiting...\n");
			call GeneralPurposeTimer.startOneShot(50); //we keep on waiting until the radio is free (happens a lot that radio is still sending puback)
			return;
		}
		if(!radioIsBusy){
			
			PublishPKT* sendpkt = (PublishPKT * )(call Packet.getPayload(&pkt, sizeof(PublishPKT)));
			//build the packet
			sendpkt->pktId=PUBLISH_ID;
			sendpkt->nodeId=nodes[currentNode].nodeId; //this is the node id of the publisher, this information might be needed by the receiving nodes
			sendpkt->topicId=currentTopic;
			sendpkt->data=currentData;
			if(call AMSend.send(nodes[currentNode].nodeId, &pkt, sizeof(PublishPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
				waitForAck=needsAck;
			} else printf("PANC: failed to send message in sendData function\n");
			printf("PANC: data sent to node %u for topic %u\n", nodes[currentNode].nodeId, currentTopic);
		} else printf("PANC: radio busy\n");
	}
	
	//this task sends (if it should, see below) a publish message to the current node according to the qos it has specified
	task void publishBack(){
		if(currentNode==nodeCount){ //NOTE: current node starts from zero so == is to avoid an offset-by-one error
			printf("PANC: data relay is completed\n");
			return;
		}
		
		if(nodes[currentNode].nodeId!=publisherNode && nodes[currentNode].topics[currentTopic].subscribed){ //if the current node is not the publisher and is subscribed to the topic
			if(nodes[currentNode].topics[currentTopic].qos==1){
				waitForAck=TRUE; //in case radio is busy and sendData doesn't reach to set this to true
				sendData(TRUE);
				currentTrials++;
				return;
			}
			//here is if current node has qos 0
			waitForAck=FALSE;
			sendData(FALSE);
			currentTrials=0;
			currentNode++; //we don't need to wait for an ack, we automatically increase to evaluate the next node and restart the procedure
			post publishBack();
		}
		//this node was not subscribed, skip to the next
		currentNode++;
		post publishBack();
	}	
	
	
	void addNewNode(uint8_t nodeId){
		//check if node is already in memory (need this in case of connack not received from the node)
		for(i=0; i<nodeCount; i++){
			if(nodes[i].nodeId==nodeId){
				printf("PANC: Node %u was already in memory, possible lost connack\n", nodeId);
				return;
			}
		}
		nodeCount++;
		//printf("nodecount %u\n", nodeCount); debug reasons
		nodes[nodeCount-1].nodeId=nodeId;
		//initialize all the topics
		for (i=0; i<3; i++){
			nodes[nodeCount-1].topics[i].topicId=i;
			nodes[nodeCount-1].topics[i].qos=FALSE;
			nodes[nodeCount-1].topics[i].subscribed=FALSE;
		}
		printf("PANC: Node %u added into memory\n", nodes[nodeCount-1].nodeId);
	}
	
	//just set the node's topic
	void subscribeNode(uint8_t nodeId, uint8_t topicId, uint8_t qos){
		for(i=0; i<=nodeCount; i++){ //first search for the node
			if(nodes[i].nodeId==nodeId){
				nodes[i].topics[topicId].qos=qos;
				nodes[i].topics[topicId].subscribed=TRUE;
				printf("PANC: Node %u subscribed to topic %u with qos %u\n", nodeId, topicId, qos);
				return;
			}
		}
		printf("PANC: subscribe error: node %u not found in memory\n", nodeId);
	}
	
	//sends back the connack message; note: connack might collide with something else, this is taken into account in addNewNode
	void SendConnack(uint8_t addr) {
		printf("PANC: Sending connack message\n");
		if( ! radioIsBusy) {
			//build packet and bind it to node's packet pkt''
			connpkt = (ConnackMessagePKT * )(call Packet.getPayload(&pkt, sizeof(ConnackMessagePKT)));
			connpkt->pktID = CONNACK_ID;
			connpkt->nodeID = addr;
			connpkt->pancID=(uint8_t)TOS_NODE_ID;
			//try and send the packet
			if(call AMSend.send(addr, &pkt, sizeof(ConnackMessagePKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
		}
	}
	
	//send the suback message
	void sendSuback(uint8_t addr){
		printf("PANC: Sending suback message\n");
		if(!radioIsBusy){
			sendSubpkt = (SubackPKT*)(call Packet.getPayload(&pkt, sizeof(SubackPKT)));
			sendSubpkt->pktId=SUBACK_ID;
			sendSubpkt->nodeId=addr;
			if(call AMSend.send(addr, &pkt, sizeof(SubackPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
		}
	}
	
	//send the suback message
	void sendPuback(uint8_t addr){
		printf("PANC: Sending puback message\n");
		if(!radioIsBusy){
			sendPubpkt = (PubackPKT*)(call Packet.getPayload(&pkt, sizeof(PubackPKT)));
			sendPubpkt->pktId=PUBACK_ID;
			sendPubpkt->nodeId=addr;
			if(call AMSend.send(addr, &pkt, sizeof(PubackPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
		}
	}	

	event void Boot.booted(){
		call Leds.led0On();
		call AMControl.start();
		printf("Pan Coordinartor %u: Booted\n", TOS_NODE_ID);
	}

	//the panc has an ack timeout only in 1 occasion: puback not received
	//in order to avoid for a node to capture the queue, afer a maximum number of retry the panc gives up
	event void ResendTimer.fired(){
		waitForAck=FALSE;
		if(currentTrials<=MAX_RETRY){
			printf("PANC: ack from node %u not received\n", nodes[currentNode].nodeId);
			post publishBack(); //will retry with the current node
		} else {
			printf("PANC: max trials exceeded for node %u\n", nodes[currentNode].nodeId);
			currentTrials=0;
			currentNode++;
			post publishBack();
		}
		
	}
	
	//this is currently used only to wait for the radio to be free
	event void GeneralPurposeTimer.fired(){
		waitForAck=oldWaitForAck; //restore the queued transmission waitforack value
		sendData(waitForAck);
	}

	//after the message is sent, we check if this message requires an ack, if so: set a timer
	//this is done beacuse we want the timer to start only if and after a successful transmission
	event void AMSend.sendDone(message_t *msg, error_t error){
		//printf("senddone\n"); //debug reasons
		radioIsBusy=FALSE;
		if(waitForAck){
			call ResendTimer.startOneShot(ACK_TO);
		}
	}

	event void AMControl.startDone(error_t error){
		// TODO Auto-generated method stub
	}

	event void AMControl.stopDone(error_t error){
		// TODO Auto-generated method stub
	}

	event message_t * Receive.receive(message_t *msg, void *payload, uint8_t len){
		
		//checking here for the packet id avoids the need to check after in puback
		if(len==sizeof(ConnectMessagePKT)){
			connectPKT = (ConnectMessagePKT*) payload;
			if(connectPKT->pktID==CONNECT_ID){
				printf("PANC: received connection message from node %u\n", connectPKT->nodeID);
				SendConnack(connectPKT->nodeID);
				addNewNode(connectPKT->nodeID);
			}
			return msg;
		}
	
		if(len==sizeof(SubscribePKT)){
			subpkt = (SubscribePKT*) payload;
			if(subpkt->pktId==SUBSCRIBE_ID){
				printf("PANC: received subscribe message from node %u\n", subpkt->nodeId);
				sendSuback(subpkt->nodeId);
				subscribeNode(subpkt->nodeId, subpkt->topicId, subpkt->qos);
			}
		}
		
		if(len==sizeof(PublishPKT)){
			pubpkt = (PublishPKT*) payload;
			printf("PANC: received publish message from node %u, data %u, topic %u\n", pubpkt->nodeId, pubpkt->data, pubpkt->topicId);
			if(pubpkt->qos==1){ //answer to qos
				sendPuback(pubpkt->nodeId);	
			}
	
			//save data and reset current node counter
			currentData=pubpkt->data;
			currentNode=0;
			publisherNode=pubpkt->nodeId;
			currentTopic = pubpkt->topicId;
			currentTrials=0;
			post publishBack();
		}
		
		
		if(len==sizeof(PubackPKT)){
			//should first check from which node is this ack, then in case stop the ack timer, will probably need larger timeouts
			puback = (PubackPKT*) payload;
			if(puback->pktId!=PUBACK_ID) return msg;
			if(puback->nodeId==nodes[currentNode].nodeId){
				call ResendTimer.stop();
				printf("PANC: puback received from node %u\n", puback->nodeId);
				currentNode++;
				currentTrials=0;
				post publishBack();
			}
		}
		return msg;
	}
	
}
