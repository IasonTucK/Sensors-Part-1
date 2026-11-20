#include "SimpleRoutingTree.h"
#ifdef PRINTFDBG_MODE
	#include "printf.h"
#endif

// Αυτό είναι ο κώδικας που θα τρέχει ο κάθε αισθητήρας μόνος του.

// Ότι 'interface' προσθέσουμε εδώ, θα πρέπει αν το συνδέσουμε και στο 'SRTreeAppC.nc'

module SRTreeC
{
	// Εδώ αναφέρουμε όλα τα 'interfaces' που έχουμε
	// Να πετάξουμε όσα 'interfaces' δεν χρειάζονται (πχ. Leds)

	uses interface Boot;
	uses interface Leds;
	uses interface SplitControl as RadioControl;
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'uses interface SplitControl as SerialControl;' (μέσα σε #ifdef SERIAL_EN).
	// Η σειριακή θύρα χρησιμοποιούνταν μόνο για να στέλνει η ρίζα τα NotifyParentMsg στο PC (πραγματικό hardware).

	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;

	// Νέα interfaces για τα δεδομένα συνάθροισης
	uses interface Packet as AggPacket;
	uses interface AMSend as AggAMSend;
	uses interface AMPacket as AggAMPacket;
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Τα interfaces NotifyAMSend, NotifyAMPacket, NotifyPacket.
	// Στο TAG δεν στέλνουμε NotifyParentMsg: ο πατέρας καταλαβαίνει τα παιδιά του όταν λάβει δεδομένα τους.

	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Τα interfaces SerialAMSend, SerialAMPacket, SerialPacket (μέσα σε #ifdef SERIAL_EN).
	uses interface Timer<TMilli> as Led0Timer;
	uses interface Timer<TMilli> as Led1Timer;
	uses interface Timer<TMilli> as Led2Timer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'uses interface Timer<TMilli> as LostTaskTimer;'
	// Η μόνη εντολή που τον ξεκινούσε ήταν σε σχόλιο, άρα δεν χτυπούσε ποτέ (νεκρός κώδικας).
	
	uses interface Receive as RoutingReceive;
	// [Βήμα 1] ΠΡΟΣΘΗΚΗ: Λήψη των δεδομένων συνάθροισης από τα παιδιά. Ήταν ήδη συνδεδεμένο στο SRTreeAppC.nc
	// ('SRTreeC.AggReceive->...') αλλά δεν είχε δηλωθεί εδώ, οπότε δεν έκανε compile.
	uses interface Receive as AggReceive;
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'uses interface Receive as NotifyReceive;' και 'uses interface Receive as SerialReceive;'
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Οι ουρές NotifySendQueue και NotifyReceiveQueue.

	// Νέες ουρές για τα δεδομένα συνάθροισης
	uses interface PacketQueue as AggSendQueue;
	uses interface PacketQueue as AggReceiveQueue;

	uses interface Random; // Για παραγωγή τυχαίων αριθμών
}
implementation
{
	// Εδώ ξεκινάει ο κώδικας

	uint16_t  roundCounter; // Ορίζει σε ποιά εποχή είμαστε
	
	message_t radioRoutingSendPkt;
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'message_t radioNotifySendPkt;' (NotifyParentMsg).
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'message_t serialPkt;' και '//message_t serialRecPkt;' (σειριακή θύρα).
	
	// Αν είναι busy ο ασύρματος
	bool RoutingSendBusy=FALSE;
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'bool NotifySendBusy=FALSE;' και 'bool serialBusy=FALSE;'
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Οι σημαίες lostRoutingSendTask, lostNotifySendTask, lostRoutingRecTask, lostNotifyRecTask.
	// Τις διάβαζε μόνο το LostTaskTimer.fired(), που δεν εκτελούνταν ποτέ.
	
	// Αρχικοποιούνατι σε τιμές που λένε 'δε ξέρω το βάθος μου' και 'δεν ξέρω τον πατέρα μου' και έπειτα τα αλλάξουν
	uint8_t curdepth; // Το τρέχον βάθος
	uint16_t parentID; // Ποιός είναι ο πατέρας μου
	
	// Αυτά είναι 'tasks' που ορίζω παρακάτω
	task void sendRoutingTask();
	task void receiveRoutingTask();
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Οι δηλώσεις των tasks sendNotifyTask() και receiveNotifyTask().
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Οι συναρτήσεις setLostRoutingSendTask(), setLostNotifySendTask(), setLostNotifyRecTask(),
	// setLostRoutingRecTask(). Άλλαζαν μόνο τις σημαίες lost* του νεκρού μηχανισμού 'lost task'.
	void setRoutingSendBusy(bool state)
	{
		atomic{
		RoutingSendBusy=state;
		}
		if(state==TRUE)
		{
			call Leds.led0On();
			call Led0Timer.startOneShot(TIMER_LEDS_MILLI);
		}
		else 
		{
			//call Leds.led0Off();
		}
	}
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Η setNotifySendBusy() (NotifyParentMsg) και η setSerialBusy() (σειριακή θύρα, μέσα σε #ifdef SERIAL_EN).
	event void Boot.booted()
	{
		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'setNotifySendBusy(FALSE);' και 'setSerialBusy(FALSE);'
		roundCounter =0;
		
		if(TOS_NODE_ID==0)
		{
			// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'call SerialControl.start();' (η ρίζα δεν ανοίγει πλέον σειριακή θύρα).
			curdepth=0;
			parentID=0;
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
#ifdef PRINTFDBG_MODE
			printf("Booted NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			printfflush();
#endif
		}
		else
		{
			curdepth=-1;
			parentID=-1;
			dbg("Boot", "curdepth = %d  ,  parentID= %d \n", curdepth , parentID);
#ifdef PRINTFDBG_MODE
			printf("Booted NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
			printfflush();
#endif
		}
	}
	
	event void RadioControl.startDone(error_t err) // To 'boot' του αισθητήρα ολοκληρώθηκε (ήρθε το event)
	{
		if (err == SUCCESS)
		{
			dbg("Radio" , "Radio initialized successfully!!!\n");
#ifdef PRINTFDBG_MODE
			printf("Radio initialized successfully!!!\n");
			printfflush();
#endif
			
			//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//call RoutingMsgTimer.startPeriodic(TIMER_PERIOD_MILLI);
			//call LostTaskTimer.startPeriodic(SEND_CHECK_MILLIS);

			// Αν είσαι ο κόμβος 0, περίμενε λίγη ώρα να κάνουν 'boot' και οι υπόλοιποι αισθητήρες
			if (TOS_NODE_ID==0)
			{
				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
		}
		else
		{
			dbg("Radio" , "Radio initialization failed! Retrying...\n");
#ifdef PRINTFDBG_MODE
			printf("Radio initialization failed! Retrying...\n");
			printfflush();
#endif
			call RadioControl.start();
		}
	}
	
	event void RadioControl.stopDone(error_t err)
	{ 
		dbg("Radio", "Radio stopped!\n");
#ifdef PRINTFDBG_MODE
		printf("Radio stopped!\n");
		printfflush();
#endif
	}
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Τα events SerialControl.startDone() και SerialControl.stopDone() (σειριακή θύρα).
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Το event LostTaskTimer.fired(). Ξαναέκανε post τα tasks που είχαν 'χαθεί', αλλά ο LostTaskTimer
	// δεν ξεκινούσε ποτέ. Δεν χρειάζεται αντικατάσταση: αν η sendRoutingTask() βρει τον ασύρματο busy, το
	// RoutingAMSend.sendDone() την ξανακάνει post μόλις τελειώσει η τρέχουσα αποστολή (αφού η ουρά δεν είναι άδεια).
	
	event void RoutingMsgTimer.fired()
	{
		message_t tmp;
		error_t enqueueDone;
		
		RoutingMsg* mrpkt;
		dbg("SRTreeC", "RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
#ifdef PRINTFDBG_MODE
		printfflush();
		printf("RoutingMsgTimer fired!  radioBusy = %s \n",(RoutingSendBusy)?"True":"False");
		printfflush();
#endif

		// [Βήμα 1] ΑΦΑΙΡΕΣΗ (TODO: 'Στο tag, το routing στέλνεται ΜΟΝΟ μια φορά'): Εδώ υπήρχε το μπλοκ
		//   if (TOS_NODE_ID==0) { roundCounter+=1; <εκτύπωση ROUND>; call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI); }
		// με το οποίο η ρίζα ξαναέστελνε routing μήνυμα (δηλαδή ξαναέχτιζε το δέντρο) κάθε TIMER_PERIOD_MILLI (~150 sec).
		// Στο TAG η τοπολογία είναι στατική, οπότε το δέντρο χτίζεται ΜΙΑ φορά, στην αρχή.
		// (Επιπλέον, το TIMER_PERIOD_MILLI δεν υπάρχει πια στο SimpleRoutingTree.h, οπότε δεν έκανε compile.)
		
		if(call RoutingSendQueue.full())
		// Εδώ θα πρέπει να στειλώ τα routing μηνύματα
		{
#ifdef PRINTFDBG_MODE
			printf("RoutingSendQueue is FULL!!! \n");
			printfflush();
#endif
			return;
		}
		
		
		mrpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&tmp, sizeof(RoutingMsg)));
		if(mrpkt==NULL)
		{
			dbg("SRTreeC","RoutingMsgTimer.fired(): No valid payload... \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsgTimer.fired(): No valid payload... \n");
			printfflush();
#endif
			return;
		}
		// Εδώ γεμίζουμε τα περιεχόμενα του μηνύματος
		atomic{
		// TODO: Το να λέω μέσα στο μληνυμα το ποιός είμαι εγώ που το στέλνω είναι άσκοπο, αφού από το 'interface' AMPacket, είπαμε ότι αυτό αναφέρεται στην κεφαλή του πακέτου
		mrpkt->senderID=TOS_NODE_ID; // Το ID του τρέχοντος κόμβου
		mrpkt->depth = curdepth; // Το βάθος του τρέχοντος κόμβου
		}
		dbg("SRTreeC" , "Sending RoutingMsg... \n");

#ifdef PRINTFDBG_MODE
		printf("NodeID= %d : RoutingMsg sending...!!!! \n", TOS_NODE_ID);
		printfflush();
#endif		

		// Στην κεφαλή του μηνύματος βάζουμε και τον αποδέκτη (που εδώ είναι broadcast) και το μέγεθος του μηνύματος
		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, sizeof(RoutingMsg));
		
		enqueueDone=call RoutingSendQueue.enqueue(tmp); // Το βάζουμε στην ουρά των μηνυμάτων
		
		if( enqueueDone==SUCCESS) // Αν η ουρά δεν είναι γεμάτη
		{
			// Αν είναι το 1ο μήνυμα στην ουρά, κάνε 'sendRoutingTask'
			// NOTE: Αυτό το κάνουμε μόνο στο 1ο, διότι αν είχαμε 2, το 1ο θα έκανε το 'sendRoutingTask' και θα έστελνε και το 2ο αυτόματα.
			if (call RoutingSendQueue.size()==1)
			{
				dbg("SRTreeC", "SendTask() posted!!\n");
#ifdef PRINTFDBG_MODE
				printf("SendTask() posted!!\n");
				printfflush();
#endif
				post sendRoutingTask();
			}
			
			dbg("SRTreeC","RoutingMsg enqueued successfully in SendingQueue!!!\n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsg enqueued successfully in SendingQueue!!!\n");
			printfflush();
#endif
		}
		else
		{
			dbg("SRTreeC","RoutingMsg failed to be enqueued in SendingQueue!!!");
#ifdef PRINTFDBG_MODE			
			printf("RoutingMsg failed to be enqueued in SendingQueue!!!\n");
			printfflush();
#endif
		}		
	}
	
	event void Led0Timer.fired()
	{
		call Leds.led0Off();
	}
	event void Led1Timer.fired()
	{
		call Leds.led1Off();
	}
	event void Led2Timer.fired()
	{
		call Leds.led2Off();
	}

	// Εδώ είναι το event για όταν στέλνουμε ένα μήνυμα
	event void RoutingAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("A Routing package sent... %s \n",(err==SUCCESS)?"True":"False");
		printfflush();
#endif
		
		dbg("SRTreeC" , "Package sent %s \n", (err==SUCCESS)?"True":"False");
#ifdef PRINTFDBG_MODE
		printf("Package sent %s \n", (err==SUCCESS)?"True":"False");
		printfflush();
#endif
		setRoutingSendBusy(FALSE);
		
		// Αν η ουρά μηνυμάτων δεν είναι άδεια, στείλε και το επόμενο μήνυμα
		if(!(call RoutingSendQueue.empty()))
		{
			post sendRoutingTask();
		}
		//call Leds.led0Off();
	
		
	}
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Τα events NotifyAMSend.sendDone() (NotifyParentMsg) και SerialAMSend.sendDone() (σειριακή θύρα).
	
	// [Βήμα 1] ΠΡΟΣΘΗΚΗ: Κενό event για το AggAMSend. Το nesC απαιτεί να υλοποιούνται όλα τα events των interfaces
	// που χρησιμοποιούμε, αλλιώς δεν κάνει compile ('AggAMSend.sendDone not implemented').
	// Θα συμπληρωθεί στο βήμα της αποστολής των δεδομένων συνάθροισης.
	event void AggAMSend.sendDone(message_t * msg , error_t err)
	{
	}
	
	// [Βήμα 1] ΠΡΟΣΘΗΚΗ: Κενό event για το AggReceive (ίδιος λόγος). Θα συμπληρωθεί στο βήμα της λήψης των δεδομένων συνάθροισης.
	event message_t* AggReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		return msg;
	}
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Το event NotifyReceive.receive() (λήψη NotifyParentMsg).
//	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)

	// Όταν λαμβάνουμε ένα μήνυμα, εκτελείται αυτό το event
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		dbg("SRTreeC", "Something received!!!  from %u  %u \n",((RoutingMsg*) payload)->senderID ,  msource);
		//dbg("SRTreeC", "Something received!!!\n");
#ifdef PRINTFDBG_MODE		
		// [Βήμα 1] ΑΛΛΑΓΗ: Αφαιρέθηκε το 'npm=%u' / 'sizeof(NotifyParentMsg)', γιατί ο τύπος NotifyParentMsg δεν υπάρχει πια.
		printf("Something Received!!!, len = %u , rm=%u\n",len, sizeof(RoutingMsg));
		printfflush();
#endif
		//call Leds.led1On();
		//call Led1Timer.startOneShot(TIMER_LEDS_MILLI);
		
		//if(len!=sizeof(RoutingMsg))
		//{
			//dbg("SRTreeC","\t\tUnknown message received!!!\n");
//#ifdef PRINTFDBG_MODE
			//printf("\t\t Unknown message received!!!\n");
			//printfflush();
//#endif
			//return msg;
		//}
		
		atomic{
		memcpy(&tmp,msg,sizeof(message_t));
		//tmp=*(message_t*)msg;
		}
		enqueueDone=call RoutingReceiveQueue.enqueue(tmp);
		if(enqueueDone == SUCCESS)
		{
#ifdef PRINTFDBG_MODE
			printf("posting receiveRoutingTask()!!!! \n");
			printfflush();
#endif
			post receiveRoutingTask();
		}
		else
		{
			dbg("SRTreeC","RoutingMsg enqueue failed!!! \n");
#ifdef PRINTFDBG_MODE
			printf("RoutingMsg enqueue failed!!! \n");
			printfflush();
#endif			
		}
		
		//call Leds.led1Off();
		
		dbg("SRTreeC", "### RoutingReceive.receive() end ##### \n");
		return msg;
	}
	
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Το event SerialReceive.receive() (σειριακή θύρα).
	
	////////////// Tasks implementations //////////////////////////////
	
	
	task void sendRoutingTask()
	{
		//uint8_t skip;
		uint8_t mlen;
		uint16_t mdest;
		error_t sendDone;
		//message_t radioRoutingSendPkt;
		
#ifdef PRINTFDBG_MODE
		printf("SendRoutingTask(): Starting....\n");
		printfflush();
#endif
		if (call RoutingSendQueue.empty())
		{
			dbg("SRTreeC","sendRoutingTask(): Q is empty!\n");
#ifdef PRINTFDBG_MODE		
			printf("sendRoutingTask():Q is empty!\n");
			printfflush();
#endif
			return;
		}
		
		
		if(RoutingSendBusy)
		{
			dbg("SRTreeC","sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
#ifdef PRINTFDBG_MODE
			printf(	"sendRoutingTask(): RoutingSendBusy= TRUE!!!\n");
			printfflush();
#endif
			// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'setLostRoutingSendTask(TRUE);' (νεκρός μηχανισμός 'lost task').
			// Δεν χάνεται τίποτα: το RoutingAMSend.sendDone() θα ξανακάνει post το task, αφού η ουρά δεν είναι άδεια.
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue(); // Αφαιρούμε το 1ο μήνυμα από την ουρά
		
		//call Leds.led2On();
		//call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt); // Παίρνουμε το μέγεθος του μηνύματος
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt); // Παίρνουμε τον αποδέκτη του μηνύματος
		if(mlen!=sizeof(RoutingMsg))
		{
			dbg("SRTreeC","\t\tsendRoutingTask(): Unknown message!!!\n");
#ifdef PRINTFDBG_MODE
			printf("\t\tsendRoutingTask(): Unknown message!!!!\n");
			printfflush();
#endif
			return;
		}

		// Καλούμε την 'send' για στείλουμε το μήνυμα
		// NOTE: Όταν το μήνυμα σταλεί, θα μου έρθει ένα event. Αυτό δε σημαίνει ότι ο παραλήπτης το έλαβε.
		sendDone=call RoutingAMSend.send(mdest,&radioRoutingSendPkt,mlen);
		
		if ( sendDone== SUCCESS)
		{
			dbg("SRTreeC","sendRoutingTask(): Send returned success!!!\n");
#ifdef PRINTFDBG_MODE
			printf("sendRoutingTask(): Send returned success!!!\n");
			printfflush();
#endif
			setRoutingSendBusy(TRUE);
		}
		else
		{
			dbg("SRTreeC","send failed!!!\n");
#ifdef PRINTFDBG_MODE
			printf("SendRoutingTask(): send failed!!!\n");
#endif
			//setRoutingSendBusy(FALSE);
		}
	}
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Το task sendNotifyTask() (αποστολή NotifyParentMsg).
	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */
	
	task void receiveRoutingTask()
	{
		// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'message_t tmp;' (το χρησιμοποιούσαν μόνο τα NotifyParentMsg που αφαιρέθηκαν).
		uint8_t len;
		message_t radioRoutingRecPkt;
		
#ifdef PRINTFDBG_MODE
		printf("ReceiveRoutingTask():received msg...\n");
		printfflush();
#endif
		radioRoutingRecPkt= call RoutingReceiveQueue.dequeue(); // Βγάζει ένα μήνυμα από την ουρά
		
		len= call RoutingPacket.payloadLength(&radioRoutingRecPkt);
		
		dbg("SRTreeC","ReceiveRoutingTask(): len=%u \n",len);
#ifdef PRINTFDBG_MODE
		printf("ReceiveRoutingTask(): len=%u!\n",len);
		printfflush();
#endif
		// processing of radioRecPkt
		
		// pos tha xexorizo ta 2 diaforetika minimata???
				
		if(len == sizeof(RoutingMsg)) // Σίγουρα θα έχει αυτό το μέγεθος
		{
			// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'NotifyParentMsg* m;'
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len)); // Παίρνει ένα δείκτη στα δεδομένα του μηνύματος
			
			//if(TOS_NODE_ID >0)
			//{
				//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//}
			//
			
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
#ifdef PRINTFDBG_MODE
			printf("NodeID= %d , RoutingMsg received! \n",TOS_NODE_ID);
			printf("receiveRoutingTask():senderID= %d , depth= %d \n", mpkt->senderID , mpkt->depth);
			printfflush();
#endif
			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				//NOTE: Ο έξυπνιος τρόπος να βρούμε ποιός είναια υτός που έστειλε το μήνυμα είναι η source (αντί για mpkt->senderID)
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
				curdepth= mpkt->depth + 1; // Το τρέχον βάθος είναι +1 αυτού που μου έστειλε το μήνυμα

				// TODO: Στο TAG οι κόμβοι χρονοπρογραμματίζονται σύμφωνα με το βάθος τους. Οπότε εδώ που βρίσκουμε το βάθος, μπορούμε να ξεκινάμε έναν timer που θα λέει το πότε λειτουργεί ο κόμβος (συγκεκριμένα θα κάνουμε και χρήση του startPeriodical, ώστε να χτυπάει σε συγκεκριμένη περίοδο)
#ifdef PRINTFDBG_MODE
				printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
				printfflush();
#endif
				// [Βήμα 1] ΠΡΟΣΘΗΚΗ: Εκτύπωση με dbg (το printf από πάνω τυπώνει μόνο σε πραγματικό hardware),
				// ώστε να φαίνεται στην προσομοίωση το δέντρο που χτίστηκε.
				dbg("SRTreeC" , "NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);

				// [Βήμα 1] ΑΦΑΙΡΕΣΗ (TODO: 'Εδώ στέλνουμε ένα μήνυμα NotifyParentMsg ... στο TAG αυτό δεν το κάνουμε'):
				// Εδώ ο κόμβος έφτιαχνε ένα NotifyParentMsg (senderID, depth, parentID) και το έβαζε στην NotifySendQueue
				// για τον πατέρα του. Στο TAG ένας κόμβος Α καταλαβαίνει ότι είναι πατέρας του Β όταν λάβει δεδομένα του Β
				// για το query (αφού τα παιδιά στέλνουν δεδομένα μόνο στον πατέρα), οπότε το μήνυμα είναι περιττό.

				// TODO: Κάποιος που έλαβε ένα 'routing message' για πρώτη φορά (και αποφάσισα ποιός είναι ο πατερας μου και έκανα τον χρονοπρογραμματισμό μου), πρέπει να στείλω αυτό το 'routing message' για να το ακούσουν και οι γειτονές μου

				// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Το 'if (call NotifySendQueue.enqueue(tmp)==SUCCESS) { ... post sendNotifyTask(); }'
				// που έβαζε το NotifyParentMsg στην ουρά αποστολής (συνέχεια της παραπάνω αφαίρεσης).

				// Αν δεν είμαι ο κόμβος 0, ξεκίνα έναν μετρητή για να στείλεις το 'routing message'
				if (TOS_NODE_ID!=0)
				{
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
				}
			}
			else
			{
				
				if (( curdepth > mpkt->depth +1) || (mpkt->senderID==parentID))
				{
					// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'uint16_t oldparentID = parentID;' (χρειαζόταν μόνο για το NotifyParentMsg προς τον παλιό πατέρα).
					
					parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
					curdepth = mpkt->depth + 1;
				
#ifdef PRINTFDBG_MODE
					printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
					printfflush();
#endif					
					// [Βήμα 1] ΠΡΟΣΘΗΚΗ: Εκτύπωση με dbg της αλλαγής πατέρα (για να φαίνεται στην προσομοίωση).
					dbg("SRTreeC" , "NodeID= %d : NEW curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
					
					// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Τα 2 NotifyParentMsg που στέλνονταν εδώ, ένα στον παλιό πατέρα και ένα στον νέο.
					// Στο TAG δεν χρειάζονται. Επιπλέον η συνθήκη του πρώτου,
					// '(oldparentID<65535) || (oldparentID>0) || (oldparentID==parentID)', ήταν πάντα αληθής,
					// οπότε στελνόταν μήνυμα ακόμα και όταν ο πατέρας δεν είχε αλλάξει.
					
					if (TOS_NODE_ID!=0)
					{
						call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
					}
				}
				
				
			}
		}
		else
		{
			dbg("SRTreeC","receiveRoutingTask():Empty message!!! \n");
#ifdef PRINTFDBG_MODE
			printf("receiveRoutingTask():Empty message!!! \n");
			printfflush();
#endif
			// [Βήμα 1] ΑΦΑΙΡΕΣΗ: 'setLostRoutingRecTask(TRUE);' (νεκρός μηχανισμός 'lost task'). Το μήνυμα απλά αγνοείται.
			return;
		}
		
	}


////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////	
	
	 
	// [Βήμα 1] ΑΦΑΙΡΕΣΗ: Το task receiveNotifyTask(). Επεξεργαζόταν τα NotifyParentMsg: οι κλάδοι 'προσθήκη/διαγραφή παιδιού'
	// ήταν κενοί, η ρίζα τα έστελνε στο PC μέσω σειριακής, και οι υπόλοιποι κόμβοι τα προωθούσαν στον πατέρα τους
	// μέχρι τη ρίζα (πολλές περιττές μεταδόσεις).
	
}
