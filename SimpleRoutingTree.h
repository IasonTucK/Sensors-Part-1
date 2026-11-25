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
	TIMER_FAST_PERIOD=205, // 1/5 second
	TIMER_LEDS_MILLI=1024, // 1 second

	// ΠΡΟΣΘΗΚΗ: Το χρονικό παράθυρο (slot) κάθε επιπέδου του δέντρου μέσα στην εποχή (~0.1 sec).
	TIMER_SLOT_MILLI=100,

	// ΠΡΟΣΘΗΚΗ: Αίτηση ένταξης στο δέντρο (JoinRequest). Ένας κόμβος που δεν έχει πατέρα JOIN_WAIT_MILLI (~3 sec) μετά το
	// boot (δηλαδή έχασε το routing μήνυμα του γείτονά του), ζητάει από τους γείτονές του να ξαναστείλουν το routing μήνυμά τους.
	// Το ξαναζητάει το πολύ JOIN_MAX_TRIES φορές, ώστε ένας κόμβος χωρίς γείτονες να μη στέλνει για πάντα.
	JOIN_WAIT_MILLI=3072,
	JOIN_MAX_TRIES=3,
};

/*
TODO: Εδώ δηλώνουμε τα είδη μηνυμάτων που θέλουμε να υπάρχουν':

NOTE: Αν προσθέω τύπο μηνύματος, να το προσθέσω και στο enum παραπάνω με έναν κωδικό.
NOTE: Μέγιστο μέγεθος μηνύματος 29 bytes.
*/
typedef nx_struct RoutingMsg
{
	// ΑΦΑΙΡΕΣΗ: 'nx_uint16_t senderID;' (2 bytes). Ο αποστολέας υπάρχει ήδη στην κεφαλή του πακέτου
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

// VAR = sumSq/count - (sum/count)^2. Το sumSq φτάνει μέχρι 100 * 100^2 = 1000000 > 65535, άρα θέλει 32 bits.
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
