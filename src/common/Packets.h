#ifndef PACKETS_H
#define PACKETS_H

typedef nx_struct ConnectMessagePKT {
	nx_uint8_t pktID;
	nx_uint8_t nodeID;
} ConnectMessagePKT;

typedef nx_struct ConnackMessagePKT{
	nx_uint8_t pktID;
	nx_uint8_t nodeID;
	nx_uint8_t pancID;
} ConnackMessagePKT;

typedef nx_struct SubscribePKT{
	nx_uint8_t pktId;
	nx_uint8_t nodeId;
	nx_uint8_t topicId;
	nx_uint8_t qos;
} SubscribePKT;

typedef nx_struct SubackPKT{
	nx_uint8_t pktId;
	nx_uint8_t nodeId;
} SubackPKT;

enum {
	CONNECT_ID = 1,
	CONNACK_ID = 2,
	SUBSCRIBE_ID=3,
	SUBACK_ID=4
};

#endif /* PACKETS_H */
