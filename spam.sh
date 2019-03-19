#!/bin/bash
iptables -A OUTPUT -p tcp -m multiport --dport 24,25,50,57,105,106,109,110,143,158,209,218,220,465,587 -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p tcp -m multiport --dport 993,995,1109,24554,60177,60179 -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p tcp -m multiport --dport 24,25,50,57,105,106,109,110,143,158,209,218,220,465,587 -j DROP
iptables -A OUTPUT -p tcp -m multiport --dport 993,995,1109,24554,60177,60179 -j DROP
service iptables save
service iptables restart
