#ifndef PANC_APP_H
#define PANC_APP_H

enum{ AM_CHANNEL=6};

typedef struct topic{
	uint8_t topicId;
	bool qos;
	bool subscribed;
} topic;

typedef struct node{
	uint8_t nodeId;
	topic topics[3];	
} node;

enum topicIDs{
	TEMPERATURE=1,
	HUMIDITY=2,
	LUMINOSITY=3
};

#endif /* PANC_APP_H */
