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
	// ΑΦΑΙΡΕΣΗ: 'uses interface SplitControl as SerialControl;' (μέσα σε #ifdef SERIAL_EN).
	// Η σειριακή θύρα χρησιμοποιούνταν μόνο για να στέλνει η ρίζα τα NotifyParentMsg στο PC (πραγματικό hardware).

	uses interface Packet as RoutingPacket;
	uses interface AMSend as RoutingAMSend;
	uses interface AMPacket as RoutingAMPacket;

	// Νέα interfaces για τα δεδομένα συνάθροισης
	uses interface Packet as AggPacket;
	uses interface AMSend as AggAMSend;
	uses interface AMPacket as AggAMPacket;
	
	// ΑΦΑΙΡΕΣΗ: Τα interfaces NotifyAMSend, NotifyAMPacket, NotifyPacket.
	// Στο TAG δεν στέλνουμε NotifyParentMsg: ο πατέρας καταλαβαίνει τα παιδιά του όταν λάβει δεδομένα τους.

	// ΑΦΑΙΡΕΣΗ: Τα interfaces SerialAMSend, SerialAMPacket, SerialPacket (μέσα σε #ifdef SERIAL_EN).
	uses interface Timer<TMilli> as Led0Timer;
	uses interface Timer<TMilli> as Led1Timer;
	uses interface Timer<TMilli> as Led2Timer;
	uses interface Timer<TMilli> as RoutingMsgTimer;
	// ΠΡΟΣΘΗΚΗ: Ο περιοδικός μετρητής της εποχής. Χτυπάει μία φορά ανά εποχή, τη στιγμή που ο κόμβος
	// πρέπει να λειτουργήσει (ανάλογα με το βάθος του).
	uses interface Timer<TMilli> as EpochTimer;
	// ΠΡΟΣΘΗΚΗ: Μετρητής μιας χρήσης για την τυχαία καθυστέρηση της αποστολής προς τον πατέρα, μέσα στο slot του κόμβου.
	uses interface Timer<TMilli> as AggSendTimer;
	// ΠΡΟΣΘΗΚΗ: Μετρητής της αίτησης ένταξης στο δέντρο (JoinRequest), για κόμβους που έχασαν το routing μήνυμα.
	uses interface Timer<TMilli> as JoinTimer;
	// ΑΦΑΙΡΕΣΗ: 'uses interface Timer<TMilli> as LostTaskTimer;'
	// Η μόνη εντολή που τον ξεκινούσε ήταν σε σχόλιο, άρα δεν χτυπούσε ποτέ (νεκρός κώδικας).
	
	uses interface Receive as RoutingReceive;
	// ΠΡΟΣΘΗΚΗ: Λήψη των δεδομένων συνάθροισης από τα παιδιά. Ήταν ήδη συνδεδεμένο στο SRTreeAppC.nc
	// ('SRTreeC.AggReceive->...') αλλά δεν είχε δηλωθεί εδώ, οπότε δεν έκανε compile.
	uses interface Receive as AggReceive;
	// ΑΦΑΙΡΕΣΗ: 'uses interface Receive as NotifyReceive;' και 'uses interface Receive as SerialReceive;'
	
	uses interface PacketQueue as RoutingSendQueue;
	uses interface PacketQueue as RoutingReceiveQueue;
	
	// ΑΦΑΙΡΕΣΗ: Οι ουρές NotifySendQueue και NotifyReceiveQueue.

	// Νέες ουρές για τα δεδομένα συνάθροισης
	uses interface PacketQueue as AggSendQueue;
	uses interface PacketQueue as AggReceiveQueue;

	uses interface Random; // Για παραγωγή τυχαίων αριθμών
	// ΠΡΟΣΘΗΚΗ: Αρχικοποίηση (seed) της γεννήτριας τυχαίων αριθμών. Χωρίς αυτό το RandomC ξεκινάει πάντα
	// από seed = TOS_NODE_ID+1, άρα η ρίζα θα διάλεγε ΠΑΝΤΑ το ίδιο ερώτημα και την ίδια εποχή (όπως στο lab4).
	uses interface ParameterInit<uint16_t> as SeedInit;
}
implementation
{
	// Εδώ ξεκινάει ο κώδικας

	uint16_t  roundCounter; // Ορίζει σε ποιά εποχή είμαστε
	
	message_t radioRoutingSendPkt;
	// ΑΦΑΙΡΕΣΗ: 'message_t radioNotifySendPkt;' (NotifyParentMsg).
	// ΑΦΑΙΡΕΣΗ: 'message_t serialPkt;' και '//message_t serialRecPkt;' (σειριακή θύρα).
	
	// Αν είναι busy ο ασύρματος
	bool RoutingSendBusy=FALSE;
	// ΑΦΑΙΡΕΣΗ: 'bool NotifySendBusy=FALSE;' και 'bool serialBusy=FALSE;'
	
	// ΑΦΑΙΡΕΣΗ: Οι σημαίες lostRoutingSendTask, lostNotifySendTask, lostRoutingRecTask, lostNotifyRecTask.
	// Τις διάβαζε μόνο το LostTaskTimer.fired(), που δεν εκτελούνταν ποτέ.
	
	// Αρχικοποιούνατι σε τιμές που λένε 'δε ξέρω το βάθος μου' και 'δεν ξέρω τον πατέρα μου' και έπειτα τα αλλάξουν
	uint8_t curdepth; // Το τρέχον βάθος
	uint16_t parentID; // Ποιός είναι ο πατέρας μου

	// ΠΡΟΣΘΗΚΗ: Οι παράμετροι του ερωτήματος. Τις διαλέγει τυχαία η ρίζα και τις μαθαίνουν οι υπόλοιποι κόμβοι
	// από το RoutingMsg, κατά το χτίσιμο του δέντρου.
	uint8_t queryType; // 1=SUM, 2=AVG, 3=VARIANCE, 4=MAX
	uint8_t epochSec; // Διάρκεια εποχής σε δευτερόλεπτα (30, 40, ..., 100)

	// ΠΡΟΣΘΗΚΗ: Η μέτρηση του κόμβου στην τρέχουσα εποχή.
	uint8_t measurement;

	// ΠΡΟΣΘΗΚΗ: Το μερικό αποτέλεσμα που έχουν στείλει τα παιδιά στην τρέχουσα εποχή (συνδυασμένο).
	// Ανάλογα με το ερώτημα χρησιμοποιούνται μόνο κάποια από αυτά: SUM -> childSum, AVG -> childSum/childCount,
	// VARIANCE -> childSum/childSumSq/childCount, MAX -> childMax. Μηδενίζονται μετά από κάθε αποστολή (resetChildData()).
	uint16_t childSum;
	uint32_t childSumSq;
	uint8_t childCount;
	uint8_t childMax;

	// ΠΡΟΣΘΗΚΗ: Αποστολή των δεδομένων συνάθροισης (ίδια λογική με τα routing μηνύματα: ουρά + task + busy).
	message_t radioAggSendPkt;
	bool AggSendBusy=FALSE;
	// TRUE από τη στιγμή που χτυπάει ο EpochTimer μέχρι να φύγει το μήνυμα προς τον πατέρα (στη διάρκεια της τυχαίας
	// καθυστέρησης). Τότε δεχόμαστε ακόμα δεδομένα από τα παιδιά για την τρέχουσα εποχή.
	bool aggPending=FALSE;
	// ΠΡΟΣΘΗΚΗ: Πόσες αιτήσεις ένταξης (JoinRequest) έχει στείλει ο κόμβος.
	uint8_t joinTries=0;

	
	// Αυτά είναι 'tasks' που ορίζω παρακάτω
	task void sendRoutingTask();
	task void receiveRoutingTask();
	task void sendAggTask(); // ΠΡΟΣΘΗΚΗ
	task void receiveAggTask(); // ΠΡΟΣΘΗΚΗ
	// ΑΦΑΙΡΕΣΗ: Οι δηλώσεις των tasks sendNotifyTask() και receiveNotifyTask().
	
	// ΑΦΑΙΡΕΣΗ: Οι συναρτήσεις setLostRoutingSendTask(), setLostNotifySendTask(), setLostNotifyRecTask(),
	// setLostRoutingRecTask(). Άλλαζαν μόνο τις σημαίες lost* του νεκρού μηχανισμού 'lost task'.

	// ΠΡΟΣΘΗΚΗ: Ξεκινάει (ή ξαναξεκινάει) τον περιοδικό μετρητή της εποχής, ανάλογα με το βάθος του κόμβου.
	// Χρονοπρογραμματισμός του TAG: ένας κόμβος σε βάθος d χτυπάει d slots ΠΡΙΝ το τέλος κάθε εποχής:
	//     1η φορά:   epochSec*1024 - curdepth*TIMER_SLOT_MILLI
	//     μετά:      κάθε epochSec*1024
	// Έτσι πρώτα λειτουργούν οι πιο βαθιοί κόμβοι, ένα slot μετά οι πατέρες τους κ.ο.κ., και τελευταία η ρίζα
	// (βάθος 0), ακριβώς στο τέλος της εποχής. Η ρίζα έχει το αποτέλεσμα ήδη στο τέλος της 1ης εποχής.
	// Το 'startPeriodicAt(t0, dt)' χτυπάει πρώτη φορά τη στιγμή t0+dt, οπότε δίνουμε t0 = -curdepth*TIMER_SLOT_MILLI
	// (αρνητικό: οι πράξεις γίνονται modulo 2^32, όπως στο σχόλιο 'startPeriodicAt(-45*1024,60*1024)' του lab4).
	// Ο χρόνος 0 είναι το boot του κόμβου (τοπικό ρολόι). Όλοι οι κόμβοι κάνουν boot σχεδόν ταυτόχρονα
	// (mySimulation.py: 10 sec + i ticks), οπότε τα τέλη των εποχών συμπίπτουν σε όλο το δίκτυο.
	void startEpochTimer()
	{
		uint32_t epochMilli = (uint32_t)epochSec * 1024;
		uint32_t offset = (uint32_t)curdepth * TIMER_SLOT_MILLI;

		call EpochTimer.startPeriodicAt((uint32_t)0 - offset, epochMilli);
		dbg("SRTreeC", "NodeID= %d : EpochTimer started, depth= %u , first fire at %u ms, period %u ms \n",
			TOS_NODE_ID, curdepth, epochMilli - offset, epochMilli);
	}

	// ΠΡΟΣΘΗΚΗ: Νέα μέτρηση σε κάθε εποχή. Στην 1η εποχή τυχαίος ακέραιος στο [1..100]. Στις επόμενες, τυχαίος
	// ακέραιος που απέχει το πολύ 25% από την προηγούμενη μέτρηση (low..high) και πάντα στο [1..100].
	void takeMeasurement()
	{
		uint8_t delta, low, high;

		if (roundCounter == 1)
		{
			measurement = (call Random.rand16() % 100) + 1;
		}
		else
		{
			delta = measurement / 4; // 25% της προηγούμενης μέτρησης (στρογγυλοποίηση προς τα κάτω)
			low = measurement - delta; // >= 1, αφού delta < measurement
			high = (measurement + delta > 100) ? 100 : measurement + delta;
			measurement = low + (call Random.rand16() % (high - low + 1));
		}
		dbg("Measurements", "epoch= %u node= %u depth= %u parent= %u measurement= %u \n",
			roundCounter, TOS_NODE_ID, curdepth, parentID, measurement);
	}

	// ΠΡΟΣΘΗΚΗ: Μηδενίζει το μερικό αποτέλεσμα των παιδιών, για να ξεκινήσει η επόμενη εποχή από την αρχή.
	void resetChildData()
	{
		childSum = 0;
		childSumSq = 0;
		childCount = 0;
		childMax = 0;
	}

	// ΠΡΟΣΘΗΚΗ: Το μέγεθος (σε bytes) του μηνύματος συνάθροισης για το τρέχον ερώτημα.
	uint8_t aggMsgLength()
	{
		switch (queryType)
		{
			case 1: return sizeof(SumAggMsg);
			case 2: return sizeof(AvgAggMsg);
			case 3: return sizeof(VarAggMsg);
			case 4: return sizeof(MaxAggMsg);
			default: return 0;
		}
	}

	// ΠΡΟΣΘΗΚΗ: Η ρίζα συνδυάζει τη δική της μέτρηση με τα δεδομένα των παιδιών της και τυπώνει το τελικό
	// αποτέλεσμα της εποχής. AVG = sum/count και VARIANCE = sumSq/count - (sum/count)^2 υπολογίζονται μόνο εδώ.
	void printResult()
	{
		uint16_t sum = childSum + measurement;
		uint32_t sumSq = childSumSq + (uint32_t)measurement * measurement;
		uint8_t count = childCount + 1;
		uint8_t maxVal = (childMax > measurement) ? childMax : measurement;
		double mean;

		switch (queryType)
		{
			case 1:
				dbg("Results", "EPOCH %u : SUM = %u \n", roundCounter, sum);
				break;
			case 2:
				dbg("Results", "EPOCH %u : AVG = %.2f (sum= %u , count= %u) \n", roundCounter, (double)sum / count, sum, count);
				break;
			case 3:
				mean = (double)sum / count;
				dbg("Results", "EPOCH %u : VARIANCE = %.2f (sum= %u , sumSq= %lu , count= %u) \n",
					roundCounter, (double)sumSq / count - mean * mean, sum, (unsigned long)sumSq, count);
				break;
			case 4:
				dbg("Results", "EPOCH %u : MAX = %u \n", roundCounter, maxVal);
				break;
		}
	}

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
	
	// ΑΦΑΙΡΕΣΗ: Η setNotifySendBusy() (NotifyParentMsg) και η setSerialBusy() (σειριακή θύρα, μέσα σε #ifdef SERIAL_EN).
	event void Boot.booted()
	{
		/////// arxikopoiisi radio kai serial
		call RadioControl.start();
		
		setRoutingSendBusy(FALSE);
		// ΑΦΑΙΡΕΣΗ: 'setNotifySendBusy(FALSE);' και 'setSerialBusy(FALSE);'
		roundCounter =0;
		resetChildData(); // ΠΡΟΣΘΗΚΗ

		// ΠΡΟΣΘΗΚΗ: Seed της γεννήτριας με τον χρόνο της προσομοίωσης τη στιγμή του boot (όπως στο lab4).
		// Ο χρόνος αυτός εξαρτάται από το bootAtTime() του mySimulation.py.
		call SeedInit.init(sim_time() % 1024);
		
		if(TOS_NODE_ID==0)
		{
			// ΑΦΑΙΡΕΣΗ: 'call SerialControl.start();' (η ρίζα δεν ανοίγει πλέον σειριακή θύρα).
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
				// ΠΡΟΣΘΗΚΗ: Η ρίζα διαλέγει τυχαία το ερώτημα και τη διάρκεια της εποχής, ΠΡΙΝ στείλει το
				// πρώτο routing μήνυμα, ώστε να διαδοθούν μέσα σε αυτό σε όλο το δίκτυο (χωρίς επιπλέον μηνύματα).
				queryType = (call Random.rand16() % 4) + 1; // 1..4
				epochSec = ((call Random.rand16() % 8) + 3) * 10; // 3..10 επί 10 -> 30, 40, ..., 100 sec
				dbg("SRTreeC", "ROOT: queryType= %u (1=SUM, 2=AVG, 3=VARIANCE, 4=MAX) , epochSec= %u \n", queryType, epochSec);

				// ΠΡΟΣΘΗΚΗ: Η ρίζα (βάθος 0) ξεκινάει τον μετρητή της εποχής: χτυπάει στο τέλος κάθε εποχής.
				startEpochTimer();

				call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);
			}
			else
			{
				// ΠΡΟΣΘΗΚΗ: Κάθε άλλος κόμβος ελέγχει μετά από JOIN_WAIT_MILLI (+ τυχαία καθυστέρηση, για να μη στέλνουν
				// όλοι μαζί) αν μπήκε στο δέντρο. Αν όχι, στέλνει αίτηση ένταξης (βλ. JoinTimer.fired()).
				call JoinTimer.startOneShot(JOIN_WAIT_MILLI + (call Random.rand16() % TIMER_FAST_PERIOD));
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
	// ΑΦΑΙΡΕΣΗ: Τα events SerialControl.startDone() και SerialControl.stopDone() (σειριακή θύρα).
	
	// ΑΦΑΙΡΕΣΗ: Το event LostTaskTimer.fired(). Ξαναέκανε post τα tasks που είχαν 'χαθεί', αλλά ο LostTaskTimer
	// δεν ξεκινούσε ποτέ. Δεν χρειάζεται αντικατάσταση: αν η sendRoutingTask() βρει τον ασύρματο busy, το
	// RoutingAMSend.sendDone() την ξανακάνει post μόλις τελειώσει η τρέχουσα αποστολή (αφού η ουρά δεν είναι άδεια).
	
	// ΠΡΟΣΘΗΚΗ: Αίτηση ένταξης στο δέντρο (JoinRequest).
	// Το δέντρο χτίζεται μία φορά και κάθε κόμβος στέλνει το routing μήνυμά του μία φορά. Αν ένας κόμβος δεν ακούσει κανένα
	// routing μήνυμα (θόρυβος ή σύγκρουση), δεν μπαίνει ποτέ στο δέντρο και λείπει από όλες τις εποχές. Γι' αυτό, αν μετά
	// από JOIN_WAIT_MILLI δεν έχει πατέρα, στέλνει broadcast ένα routing μήνυμα ΧΩΡΙΣ δεδομένα (0 bytes). Όποιος γείτονας
	// είναι ήδη στο δέντρο το λαμβάνει και ξαναστέλνει το routing μήνυμά του (βλ. receiveRoutingTask()), οπότε ο κόμβος
	// μπαίνει στο δέντρο με τον κανονικό τρόπο. Επιπλέον μηνύματα στέλνονται μόνο όταν κάποιος κόμβος έχασε το routing.
	event void JoinTimer.fired()
	{
		message_t tmp;

		if ((parentID < 65535) || (joinTries >= JOIN_MAX_TRIES))
		{
			return; // Μπήκε ήδη στο δέντρο ή έστειλε όσες αιτήσεις επιτρέπονται
		}
		if (call RoutingSendQueue.full())
		{
			return;
		}

		call RoutingAMPacket.setDestination(&tmp, AM_BROADCAST_ADDR);
		call RoutingPacket.setPayloadLength(&tmp, 0); // Κενό μήνυμα: το μέγεθος 0 το ξεχωρίζει από το RoutingMsg
		if (call RoutingSendQueue.enqueue(tmp) == SUCCESS)
		{
			joinTries++;
			dbg("SRTreeC", "NodeID= %d : no parent, JoinRequest %u sent \n", TOS_NODE_ID, joinTries);
			if (call RoutingSendQueue.size() == 1)
			{
				post sendRoutingTask();
			}
		}

		// Αν δεν απαντήσει κανείς, ξαναδοκιμάζουμε (το πολύ JOIN_MAX_TRIES φορές συνολικά).
		call JoinTimer.startOneShot(JOIN_WAIT_MILLI + (call Random.rand16() % TIMER_FAST_PERIOD));
	}

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

		// ΑΦΑΙΡΕΣΗ (TODO: 'Στο tag, το routing στέλνεται ΜΟΝΟ μια φορά'): Εδώ υπήρχε το μπλοκ
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
		// ΑΦΑΙΡΕΣΗ (TODO: 'Το να λέω μέσα στο μήνυμα το ποιός είμαι εγώ που το στέλνω είναι άσκοπο, αφού από το
		// interface AMPacket, είπαμε ότι αυτό αναφέρεται στην κεφαλή του πακέτου'): 'mrpkt->senderID=TOS_NODE_ID;'
		// Το ActiveMessage βάζει αυτόματα τη διεύθυνση του αποστολέα στην κεφαλή κάθε πακέτου, οπότε ο παραλήπτης
		// τη βρίσκει με 'call RoutingAMPacket.source(msg)'. Γλιτώνουμε 2 bytes σε κάθε routing μήνυμα.
		mrpkt->depth = curdepth; // Το βάθος του τρέχοντος κόμβου
		// ΠΡΟΣΘΗΚΗ: Μαζί με το βάθος στέλνουμε και τις παραμέτρους του ερωτήματος, ώστε να τις μάθουν οι γείτονες.
		mrpkt->queryType = queryType;
		mrpkt->epochSec = epochSec;
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
	
	// ΠΡΟΣΘΗΚΗ: Χτυπάει μία φορά σε κάθε εποχή, στο slot του κόμβου (βλ. startEpochTimer()).
	// Μέχρι αυτή τη στιγμή τα παιδιά (ένα slot νωρίτερα) έχουν ήδη στείλει τα δεδομένα τους.
	event void EpochTimer.fired()
	{
		roundCounter += 1;

		if (TOS_NODE_ID==0)
		{
			dbg("SRTreeC", "\n ##################################### \n");
			dbg("SRTreeC", "#######   EPOCH   %u    ############## \n", roundCounter);
			dbg("SRTreeC", "#####################################\n");
		}
		// ΑΛΛΑΓΗ: Αφαιρέθηκε το sim_time_string() από την εκτύπωση (το dbg τυπώνει ήδη τον χρόνο).
		dbg("SRTreeC", "NodeID= %d : EpochTimer fired, epoch= %u , depth= %u \n", TOS_NODE_ID, roundCounter, curdepth);

		// ΠΡΟΣΘΗΚΗ: Νέα μέτρηση της εποχής.
		takeMeasurement();

		if (TOS_NODE_ID==0)
		{
			// ΠΡΟΣΘΗΚΗ: Η ρίζα είναι η τελευταία που λειτουργεί στην εποχή (ακριβώς στο τέλος της):
			// τυπώνει το τελικό αποτέλεσμα και ξεκινάει την επόμενη εποχή από την αρχή.
			printResult();
			resetChildData();
		}
		else
		{
			// ΠΡΟΣΘΗΚΗ: Κάθε άλλος κόμβος στέλνει στον πατέρα του μετά από τυχαία καθυστέρηση στο [0, TIMER_SLOT_MILLI/2).
			// Έτσι τα αδέρφια (ίδιο βάθος, ίδιο slot) δεν στέλνουν ταυτόχρονα (λιγότερες συγκρούσεις), και το μήνυμα φτάνει
			// τουλάχιστον μισό slot πριν λειτουργήσει ο πατέρας.
			aggPending = TRUE;
			call AggSendTimer.startOneShot(call Random.rand16() % (TIMER_SLOT_MILLI / 2));
		}
	}

	// ΠΡΟΣΘΗΚΗ: Φτιάχνει το μερικό αποτέλεσμα του υποδέντρου (δική μας μέτρηση + δεδομένα παιδιών) στη δομή
	// του ερωτήματος και το βάζει στην ουρά αποστολής προς τον πατέρα (unicast).
	event void AggSendTimer.fired()
	{
		message_t tmp;
		SumAggMsg* sumMsg;
		AvgAggMsg* avgMsg;
		VarAggMsg* varMsg;
		MaxAggMsg* maxMsg;
		uint8_t len = aggMsgLength();

		aggPending = FALSE;

		if (len == 0)
		{
			dbg("SRTreeC", "AggSendTimer.fired(): unknown queryType= %u \n", queryType);
			return;
		}
		if (call AggSendQueue.full())
		{
			dbg("SRTreeC", "AggSendQueue is FULL!!! \n");
			resetChildData();
			return;
		}

		switch (queryType)
		{
			case 1:
				sumMsg = (SumAggMsg*) (call AggPacket.getPayload(&tmp, len));
				if (sumMsg == NULL) return;
				sumMsg->sum = childSum + measurement;
				break;
			case 2:
				avgMsg = (AvgAggMsg*) (call AggPacket.getPayload(&tmp, len));
				if (avgMsg == NULL) return;
				avgMsg->sum = childSum + measurement;
				avgMsg->count = childCount + 1;
				break;
			case 3:
				varMsg = (VarAggMsg*) (call AggPacket.getPayload(&tmp, len));
				if (varMsg == NULL) return;
				varMsg->sum = childSum + measurement;
				varMsg->sumSq = childSumSq + (uint32_t)measurement * measurement;
				varMsg->count = childCount + 1;
				break;
			case 4:
				maxMsg = (MaxAggMsg*) (call AggPacket.getPayload(&tmp, len));
				if (maxMsg == NULL) return;
				maxMsg->maxVal = (childMax > measurement) ? childMax : measurement;
				break;
		}

		// Το μήνυμα πάει ΜΟΝΟ στον πατέρα. Έτσι ο πατέρας αναγνωρίζει τα παιδιά του (βλ. TODO για το NotifyParentMsg).
		call AggAMPacket.setDestination(&tmp, parentID);
		call AggPacket.setPayloadLength(&tmp, len);

		// Τα δεδομένα των παιδιών αυτής της εποχής μπήκαν στο μήνυμα: μηδενίζουμε για την επόμενη εποχή.
		resetChildData();

		if (call AggSendQueue.enqueue(tmp) == SUCCESS)
		{
			if (call AggSendQueue.size() == 1)
			{
				post sendAggTask();
			}
		}
		else
		{
			dbg("SRTreeC", "AggMsg failed to be enqueued in AggSendQueue!!! \n");
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
	
	// ΑΦΑΙΡΕΣΗ: Τα events NotifyAMSend.sendDone() (NotifyParentMsg) και SerialAMSend.sendDone() (σειριακή θύρα).
	
	// ΠΡΟΣΘΗΚΗ: Event για το AggAMSend (το nesC απαιτεί να υλοποιούνται όλα τα events των interfaces).
	// ΥΛΟΠΟΙΗΣΗ: Η αποστολή τελείωσε: ο ασύρματος είναι ξανά ελεύθερος και, αν υπάρχει κι άλλο μήνυμα στην ουρά, το στέλνουμε.
	event void AggAMSend.sendDone(message_t * msg , error_t err)
	{
		dbg("SRTreeC", "An Agg package sent... %s \n", (err==SUCCESS)?"True":"False");

		// Όπως στο TAG, το μήνυμα στέλνεται μία φορά, χωρίς επιβεβαίωση λήψης (ACK) και χωρίς επαναποστολή.
		AggSendBusy = FALSE;

		if (!(call AggSendQueue.empty()))
		{
			post sendAggTask();
		}
	}
	
	// ΠΡΟΣΘΗΚΗ: Event για το AggReceive.
	// ΥΛΟΠΟΙΗΣΗ: Λήψη δεδομένων συνάθροισης από ένα παιδί. Τα μηνύματα είναι unicast, οπότε φτάνουν εδώ μόνο όσα
	// έχουν προορισμό εμάς, δηλαδή μόνο από τα παιδιά μας. Όπως και στο routing, αντιγράφουμε το μήνυμα στην ουρά λήψης
	// και η επεξεργασία γίνεται στο receiveAggTask().
	event message_t* AggReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		message_t tmp;
		uint32_t untilFire;

		// Δεχόμαστε δεδομένα μόνο για την τρέχουσα εποχή: είτε λίγο πριν χτυπήσει ο δικός μας EpochTimer (το πολύ 2 slots,
		// τότε στέλνουν τα παιδιά), είτε αφού χτύπησε αλλά δεν έχουμε στείλει ακόμα (aggPending). Ένα μήνυμα που φτάνει
		// αργότερα ανήκει σε εποχή που έχουμε ήδη στείλει: το αγνοούμε, αλλιώς θα μετρούσε λάθος στην επόμενη εποχή.
		untilFire = (call EpochTimer.gett0() + call EpochTimer.getdt()) - call EpochTimer.getNow();
		if (!(call EpochTimer.isRunning()) || (!aggPending && untilFire > 2 * TIMER_SLOT_MILLI))
		{
			dbg("SRTreeC", "LATE Agg package from %u ignored \n", call AggAMPacket.source(msg));
			return msg;
		}

		atomic{
		memcpy(&tmp, msg, sizeof(message_t));
		}
		if (call AggReceiveQueue.enqueue(tmp) == SUCCESS)
		{
			post receiveAggTask();
		}
		else
		{
			dbg("SRTreeC", "AggMsg enqueue failed!!! \n");
		}
		return msg;
	}
	
	// ΑΦΑΙΡΕΣΗ: Το event NotifyReceive.receive() (λήψη NotifyParentMsg).
//	event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len)

	// Όταν λαμβάνουμε ένα μήνυμα, εκτελείται αυτό το event
	event message_t* RoutingReceive.receive( message_t * msg , void * payload, uint8_t len)
	{
		error_t enqueueDone;
		message_t tmp;
		uint16_t msource;
		
		msource =call RoutingAMPacket.source(msg);
		
		dbg("SRTreeC", "### RoutingReceive.receive() start ##### \n");
		// ΑΛΛΑΓΗ: Ήταν '... from %u  %u \n",((RoutingMsg*) payload)->senderID , msource);'. Το senderID δεν υπάρχει πια,
		// τυπώνουμε μόνο το msource (ο αποστολέας από την κεφαλή του πακέτου).
		dbg("SRTreeC", "Something received!!!  from %u \n", msource);
		//dbg("SRTreeC", "Something received!!!\n");
#ifdef PRINTFDBG_MODE		
		// ΑΛΛΑΓΗ: Αφαιρέθηκε το 'npm=%u' / 'sizeof(NotifyParentMsg)', γιατί ο τύπος NotifyParentMsg δεν υπάρχει πια.
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
	
	// ΑΦΑΙΡΕΣΗ: Το event SerialReceive.receive() (σειριακή θύρα).
	
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
			// ΑΦΑΙΡΕΣΗ: 'setLostRoutingSendTask(TRUE);' (νεκρός μηχανισμός 'lost task').
			// Δεν χάνεται τίποτα: το RoutingAMSend.sendDone() θα ξανακάνει post το task, αφού η ουρά δεν είναι άδεια.
			return;
		}
		
		radioRoutingSendPkt = call RoutingSendQueue.dequeue(); // Αφαιρούμε το 1ο μήνυμα από την ουρά
		
		//call Leds.led2On();
		//call Led2Timer.startOneShot(TIMER_LEDS_MILLI);
		mlen= call RoutingPacket.payloadLength(&radioRoutingSendPkt); // Παίρνουμε το μέγεθος του μηνύματος
		mdest=call RoutingAMPacket.destination(&radioRoutingSendPkt); // Παίρνουμε τον αποδέκτη του μηνύματος
		// ΑΛΛΑΓΗ: Ήταν 'if(mlen!=sizeof(RoutingMsg))'. Δεχόμαστε και μέγεθος 0 (αίτηση ένταξης, βλ. JoinTimer.fired()).
		if((mlen!=sizeof(RoutingMsg)) && (mlen!=0))
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
	// ΑΦΑΙΡΕΣΗ: Το task sendNotifyTask() (αποστολή NotifyParentMsg).
	////////////////////////////////////////////////////////////////////
	//*****************************************************************/
	///////////////////////////////////////////////////////////////////
	/**
	 * dequeues a message and processes it
	 */
	
	task void receiveRoutingTask()
	{
		// ΑΦΑΙΡΕΣΗ: 'message_t tmp;' (το χρησιμοποιούσαν μόνο τα NotifyParentMsg που αφαιρέθηκαν).
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

		// ΠΡΟΣΘΗΚΗ: Μέγεθος 0 = αίτηση ένταξης από γείτονα που δεν έχει πατέρα. Αν εμείς είμαστε στο δέντρο (ρίζα ή κόμβος με
		// πατέρα), ξαναστέλνουμε το routing μήνυμά μας μετά από τυχαία καθυστέρηση (για να μην απαντήσουν όλοι οι γείτονες μαζί).
		// Αν το routing μήνυμά μας είναι ήδη προγραμματισμένο, δεν χρειάζεται να κάνουμε κάτι.
		if (len == 0)
		{
			if ((curdepth != 255) && !(call RoutingMsgTimer.isRunning()))
			{
				dbg("SRTreeC", "NodeID= %d : JoinRequest from %u, sending RoutingMsg again \n", TOS_NODE_ID, call RoutingAMPacket.source(&radioRoutingRecPkt));
				call RoutingMsgTimer.startOneShot(1 + (call Random.rand16() % TIMER_FAST_PERIOD));
			}
			return;
		}
				
		if(len == sizeof(RoutingMsg)) // Σίγουρα θα έχει αυτό το μέγεθος
		{
			// ΑΦΑΙΡΕΣΗ: 'NotifyParentMsg* m;'
			RoutingMsg * mpkt = (RoutingMsg*) (call RoutingPacket.getPayload(&radioRoutingRecPkt,len)); // Παίρνει ένα δείκτη στα δεδομένα του μηνύματος
			
			//if(TOS_NODE_ID >0)
			//{
				//call RoutingMsgTimer.startOneShot(TIMER_PERIOD_MILLI);
			//}
			//
			
			// ΑΛΛΑΓΗ: Στις 2 εκτυπώσεις 'mpkt->senderID' -> 'call RoutingAMPacket.source(&radioRoutingRecPkt)' (το senderID αφαιρέθηκε).
			dbg("SRTreeC" , "receiveRoutingTask():senderID= %d , depth= %d \n", call RoutingAMPacket.source(&radioRoutingRecPkt) , mpkt->depth);
#ifdef PRINTFDBG_MODE
			printf("NodeID= %d , RoutingMsg received! \n",TOS_NODE_ID);
			printf("receiveRoutingTask():senderID= %d , depth= %d \n", call RoutingAMPacket.source(&radioRoutingRecPkt) , mpkt->depth);
			printfflush();
#endif
			if ( (parentID<0)||(parentID>=65535))
			{
				// tote den exei akoma patera
				//NOTE: Ο έξυπνιος τρόπος να βρούμε ποιός είναια υτός που έστειλε το μήνυμα είναι η source (αντί για mpkt->senderID)
				parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
				curdepth= mpkt->depth + 1; // Το τρέχον βάθος είναι +1 αυτού που μου έστειλε το μήνυμα
				// ΠΡΟΣΘΗΚΗ: Ο κόμβος μαθαίνει το ερώτημα και την εποχή που διάλεξε η ρίζα.
				// (Αρκεί εδώ, την πρώτη φορά: όλα τα routing μηνύματα έχουν τις ίδιες τιμές.)
				queryType = mpkt->queryType;
				epochSec = mpkt->epochSec;
				dbg("SRTreeC" , "NodeID= %d : learned queryType= %u , epochSec= %u \n", TOS_NODE_ID, queryType, epochSec);

				// ΥΛΟΠΟΙΗΘΗΚΕ (TODO: 'Στο TAG οι κόμβοι χρονοπρογραμματίζονται σύμφωνα με το βάθος τους. Οπότε εδώ που
				// βρίσκουμε το βάθος, μπορούμε να ξεκινάμε έναν timer που θα λέει το πότε λειτουργεί ο κόμβος (startPeriodic)'):
				// Τώρα ξέρουμε το βάθος και την εποχή, οπότε ξεκινάμε τον περιοδικό μετρητή της εποχής (βλ. startEpochTimer()).
				startEpochTimer();
#ifdef PRINTFDBG_MODE
				printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
				printfflush();
#endif
				// ΠΡΟΣΘΗΚΗ: Εκτύπωση με dbg (το printf από πάνω τυπώνει μόνο σε πραγματικό hardware),
				// ώστε να φαίνεται στην προσομοίωση το δέντρο που χτίστηκε.
				dbg("SRTreeC" , "NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);

				// ΑΦΑΙΡΕΣΗ (TODO: 'Εδώ στέλνουμε ένα μήνυμα NotifyParentMsg ... στο TAG αυτό δεν το κάνουμε'):
				// Εδώ ο κόμβος έφτιαχνε ένα NotifyParentMsg (senderID, depth, parentID) και το έβαζε στην NotifySendQueue
				// για τον πατέρα του. Στο TAG ένας κόμβος Α καταλαβαίνει ότι είναι πατέρας του Β όταν λάβει δεδομένα του Β
				// για το query (αφού τα παιδιά στέλνουν δεδομένα μόνο στον πατέρα), οπότε το μήνυμα είναι περιττό.

				// ΥΛΟΠΟΙΗΘΗΚΕ (TODO: 'Κάποιος που έλαβε ένα routing message για πρώτη φορά [...] πρέπει να στείλω
				// αυτό το routing message για να το ακούσουν και οι γείτονές μου'):
				// Η προώθηση γίνεται από τον κώδικα που υπήρχε ήδη λίγο πιο κάτω: ο κόμβος ξεκινάει τον RoutingMsgTimer και,
				// όταν αυτός χτυπήσει (μετά από TIMER_FAST_PERIOD), το RoutingMsgTimer.fired() κάνει broadcast ένα νέο
				// RoutingMsg με το δικό του βάθος. Στο Βήμα 3 το μήνυμα αυτό μεταφέρει πλέον και τα queryType/epochSec
				// (βλ. RoutingMsgTimer.fired()), οπότε το ερώτημα φτάνει σε όλους τους κόμβους μαζί με το δέντρο.

				// ΑΦΑΙΡΕΣΗ: Το 'if (call NotifySendQueue.enqueue(tmp)==SUCCESS) { ... post sendNotifyTask(); }'
				// που έβαζε το NotifyParentMsg στην ουρά αποστολής (συνέχεια της παραπάνω αφαίρεσης).

				// Αν δεν είμαι ο κόμβος 0, ξεκίνα έναν μετρητή για να στείλεις το 'routing message'
				if (TOS_NODE_ID!=0)
				{
					// ΑΛΛΑΓΗ: Ήταν 'call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD);'
					// Προστέθηκε τυχαία καθυστέρηση [0, TIMER_FAST_PERIOD). Με σταθερή καθυστέρηση, οι κόμβοι που άκουσαν το
					// ίδιο routing μήνυμα (π.χ. όλα τα παιδιά της ρίζας) το ξαναέστελναν ΤΑΥΤΟΧΡΟΝΑ, τα μηνύματα θα συγκρούονταν
					// και κάποιοι γείτονες δεν θα άκουγαν κανένα.
					call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD + (call Random.rand16() % TIMER_FAST_PERIOD));
				}
			}
			else
			{
				
				// ΑΛΛΑΓΗ: Ήταν 'if (( curdepth > mpkt->depth +1) || (mpkt->senderID==parentID))'.
				// Το 2ο σκέλος ('το μήνυμα ήρθε από τον πατέρα μου') αφαιρέθηκε μαζί με το senderID και δεν χρειάζεται:
				//  - Στον αρχικό κώδικα η ρίζα ξανάστελνε routing σε κάθε γύρο, οπότε κάθε επανεκπομπή του πατέρα ανάγκαζε
				//    το παιδί να ξαναστείλει κι αυτό routing (περιττές μεταδόσεις). Τώρα το δέντρο χτίζεται μία φορά (Βήμα 1).
				//  - Ο πατέρας ξαναστέλνει routing μόνο όταν βρει μικρότερο βάθος. Τότε για το παιδί ισχύει ήδη
				//    curdepth = (παλιό βάθος πατέρα)+1 > (νέο βάθος πατέρα)+1, άρα το 1ο σκέλος αρκεί.
				// Έτσι ένας κόμβος αλλάζει πατέρα (και ξαναστέλνει routing) ΜΟΝΟ αν βρει συντομότερο μονοπάτι προς τη ρίζα.
				if ( curdepth > mpkt->depth +1)
				{
					// ΑΦΑΙΡΕΣΗ: 'uint16_t oldparentID = parentID;' (χρειαζόταν μόνο για το NotifyParentMsg προς τον παλιό πατέρα).
					
					parentID= call RoutingAMPacket.source(&radioRoutingRecPkt);//mpkt->senderID;
					curdepth = mpkt->depth + 1;
				
#ifdef PRINTFDBG_MODE
					printf("NodeID= %d : curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);
					printfflush();
#endif					
					// ΠΡΟΣΘΗΚΗ: Εκτύπωση με dbg της αλλαγής πατέρα (για να φαίνεται στην προσομοίωση).
					dbg("SRTreeC" , "NodeID= %d : NEW curdepth= %d , parentID= %d \n", TOS_NODE_ID ,curdepth , parentID);

					// ΠΡΟΣΘΗΚΗ: Το βάθος άλλαξε, άρα αλλάζει και η στιγμή που λειτουργεί ο κόμβος μέσα στην εποχή.
					// Ξαναξεκινάμε τον μετρητή (το startPeriodicAt αντικαθιστά την προηγούμενη ρύθμιση).
					startEpochTimer();
					
					// ΑΦΑΙΡΕΣΗ: Τα 2 NotifyParentMsg που στέλνονταν εδώ, ένα στον παλιό πατέρα και ένα στον νέο.
					// Στο TAG δεν χρειάζονται. Επιπλέον η συνθήκη του πρώτου,
					// '(oldparentID<65535) || (oldparentID>0) || (oldparentID==parentID)', ήταν πάντα αληθής,
					// οπότε στελνόταν μήνυμα ακόμα και όταν ο πατέρας δεν είχε αλλάξει.
					
					if (TOS_NODE_ID!=0)
					{
						// ΑΛΛΑΓΗ: Ίδια τυχαία καθυστέρηση με παραπάνω (ήταν 'startOneShot(TIMER_FAST_PERIOD)').
						call RoutingMsgTimer.startOneShot(TIMER_FAST_PERIOD + (call Random.rand16() % TIMER_FAST_PERIOD));
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
			// ΑΦΑΙΡΕΣΗ: 'setLostRoutingRecTask(TRUE);' (νεκρός μηχανισμός 'lost task'). Το μήνυμα απλά αγνοείται.
			return;
		}
		
	}


////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////	
	
	 
	// ΑΦΑΙΡΕΣΗ: Το task receiveNotifyTask(). Επεξεργαζόταν τα NotifyParentMsg: οι κλάδοι 'προσθήκη/διαγραφή παιδιού'
	// ήταν κενοί, η ρίζα τα έστελνε στο PC μέσω σειριακής, και οι υπόλοιποι κόμβοι τα προωθούσαν στον πατέρα τους
	// μέχρι τη ρίζα (πολλές περιττές μεταδόσεις).
	

	////////////////////////////////////////////////////////////////////////
	// ΠΡΟΣΘΗΚΗ: Βγάζει ένα μήνυμα συνάθροισης από την ουρά και το στέλνει στον πατέρα (ίδια λογική με το sendRoutingTask()).
	task void sendAggTask()
	{
		uint8_t mlen;
		uint16_t mdest;

		if (call AggSendQueue.empty())
		{
			return;
		}
		if (AggSendBusy)
		{
			// Θα ξαναγίνει post από το AggAMSend.sendDone(), αφού η ουρά δεν είναι άδεια.
			return;
		}

		radioAggSendPkt = call AggSendQueue.dequeue();
		mlen = call AggPacket.payloadLength(&radioAggSendPkt);
		mdest = call AggAMPacket.destination(&radioAggSendPkt);

		if (mlen != aggMsgLength())
		{
			dbg("SRTreeC", "sendAggTask(): Unknown message!!! \n");
			return;
		}

		if (call AggAMSend.send(mdest, &radioAggSendPkt, mlen) == SUCCESS)
		{
			AggSendBusy = TRUE;
			dbg("Messages", "epoch= %u node= %u to= %u bytes= %u \n", roundCounter, TOS_NODE_ID, mdest, mlen);
		}
		else
		{
			dbg("SRTreeC", "sendAggTask(): send failed!!! \n");
		}
	}

	// ΠΡΟΣΘΗΚΗ: Βγάζει ένα μήνυμα από την ουρά λήψης και προσθέτει το μερικό αποτέλεσμα του παιδιού
	// στο μερικό αποτέλεσμα της τρέχουσας εποχής (childSum, childSumSq, childCount, childMax).
	task void receiveAggTask()
	{
		message_t radioAggRecPkt;
		uint8_t len;
		SumAggMsg* sumMsg;
		AvgAggMsg* avgMsg;
		VarAggMsg* varMsg;
		MaxAggMsg* maxMsg;

		radioAggRecPkt = call AggReceiveQueue.dequeue();
		len = call AggPacket.payloadLength(&radioAggRecPkt);

		// Όλοι ξέρουμε το queryType, άρα και το μέγεθος του μηνύματος που περιμένουμε.
		if (len != aggMsgLength())
		{
			dbg("SRTreeC", "receiveAggTask(): Unknown message (len= %u)!!! \n", len);
			return;
		}

		switch (queryType)
		{
			case 1:
				sumMsg = (SumAggMsg*) (call AggPacket.getPayload(&radioAggRecPkt, len));
				childSum += sumMsg->sum;
				break;
			case 2:
				avgMsg = (AvgAggMsg*) (call AggPacket.getPayload(&radioAggRecPkt, len));
				childSum += avgMsg->sum;
				childCount += avgMsg->count;
				break;
			case 3:
				varMsg = (VarAggMsg*) (call AggPacket.getPayload(&radioAggRecPkt, len));
				childSum += varMsg->sum;
				childSumSq += varMsg->sumSq;
				childCount += varMsg->count;
				break;
			case 4:
				maxMsg = (MaxAggMsg*) (call AggPacket.getPayload(&radioAggRecPkt, len));
				if (maxMsg->maxVal > childMax)
				{
					childMax = maxMsg->maxVal;
				}
				break;
		}
		dbg("SRTreeC", "receiveAggTask(): data from child %u merged \n", call AggAMPacket.source(&radioAggRecPkt));
	}

}
