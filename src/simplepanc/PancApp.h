#ifndef PANC_APP_H
#define PANC_APP_H

enum{ AM_CHANNEL=6};
enum{
	MAX_RETRY=3,
	ACK_TO=30, //MILLISECONDS
	MAX_NODES=8
};
	

typedef struct topic{
	uint8_t topicId;
	uint8_t qos;
	uint8_t seqn;
	bool subscribed;
} topic;

typedef struct node{
	uint8_t nodeId;
	topic topics[3];
	uint8_t pubsn;	
} node;

enum topicIDs{
	TEMPERATURE=0,
	HUMIDITY=1,
	LUMINOSITY=2
};

#endif /* PANC_APP_H */
