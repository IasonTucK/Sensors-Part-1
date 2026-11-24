#!/usr/bin/python
# -*- coding: utf-8 -*-
# Χρήση: python mySimulation.py [αρχείο_τοπολογίας]   (προεπιλογή: topology.txt)

from TOSSIM import *
import sys ,os
import random

t=Tossim([])
f=sys.stdout #open('./logfile.txt','w')
# [Βήμα 10] ΑΛΛΑΓΗ: Ήταν 1000 sec. Η εκφώνηση ζητάει τερματισμό μετά από 800 sec.
SIM_END_TIME= 800 * t.ticksPerSecond()

# [Βήμα 10] ΠΡΟΣΘΗΚΗ: Το αρχείο τοπολογίας μπορεί να δοθεί ως παράμετρος (π.χ. αρχεία από το topology_generator.py).
TOPOLOGY_FILE = sys.argv[1] if len(sys.argv) > 1 else "topology.txt"

print "TicksPerSecond : ", t.ticksPerSecond(),"\n"

t.addChannel("Boot",f)
t.addChannel("RoutingMsg",f)
# [Βήμα 10] ΑΦΑΙΡΕΣΗ: t.addChannel("NotifyParentMsg",f) (το μήνυμα καταργήθηκε).
t.addChannel("Radio",f)
#t.addChannel("Serial",f)
t.addChannel("SRTreeC",f)
#t.addChannel("PacketQueueC",f)
# [Βήμα 10] ΠΡΟΣΘΗΚΗ: Κανάλια για τα αποτελέσματα της ρίζας, τις μετρήσεις των κόμβων και τα μηνύματα συνάθροισης
# (τα χρησιμοποιεί και το check_results.py).
t.addChannel("Results",f)
t.addChannel("Measurements",f)
t.addChannel("Messages",f)

# [Βήμα 10] ΑΛΛΑΓΗ: Πρώτα διαβάζουμε την τοπολογία, ώστε ο αριθμός των κόμβων να βγαίνει από το αρχείο
# (μεγαλύτερο ID + 1) και όχι σταθερά 10. Έτσι η προσομοίωση δουλεύει για οποιοδήποτε topology.txt.
topo = open(TOPOLOGY_FILE, "r")

if topo is None:
	print "Topology file not opened!!! \n"

links = []
for line in topo.readlines():
  s = line.split()
  if (len(s) > 0):
    links.append((int(s[0]), int(s[1]), float(s[2])))
topo.close()
NUM_NODES = max([max(a, b) for (a, b, g) in links]) + 1
print "Topology:", TOPOLOGY_FILE, " Nodes:", NUM_NODES, " Links:", len(links), "\n"

# [Βήμα 10] ΑΛΛΑΓΗ: Ήταν 'bootAtTime(10*t.ticksPerSecond() + i)' για i=0..9.
# Κάθε κόμβος κάνει boot στα 10 sec συν μια τυχαία, διαφορετική καθυστέρηση 0..1023 ticks (1 tick = 0.1 ns).
# Ο κόμβος αρχικοποιεί τη γεννήτρια τυχαίων αριθμών με sim_time() % 1024 τη στιγμή του boot, οπότε έτσι η ρίζα
# διαλέγει διαφορετικό ερώτημα/εποχή σε κάθε εκτέλεση (πριν, το seed της ρίζας ήταν πάντα 0). Η καθυστέρηση είναι
# αμελητέα, οπότε τα ρολόγια των κόμβων παραμένουν πρακτικά συγχρονισμένα.
bootOffsets = random.sample(range(1024), NUM_NODES)
for i in range(0, NUM_NODES):
	m=t.getNode(i)
	m.bootAtTime(10*t.ticksPerSecond() + bootOffsets[i])

r=t.radio()
for (a, b, g) in links:
    print " ", a, " ", b, " ", g
    # TEST: η σύνδεση 1->7 προστίθεται στα 11 sec, αφού ο κόμβος 1 έχει ήδη στείλει το routing μήνυμά του
    if not (a==1 and b==7): r.add(a, b, g)

mTosdir = os.getenv("TINYOS_ROOT_DIR")
noiseF=open(mTosdir+"/tos/lib/tossim/noise/meyer-heavy.txt","r")
lines= noiseF.readlines()

for line in  lines:
	str1=line.strip()
	if str1:
		val=int(str1)
		for i in range(0, NUM_NODES): # [Βήμα 10] ΑΛΛΑΓΗ: ήταν range(0,10)
			t.getNode(i).addNoiseTraceReading(val)
noiseF.close()
for i in range(0, NUM_NODES): # [Βήμα 10] ΑΛΛΑΓΗ: ήταν range(0,10)
	t.getNode(i).createNoiseModel()
	
ok=False
#if(t.getNode(0).isOn()==True):
#	ok=True
h=True
linkAdded=False
while(h):
	try:
		h=t.runNextEvent()
		#print h
	except:
		print sys.exc_info()
#		e.print_stack_trace()

	if (not linkAdded) and t.time() >= 11*t.ticksPerSecond():
		r.add(1, 7, -50.0)
		linkAdded=True
	if (t.time()>= SIM_END_TIME):
		h=False
	if(h<=0):
		ok=False

print "Node 0 connected with node 1" , r.connected(0,1) , r.connected(1,0)
print "Node 0 connected with node 2" , r.connected(0,2) , r.connected(2,0)
print "Node 1 connected with node 7" , r.connected(1,7) , r.connected(7,1)
print "Node 2 connected with node 3" , r.connected(2,3) , r.connected(3,2)
print "Node 4 connected with node 8" , r.connected(4,8) , r.connected(8,4)
