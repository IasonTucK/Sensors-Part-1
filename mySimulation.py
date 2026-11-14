#!/usr/bin/python

from TOSSIM import *
import sys ,os
import random

t=Tossim([])
f=sys.stdout #open('./logfile.txt','w')
SIM_END_TIME= 1000 * t.ticksPerSecond() # This is how long the simulation will run (1000 seconds)

print "TicksPerSecond : ", t.ticksPerSecond(),"\n"

# DBG messases with the following labels
t.addChannel("Boot",f) # Note: Only for development
t.addChannel("Radio",f) # Note: Only for development
t.addChannel("RoutingMsg",f)
t.addChannel("NotifyParentMsg",f)
#t.addChannel("Serial",f)
t.addChannel("SRTreeC",f)
t.addChannel("PacketQueueC",f)
t.addChannel("Results",f)

# Nodes from 0 to 9
for i in range(0,10):
	m=t.getNode(i) # Create a node with ID i
	# TODO: I can boot the nodes when I want, but not all of them at time 0 seconds
	# Note: Even the nodes that are not in the topology file are initiazed, but that's ok
	m.bootAtTime(10*t.ticksPerSecond() + i) # Boot at 10+ seconds
	

# Read the topology file, split the lines and add the specified dB sound
# Note: If too slow, give more than 1 cores and 1Gb of RAM
topo = open("topology.txt", "r")

if topo is None:
	print "Topology file not opened!!! \n"


	
r=t.radio()
lines = topo.readlines()
for line in lines:
  s = line.split()
  if (len(s) > 0):
    print " ", s[0], " ", s[1], " ", s[2];
    r.add(int(s[0]), int(s[1]), float(s[2]))

mTosdir = os.getenv("TINYOS_ROOT_DIR")
noiseF=open(mTosdir+"/tos/lib/tossim/noise/meyer-heavy.txt","r")
lines= noiseF.readlines()

for line in  lines:
	str1=line.strip()
	if str1:
		val=int(str1)
		for i in range(0,10):
			t.getNode(i).addNoiseTraceReading(val)
noiseF.close()
for i in range(0,10):
	t.getNode(i).createNoiseModel()
	
ok=False
#if(t.getNode(0).isOn()==True):
#	ok=True

# Here we run the simulator
h=True
while(h):
	try:
		h=t.runNextEvent()
		#print h
	except:
		print sys.exc_info()
#		e.print_stack_trace()

	if (t.time()>= SIM_END_TIME): # If the running time surpasses the specified simulation limit, stop the simulation
		h=False
	if(h<=0):
		ok=False


# Remove the prints
print "Node 0 connected with node 1" , r.connected(0,1) , r.connected(1,0)
print "Node 0 connected with node 2" , r.connected(0,2) , r.connected(2,0)
print "Node 1 connected with node 7" , r.connected(1,7) , r.connected(7,1)
print "Node 2 connected with node 3" , r.connected(2,3) , r.connected(3,2)
print "Node 4 connected with node 8" , r.connected(4,8) , r.connected(8,4)
