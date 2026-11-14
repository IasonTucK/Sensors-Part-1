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
	2) Το πού 3 προς παραλαβή (εδώ αν έχει πολλά παιδιά μπορεί να γεμίσει, για αυτό πρέπει να επεξεργαζόμαστε γρήγπρα τα δεδομένα και να μην στέλνουν όλα τα παιδιά την ίδια χρονική στιγμη)
	*/
	SENDER_QUEUE_SIZE=5,
	RECEIVER_QUEUE_SIZE=3, // TODO:Αν έχουμε πολλούς γείτονες, να το μεγαλώσουμε λίγο

	AM_SIMPLEROUTINGTREEMSG=21,
	AM_ROUTINGMSG=22,
	AM_NOTIFYPARENTMSG=12,

	/* Μεταβλητές για κάποιους μετρητές. Οι μετρητές είναι σε milliseconds.
	   ΠΡΟΣΟΧΗ: 1sec = 1024 μονάδες
	*/
	SEND_CHECK_MILLIS=70*1024, // 70 seconds
	TIMER_PERIOD_MILLI=150*1024, // 15 seconds
	TIMER_FAST_PERIOD=0.2*1024, // 1/5 second
	TIMER_LEDS_MILLI=1024, // 1 second
};
/*uint16_t AM_ROUTINGMSG=AM_SIMPLEROUTINGTREEMSG;
uint16_t AM_NOTIFYPARENTMSG=AM_SIMPLEROUTINGTREEMSG;
*/

/*
TODO: Εδώ δηλώνουμε τα είδη μηνυμάτων που θέλουμε να υπάρχουν

NOTE: Αν προσθέω τύπο μηνύματος, να το προσθέσω και στο enum παραπάνω με έναν κωδικό.
NOTE: Μέγιστο μέγεθος μηνύματος 29 bytes.
*/
typedef nx_struct RoutingMsg
{
	nx_uint16_t senderID;
	nx_uint8_t depth;
} RoutingMsg;

typedef nx_struct NotifyParentMsg
{
	nx_uint16_t senderID;
	nx_uint16_t parentID;
	nx_uint8_t depth;
} NotifyParentMsg;

#endif
