#!/bin/bash

# 禁止BT下载：
iptables -A FORWARD -m string --string "BitTorrent" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "BitTorrent protocol" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "peer_id=" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string ".torrent" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "announce.php?passkey=" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "torrent" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "announce" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "info_hash" --algo bm --to 65535 -j DROP
iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
iptables -A FORWARD -m string --algo bm --hex-string "|13426974546f7272656e742070726f746f636f6c|" -j 

# 禁止邮箱端口：
iptables -A OUTPUT -p tcp -m multiport --dport 24,25,50,57,105,106,109,110,143,158,209,218,220,465,587 -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p tcp -m multiport --dport 993,995,1109,24554,60177,60179 -j REJECT --reject-with tcp-reset
iptables -A OUTPUT -p tcp -m multiport --dport 24,25,50,57,105,106,109,110,143,158,209,218,220,465,587 -j DROP
iptables -A OUTPUT -p tcp -m multiport --dport 993,995,1109,24554,60177,60179 -j DROP

yum install -y iptables-services
service iptables save
service iptables restart
