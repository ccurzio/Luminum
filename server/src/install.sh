#!/bin/sh
#
openssl req -x509 -newkey rsa:4096 -keyout /opt/luminum/LuminumServer/conf/luminum.key -out /opt/luminum/LuminumServer/conf/luminum.crt -sha256 -days 730
openssl pkcs12 -export -out /opt/luminum/LuminumServer/conf/luminum.pfx -inkey /opt/luminum/LuminumServer/conf/luminum.key -in /opt/luminum/LuminumServer/conf/luminum.crt
