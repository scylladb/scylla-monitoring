#!/usr/bin/python

import sys

with open(sys.argv[1], "w") as data_file:
    data_file.write(sys.argv[2])