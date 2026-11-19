import sys, math

D = int(sys.argv[1])
R = float(sys.argv[2])

with open("topology.txt", "w") as f:
    for i in range(D * D):
        for j in range(D * D):
            if i != j and math.hypot(i // D - j // D, i % D - j % D) <= R:
                f.write("%d %d -50.0\n" % (i, j))
