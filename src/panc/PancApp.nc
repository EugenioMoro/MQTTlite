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
	node nodes[MAX_NODES];
	uint8_t nodeCount=0;
	uint8_t i;
	bool waitForAck=FALSE;
	
	//this variable stores the sequence number for each topic in relay context, SN should be incremented at each data relay 
	uint8_t topicSN[3] = {0};
	
	//this is the current publish data packet to be relayed to all the 1-qos nodes
	PublishPKT* currentPublishPkt;
	
	//this is the next node to be unicasted
	uint8_t nextNode=0;
	//this is the counter for the unicast round trial
	uint8_t roundCount=0;
	
	void broadcastData(uint8_t topicId, uint16_t data){
		if(!radioIsBusy){
			PublishPKT* sendpkt = (PublishPKT * )(call Packet.getPayload(&pkt, sizeof(PublishPKT)));
			//increment sequence number for that topic id
			topicSN[topicId]++;
			//build the packet
			sendpkt->pktId=PUBLISH_ID;
			sendpkt->nodeId=TOS_NODE_ID;
			sendpkt->topicId=topicId;
			sendpkt->data=data;
			sendpkt->pubsn=topicSN[topicId];
			
			if(call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(PublishPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			} else printf("failed to send in broadcastData function\n");
			printf("PANC: data broadcasted for topic %u and SN %u\n", topicId, topicSN[topicId]);
		}
	}
	
	bool choseNextNode(){
		if(roundCount>MAX_RETRY-1){
			printf("Max retry exceeded or all the nodes are serviced: data relay is considered done\n");
			return FALSE;
		}
		//printf("chosenext\n");
		for(i=nextNode; i<MAX_NODES; i++){
			//printf("chosenext for\n");
			//if node has qos 1 and inferior sequence number
			//NOTE: if node is not subscribed, then qos is always 0
			if(nodes[i].topics[currentPublishPkt->topicId].qos==1 && nodes[i].topics[currentPublishPkt->topicId].seqn<topicSN[currentPublishPkt->topicId]){
				nextNode=i;
				//printf("nodefound\n");
				return TRUE;
			}
		}
		//here end of the nodes is reached, we check if max retry is exceeded, if not then start again
		roundCount++;
		//printf("roundcount %u\n", roundCount);
		nextNode=0;
		return choseNextNode();
	}
	
	void sendData(){
		while(radioIsBusy){
			waitForAck=FALSE; //otherwise it will disturb other transmissions
			printf("PANC: radio is busy, waiting...\n");
			call GeneralPurposeTimer.startOneShot(50);
			return;
		}
		if(!radioIsBusy){
			
			PublishPKT* sendpkt = (PublishPKT * )(call Packet.getPayload(&pkt, sizeof(PublishPKT)));
			//build the packet
			//printf("packet built\n");
			sendpkt->pktId=PUBLISH_ID;
			//printf("packet built\n");
			sendpkt->nodeId=nextNode;
			//printf("packet built\n");
			sendpkt->topicId=currentPublishPkt->topicId;
			//printf("packet built\n");
			sendpkt->data=currentPublishPkt->data;
			//printf("packet built\n");
			sendpkt->pubsn=topicSN[currentPublishPkt->topicId];
			//printf("packet built\n");
			if(call AMSend.send(nextNode, &pkt, sizeof(PublishPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
				waitForAck=TRUE;
			} else printf("failed to send message in sendData function\n");
			printf("PANC: data sent to node %u for topic %u and SN %u\n", nextNode, currentPublishPkt->topicId, topicSN[currentPublishPkt->topicId]);
		} else printf("radio busy\n");
	}
	
	//this function triggers a new reliable unicast data transmission for data
	void triggerNewRelayRound(PublishPKT* packet){
		//printf("trigger\n");
		call ResendTimer.stop(); //eventually stop the ack timer
		currentPublishPkt=packet;
		nextNode=0;
		roundCount=0;
		if(choseNextNode()){
			sendData();
		}
		return;
		
	}
	
	void addNewNode(uint8_t nodeId){
		nodeCount++;
		nodes[nodeCount-1].nodeId=nodeId;
		nodes[nodeCount-1].pubsn=1; //first publish sn from node will be one, easier choice 
		//initialize all the topics
		for (i=0; i<3; i++){
			nodes[nodeCount-1].topics[i].topicId=i;
			nodes[nodeCount-1].topics[i].qos=FALSE;
			nodes[nodeCount-1].topics[i].subscribed=FALSE;
		}
		printf("Panc: Node %u added into memory\n", nodes[nodeCount-1].nodeId);
	}
	
	
	void subscribeNode(uint8_t nodeId, uint8_t topicId, uint8_t qos){
		for(i=0; i<=nodeCount; i++){
			if(nodes[i].nodeId==nodeId){
				nodes[i].topics[topicId].qos=qos;
				nodes[i].topics[topicId].subscribed=TRUE;
				printf("PANC: Node %u subscribed to topic %u with qos %u\n", nodeId, topicId, qos);
				return;
			}
		}
		printf("PANC: subscribe error: node not found in memory\n");
	}
	
	void SendConnack(uint8_t addr) {
		printf("PANC %u: Sending connack message\n");
		if( ! radioIsBusy) {
			//build packet and bind it to node's packet pkt''
			ConnackMessagePKT * connpkt = (ConnackMessagePKT * )(call Packet.getPayload(&pkt, sizeof(ConnackMessagePKT)));
			connpkt->pktID = CONNACK_ID;
			connpkt->nodeID = addr;
			connpkt->pancID=TOS_NODE_ID;
			//try and send the packet
			if(call AMSend.send(addr, &pkt, sizeof(ConnackMessagePKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
		}
	}
	
	void sendSuback(uint8_t addr){
		printf("PANC: Sending suback message\n");
		if(!radioIsBusy){
			SubackPKT* subpkt = (SubackPKT*)(call Packet.getPayload(&pkt, sizeof(SubackPKT)));
			subpkt->pktId=SUBACK_ID;
			subpkt->nodeId=addr;
			if(call AMSend.send(addr, &pkt, sizeof(SubackPKT)) == SUCCESS) {
				radioIsBusy = TRUE;
			}
		}
	}
	
	void sendPuback(uint8_t addr, uint8_t pubsn){
		printf("PANC: Sending puback message\n");
		if(!radioIsBusy){
			PubackPKT* pubpkt = (PubackPKT*) (call Packet.getPayload(&pkt, sizeof(SubackPKT)));
			pubpkt->pktId=PUBACK_ID;
			pubpkt->nodeId=addr;
			pubpkt->pubsn=pubsn;
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

	event void ResendTimer.fired(){
		waitForAck=FALSE;
		printf("PANC: ack from node %u not received\n", nextNode);
		if(nextNode==MAX_NODES) nextNode=0; else nextNode++;
		if(choseNextNode()){
			sendData();
		}
	}

	event void GeneralPurposeTimer.fired(){
		waitForAck=TRUE;
		sendData();
	}

	event void AMSend.sendDone(message_t *msg, error_t error){
		//printf("senddone\n");
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
		if(len==sizeof(ConnectMessagePKT)){
			ConnectMessagePKT* connectPKT = (ConnectMessagePKT*) payload;
			if(connectPKT->pktID==CONNECT_ID){
				printf("PanC: received connection message from node %u\n", connectPKT->nodeID);
				SendConnack(connectPKT->nodeID);
				addNewNode(connectPKT->nodeID);
				}
			free(connectPKT);
			return msg;
			}
			if(len==sizeof(SubscribePKT)){
				SubscribePKT* subpkt = (SubscribePKT*) payload;
				if(subpkt->pktId==SUBSCRIBE_ID){
					printf("PANC: received subscribe message from node %u\n", subpkt->nodeId);
					sendSuback(subpkt->nodeId);
					subscribeNode(subpkt->nodeId, subpkt->topicId, subpkt->qos);
				}
			}
			if(len==sizeof(PublishPKT)){
				PublishPKT* pubpkt = (PublishPKT*) payload;
				printf("PANC: received publish message from node %u, data %u\n", pubpkt->nodeId, pubpkt->data);
				if(pubpkt->qos==1){
					//check if data is fresh
					if(pubpkt->pubsn==nodes[pubpkt->nodeId].pubsn){
						nodes[pubpkt->nodeId].pubsn++;
						sendPuback(pubpkt->nodeId, pubpkt->pubsn);
						printf("PANC: received data is new\n");
						//publish logic here
						//broadcastData(pubpkt->topicId, pubpkt->data);
						topicSN[pubpkt->topicId]++;
						triggerNewRelayRound(pubpkt);
					} else{
						printf("PANC: duplicated ack received, SN received is %u but %u was expected\n", pubpkt->pubsn, nodes[pubpkt->nodeId].pubsn);
						sendPuback(pubpkt->nodeId, pubpkt->pubsn);
					}
					
				} else { //if qos is zero
					//broadcastData(pubpkt->topicId, pubpkt->data);
					topicSN[pubpkt->topicId]++;
					triggerNewRelayRound(pubpkt);
				}
					
				}
			if(len==sizeof(PubackPKT)){
				//should first check from which node is this ack, then in case stop the ack timer, will probably need larger timeouts
				PubackPKT* puback = (PubackPKT*) payload;
				if(puback->nodeId==nextNode){
					call ResendTimer.stop();
				}
				//update topic sequence number if needed
				if(nodes[puback->nodeId].topics[currentPublishPkt->topicId].seqn<topicSN[currentPublishPkt->topicId])
					nodes[puback->nodeId].topics[currentPublishPkt->topicId].seqn=topicSN[currentPublishPkt->topicId];
				printf("PANC: puback received from node %u and SN %u\n", puback->nodeId, puback->pubsn);
				
				//then continue the round
				if(choseNextNode()){
					sendData();
				}	
			}
			return msg;
			}
		
	}
