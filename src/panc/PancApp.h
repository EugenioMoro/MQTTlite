#ifndef PANC_APP_H
#define PANC_APP_H

enum{ AM_CHANNEL=6};

typedef struct topic{
	uint8_t topicId;
	uint8_t qos;
	bool subscribed;
} topic;

typedef struct node{
	uint8_t nodeId;
	topic topics[3];	
} node;

enum topicIDs{
	TEMPERATURE=0,
	HUMIDITY=1,
	LUMINOSITY=2
};

#endif /* PANC_APP_H */
