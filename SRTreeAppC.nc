#include "SimpleRoutingTree.h"

configuration SRTreeAppC @safe() { }
implementation{
	components SRTreeC; // Είναι το module που θα έχει τον κώδικα μας

	// Για κάθε είδος μηνυμάτων που ορίσαμε στο 'SimpleRoutingTree.h' φτιάχνουμε 2 components για το συγκεριμένο 'active message ID'
	components new AMSenderC(AM_ROUTINGMSG) as RoutingSenderC;
	components new AMReceiverC(AM_ROUTINGMSG) as RoutingReceiverC;
	// ΑΦΑΙΡΕΣΗ: Οι 2 σχολιασμένες γραμμές των NotifySenderC / NotifyReceiverC (το NotifyParentMsg καταργήθηκε).

	components new AMSenderC(AM_AGGREGATEMSG) as AggSenderC;
	components new AMReceiverC(AM_AGGREGATEMSG) as AggReceiverC;

	// Εδώ έχουμε τις ουρές για κάθε είδος μηνλυματος, μια ουρά για αποστολή και μια για παραλαβή
	components new PacketQueueC(SENDER_QUEUE_SIZE) as RoutingSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as RoutingReceiveQueueC;
	// ΑΦΑΙΡΕΣΗ: Οι 2 σχολιασμένες γραμμές των NotifySendQueueC / NotifyReceiveQueueC (το NotifyParentMsg καταργήθηκε).

	components new PacketQueueC(SENDER_QUEUE_SIZE) as AggSendQueueC;
	components new PacketQueueC(RECEIVER_QUEUE_SIZE) as AggReceiveQueueC;

	// ΑΛΛΑΓΗ: Ήταν 'components MainC, ActiveMessageC, SerialActiveMessageC, LedC, RandomC;'
	//   - 'LedC' -> 'LedsC': ορθογραφικό λάθος. Το LedC είναι άλλο component (θέλει PlatformLed.h, δεν κάνει compile).
	//   - Αφαιρέθηκε το 'SerialActiveMessageC': η σειριακή θύρα δεν χρησιμοποιείται στην προσομοίωση.
	components MainC, ActiveMessageC, LedsC, RandomC;

	// Εδώ έχουμε κάποιους μετρητές
	components new TimerMilliC() as Led0TimerC;
	components new TimerMilliC() as Led1TimerC;
	components new TimerMilliC() as Led2TimerC;
	components new TimerMilliC() as RoutingMsgTimerC;
	// ΠΡΟΣΘΗΚΗ: Ο μετρητής της εποχής (χρονοπρογραμματισμός TAG βάσει βάθους).
	components new TimerMilliC() as EpochTimerC;
	// ΠΡΟΣΘΗΚΗ: Ο μετρητής της τυχαίας καθυστέρησης αποστολής προς τον πατέρα.
	components new TimerMilliC() as AggSendTimerC;
	// ΠΡΟΣΘΗΚΗ: Ο μετρητής της αίτησης ένταξης στο δέντρο (JoinRequest).
	components new TimerMilliC() as JoinTimerC;
	// ΑΦΑΙΡΕΣΗ: 'components new TimerMilliC() as LostTaskTimerC;' (ο LostTaskTimer δεν ξεκινούσε ποτέ, νεκρός κώδικας).

	// Εδώ δηλώνουμε τα 'interfaces' που θα χρησιμοποιήσουμε. Όλα αυτά τα 'interfaces' είναι δηλωμένα στο άλλο αρχείο και εδώ κάνουμε το wiring.
	// Όλα τα ονόματα που βλέπουμε μετά την τελίτσα είνα τα ονόματα που έχουμε ορίσει στο 'SRTreee.c'. Οπότε ότι καινούργιο 'interface' προσθέσουμε στο 'SRTreee.c', πρέπει να το συνδέσουμε εδώ για να βρίσεκι τον κώδικά του.
	SRTreeC.Boot->MainC.Boot;
	
	SRTreeC.RadioControl -> ActiveMessageC;
	SRTreeC.Leds-> LedsC;
	
	SRTreeC.Led0Timer-> Led0TimerC;
	SRTreeC.Led1Timer-> Led1TimerC;
	SRTreeC.Led2Timer-> Led2TimerC;
	SRTreeC.RoutingMsgTimer->RoutingMsgTimerC;
	SRTreeC.EpochTimer->EpochTimerC; // ΠΡΟΣΘΗΚΗ
	SRTreeC.AggSendTimer->AggSendTimerC; // ΠΡΟΣΘΗΚΗ
	SRTreeC.JoinTimer->JoinTimerC; // ΠΡΟΣΘΗΚΗ
	// ΑΦΑΙΡΕΣΗ: 'SRTreeC.LostTaskTimer->LostTaskTimerC;'

	SRTreeC.RoutingPacket->RoutingSenderC.Packet;
	SRTreeC.RoutingAMPacket->RoutingSenderC.AMPacket;

	SRTreeC.AggPacket->AggSenderC.Packet;
	SRTreeC.AggAMPacket->AggSenderC.AMPacket;	

	SRTreeC.RoutingAMSend->RoutingSenderC.AMSend;
	SRTreeC.RoutingReceive->RoutingReceiverC.Receive;

	SRTreeC.AggAMSend->AggSenderC.AMSend;
	// ΑΛΛΑΓΗ: Ήταν '->AggReceiveC.Receive'. Ορθογραφικό λάθος: το component λέγεται 'AggReceiverC'.
	SRTreeC.AggReceive->AggReceiverC.Receive;

	// ΑΦΑΙΡΕΣΗ: Το wiring των NotifyPacket, NotifyAMPacket, NotifyAMSend, NotifyReceive (το NotifyParentMsg καταργήθηκε).

	// ΑΦΑΙΡΕΣΗ: Όλο το μπλοκ '#ifdef SERIAL_EN' με το wiring των SerialReceive, SerialAMSend, SerialAMPacket,
	// SerialPacket, SerialControl (η σειριακή θύρα δεν χρησιμοποιείται στην προσομοίωση).
	SRTreeC.RoutingSendQueue->RoutingSendQueueC;
	SRTreeC.RoutingReceiveQueue->RoutingReceiveQueueC;
	// ΑΦΑΙΡΕΣΗ: 'SRTreeC.NotifySendQueue->NotifySendQueueC;' και 'SRTreeC.NotifyReceiveQueue->NotifyReceiveQueueC;'

	SRTreeC.AggSendQueue->AggSendQueueC;
	SRTreeC.AggReceiveQueue->AggReceiveQueueC;

	SRTreeC.Random->RandomC;
	// ΠΡΟΣΘΗΚΗ: Σύνδεση του SeedInit, για να ορίζουμε εμείς το seed της γεννήτριας τυχαίων αριθμών.
	SRTreeC.SeedInit->RandomC.SeedInit;
	
}
