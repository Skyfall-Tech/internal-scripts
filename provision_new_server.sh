#!/usr/bin/env sh
#Author: Aaron Johnson
#Comment: This script is not intended to be portable or fail-safe, and is used in my personal provisioning process.

name_old=$(cat /etc/hostname)
#Below command preserved in case it is needed to add older OS support
#ipadd_old=$(ifconfig | awk '/inet6/{next;} /127.0.0.1/{next;} /inet/{print $2;}' | grep 172.23)
cidr_old=$(ip a | awk '/inet6/{next;} /127.0.0.1/{next;} /inet/{print $2;}' | grep -E '172.2[31]')
ipadd_old=$(echo $cidr_old | awk -F '/' '{print $1}')
ipc_present=false

# Get user input
echo "Enter new host information."
read -p "Hostname [$name_old]: " name
read -p "IP address (CIDR format) [$cidr_old]: " cidr
# Input sanity check
if [ -z "$name" ]; then
    name=$name_old
fi
if [ -z "$cidr" ]; then
    cidr=$cidr_old
fi
## Validate CIDR
n='([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])'
m='([0-9]|[12][0-9]|3[012])'
if ! echo $cidr | grep -E "^$n(\.$n){3}/$m$" 2>&1 >/dev/null; then
    printf "\nCIDR input is not valid!\n"
    exit 12
fi
# End input sanity check

# Test if 'ipcalc' utility is available
which ipcalc 2>&1 >/dev/null && ipc_present=true

ipadd=$(echo $cidr | awk -F '/' '{print $1}')
echo
printf "Review these changes carefully!\n\n"
if [ "$ipc_present" = true ]; then
    snm=$(ipcalc $cidr | grep Netmask | grep -Eo "($n\.){3}$n")
    snm_old=$(ipcalc $cidr_old | grep Netmask | grep -Eo "($n\.){3}$n")
    printf "+,CURRENT,PENDING\nHostname:,$name_old,$name\nAddress:,$ipadd_old,$ipadd\nCIDR:,$cidr_old,$cidr\nNetmask:,$snm_old,$snm" | column -s, -t
else
    printf "+,CURRENT,PENDING\nHostname:,$name_old,$name\nAddress:,$ipadd_old,$ipadd\nCIDR:,$cidr_old,$cidr" | column -s, -t
fi
echo
read -p "Are you sure you want to apply the changes above? (y/N)" -n 1 -r
if echo $REPLY | grep -Eq '^[Yy]$'; then
    printf "\n Continuing...\n\n"
else
    printf "\n ABORT\n"
    exit 13
fi

# Update /etc/hostname
printf "Update hostname... "
echo $name > /etc/hostname && printf "DONE\n" || exit 1

# Update /etc/hosts
printf "Update /etc/hosts... "
sed -i "/^127.0.0.1/s/.*/127.0.0.1\tlocalhost localhost.localdomain/" /etc/hosts && \
sed -i "/^127.0.1.1/s/.*/127.0.1.1\t$(echo $name | awk -F . '{print $1}') $name/" /etc/hosts &&\
printf "DONE\n" || exit 1

# Update Zabbix Agent
printf "Update Zabbix Agent... "
sed -i "s/${name_old}/${name}/g" /etc/zabbix/zabbix_agentd.conf && printf "DONE\n" || exit 1

# Update IP address
printf "Update IP address... "
if $(grep 'SUSE' /etc/os-release 2>&1 >/dev/null); then
    printf "OpenSuSE... "
    nmcli con mod ens18 ipv4.addresses $cidr && printf "DONE\n" || exit 1
elif $(uname -r | grep 'arch' 2>&1 >/dev/null); then
    printf "Arch Linux... "
    sed -i "s_${cidr_old}_${cidr}_g" /etc/netctl/ens18 && printf "DONE\n" || exit 1
elif $(grep -i 'arch' /etc/os-release 2>&1 >/dev/null); then
    printf "Arch Linux (alternative kernel)... "
    sed -i "s_${cidr_old}_${cidr}_g" /etc/netctl/ens18 && printf "DONE\n" || exit 1
elif $(uname -r | grep -E 'el8' 2>&1 >/dev/null); then
    printf "CentOS 8... "
    nmcli con mod ens18 ipv4.addresses $cidr && printf "DONE\n" || exit 1
elif $(grep 'ubuntu' /etc/os-release 2>&1 >/dev/null); then
    printf "Ubuntu... "
    awk "{sub(_${cidr_old}_,${cidr})}" /etc/netplan/00-installer-config.yaml && printf "DONE\n" || exit 1
else
    printf "FAIL\n\nOS distribution not supported! Update IP address manually before rebooting!\n\n"
fi

# Update SSH host keys
if [ -f /etc/ssh/ssh_host_rsa_key ]; then
    printf "Found old keys. Removing... "
    rm /etc/ssh/ssh*key* && printf "DONE\n" || exit 1
fi
printf "Regenerating host keys... "
ssh-keygen -A >/dev/null && printf "DONE\n" || exit 1

# Remove script after success
if [ -f /root/provision_new_server.sh ]; then
    printf "Removing this script from /root... "
    unlink /root/provision_new_server.sh || exit 1
    printf "DONE\n"
    printf "  (This script can still be found in /opt/prov/bin)\n"
fi

printf "\nReboot to apply all changes.\n\n"

read -p "Would you like to reboot now? (y/N)" -n 1 -r
if echo $REPLY | grep -Eq '^[Yy]$'; then
    printf "\n Rebooting...\n\n"
    shutdown -r now
    exit 42
else
    printf "\nReboot has been deferred.\n"
    exit 0
fi

