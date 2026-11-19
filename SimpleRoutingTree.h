#ifndef SIMPLEROUTINGTREE_H
#define SIMPLEROUTINGTREE_H

/*
Όταν θέλουμε να στείλουμε κάποιο μήνυμα, θα πρέπει να ορίσουμε κάπου ένα 'active message ID' (ακέραιος), το οποίο μπαίνει στην κεφαλή του μηνύματος. όταν ένας κόμβος θα λάβει το μήνυμα, θα πετάξει ένα 'eventReceived' για αυτό το 'active message ID'.
Στο enum ορίζουμε τα διαθέσιμα 'active message IDs'. Πρέπει να είναι μοναδικά των 8-bits (δλδ μέχρι 255)
*/

enum{
	/*
	Η ουρά των μηνυμάτων ενός κόμβου είναι:
	1) Το πολύ 5 προς αποστολή (αν και πρακτικά θα έχω μόνο 1)
	2) Το πολύ 16 προς παραλαβή
	*/
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=16,

	AM_ROUTINGMSG=22,

	AM_AGGREGATEMSG = 23, // Νέο 'active message ID'

	/* Μεταβλητές για κάποιους μετρητές. Οι μετρητές είναι σε milliseconds.
	   ΠΡΟΣΟΧΗ: 1sec = 1024 μονάδες
	*/
	TIMER_FAST_PERIOD=0.2*1024, // 1/5 second
	TIMER_LEDS_MILLI=1024, // 1 second
};

/*
TODO: Εδώ δηλώνουμε τα είδη μηνυμάτων που θέλουμε να υπάρχουν

NOTE: Αν προσθέω τύπο μηνύματος, να το προσθέσω και στο enum παραπάνω με έναν κωδικό.
NOTE: Μέγιστο μέγεθος μηνύματος 29 bytes.
*/
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t queryType; // Το 'queryType' που επέλεξε ο κόμβος 0
	nx_uint8_t epochSec; // Η διακεια εποχής που επέλεξε ο κόμβος 0
	nx_uint8_t depth;
	
} RoutingMsg;

typedef nx_struct SumAggMsg
{
	nx_uint16_t sum;
	
} SumAggMsg;

typedef nx_struct AvgAggMsg
{
	nx_uint16_t sum;
	nx_uint8_t count;
	
} AvgAggMsg;

typedef nx_struct VarAggMsg
{
	nx_uint16_t sum;
	nx_uint32_t sumSq;
	nx_uint8_t count;
	
} VarAggMsg;

typedef nx_struct MaxAggMsg
{
	nx_uint8_t maxVal;
	
} MaxAggMsg;

#endif
