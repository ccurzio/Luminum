#!/bin/sh

# Debian
for n in `ls -1 | grep luminum-server*` ; do LCVER=`echo $n | sed -e 's/luminum-server-//g'` ; dpkg-deb --build luminum-server-$LCVER ; done
