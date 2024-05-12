#!/bin/sh

# Debian
for n in `ls -1 debian/ | grep luminum-client*` ; do LCVER=`echo $n | sed -e 's/luminum-client_//g'` ; dpkg-deb --build debian/luminum-client_$LCVER ; done
