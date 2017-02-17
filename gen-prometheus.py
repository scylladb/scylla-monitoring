from sys import argv
from string import split
ips=split(argv[1],",")
port=argv[2]
print "- targets:"
for addr in map(lambda x: x + ":" + port, ips):
    print "  - " + addr
