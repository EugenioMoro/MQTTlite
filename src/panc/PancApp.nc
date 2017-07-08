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
	node nodes[255];
	uint8_t nodeCount=0;
	uint8_t i;

	void addNewNode(uint8_t nodeId){
		nodeCount++;
		nodes[nodeCount-1].nodeId=nodeId;
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

	event void Boot.booted(){
		call Leds.led0On();
		call AMControl.start();
		printf("Pan Coordinartor %u: Booted\n", TOS_NODE_ID);
	}

	event void ResendTimer.fired(){
		// TODO Auto-generated method stub
	}

	event void GeneralPurposeTimer.fired(){
		// TODO Auto-generated method stub
	}

	event void AMSend.sendDone(message_t *msg, error_t error){
		radioIsBusy=FALSE;
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
		return msg;
	}
}