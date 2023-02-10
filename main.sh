#!/bin/bash
source functions.sh
vnx_ip=x.x.x.x
hbuids=()
### lun-prefix
system=lun-prefix
### ilos ip addresses
ilos=( 10.0.0.2 10.0.0.3 10.0.0.4 10.0.0.5 )
### man ip for servers
ips=( 10.0.1.2 10.0.1.3 10.0.1.4 10.0.1.5 )
### WWN:WWPN
 hbuids=( 12:31:43:60:54:FF:4F:93:12:31:43:60:54:FF:4F:94
          12:31:43:60:54:FF:4F:95:12:31:43:60:54:FF:4F:96
          12:31:43:60:54:FF:4F:97:12:31:43:60:54:FF:4F:98
          12:31:43:60:54:FF:4F:99:12:31:43:60:54:FF:4F:A0 )
###

hosts=( ${system}_esx1 ${system}_esx2 ${system}_esx3 ${system}_esx4 )
luns_names=( ${system}esx1disk ${system}esx2disk ${system}esx3disk ${system}esx4disk )
luns_ids=(0 0 0 0 )
luns_sizes=(35 35 35 35)
sps=( A0 B0 A1 B1 )

echo "What do you want to do?"
echo "0. Configure naviseccli"
echo "1. Create Storage groups."
echo "2. Add initiators."
echo "3. Create luns."
echo "4. Assign Luns."
echo "5. Export luns."
echo "6. Prepare everything."
echo "7. Delete luns."
echo "8. Remove initiators."
echo "9. Delete Storage groups."
echo "10. Purge everything"
echo -n "Your choice: "
read CHOICE

case $CHOICE in
  0)
    printf "Provide vnx user: "
    read vnx_admin
    printf "Provide vnx password: "
    read vnx_password
    naviseccli -h $vnx_ip -user $vnx_admin -password $vnx_password -scope 0 -AddUserSecurity
  ;;
  1)
    create_storage_group
  ;;
  2)
    get_initiators_id
    add_initiators
  ;;
  3)
    printf "Provide luns sp: "
    read luns_sp
    create_luns
  ;;
  4)
    assign_luns
  ;;
  5)
    export_luns
  ;;
  6)
    create_storage_group
    get_initiators_id
    add_initiators
    create_luns
    assign_luns
    export_luns
  ;;
  7)
    delete_luns
  ;;
  8)
    get_initiators_id
    remove_initiators
  ;;
  9)
    remove_storage_group
  ;;
  10)
    delete_luns
    remove_initiators
    remove_storage_group
  ;;

esac
