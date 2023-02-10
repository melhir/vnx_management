check_ww(){
  [[ "$wwnn" =~ ^\([a-fA-F0-9]{2}:\){8}[a-fA-F0-9]{2}$ ]]
  wwnn_result=$?
  [[ "$wwpn" =~ ^\([a-fA-F0-9]{2}:\){8}[a-fA-F0-9]{2}$ ]]
  wwpn_result=$?
}
get_initiators_id() {
  if [[ ${#hbuids[@]} == 0 ]]
  then
    printf "Provide ilo user: "
    read ilo_user
    printf "Provide ilo password: "
    read ilo_password
    for i in ${!ilos[@]}
    do
      wwnn=$(curl -s https://${ilos[i]}/redfish/v1/Systems/1/BaseNetworkAdapters/2/  -k -u $ilo_user:$ilo_password -L | jq ."FcPorts"[0]."WWNN")
      wwpn=$(curl -s https://${ilos[i]}/redfish/v1/Systems/1/BaseNetworkAdapters/2/  -k -u $ilo_user:$ilo_password -L | jq ."FcPorts"[0]."WWPN")
      if [ $wwnn == "null" ] || [ $wwpn =="null" ]
      then
        echo "WWNN/WWPN cannot be extracted from ilo, you need to provide it manually because lower generation ilo doesn't provide data about HBA"
        while [[ ! "${wwnn}" =~ ^([a-fA-F0-9]{2}:){7}[a-fA-F0-9]{2}$ ]] || [[ ! "${wwpn}" =~ ^([a-fA-F0-9]{2}:){7}[a-fA-F0-9]{2}$ ]]
        do
          echo "WWNN for ${hosts[i]}"
          echo "please provide WWNN with format XX:XX:XX:XX:XX:XX:XX:XX"
          printf "WWNN: "
          read wwnn
          echo "please provide WWPN with format XX:XX:XX:XX:XX:XX:XX:XX"
          printf "WWPN: "
          read wwpn
        done
      fi
      id=$(echo $wwnn:$wwpn | sed 's/"//g')
      hbuids+=($id)
    done
  fi
}
check_storage_group() {
  x=$(naviseccli -h $vnx_ip storagegroup -list -gname $1 | grep $2 | wc -l)
  if [ $x -lt 4 ]
  then
    echo 0
  else
    echo 1
  fi
}
create_storage_group(){
  for i in ${!hosts[@]}
  do
    #checkin if storage group exist
    naviseccli -h $vnx_ip storagegroup -list -gname ${hosts[i]} > /dev/null
    navi=$?
    if [ $navi -ne 0 ]
    then
      naviseccli -h $vnx_ip storagegroup -create -gname ${hosts[i]}
    elif [ $navi -eq 0 ]
    then
      echo "storage group exist"
    else
      echo "trouble with connection - exiting"
      exit 1
    fi
  done
}
add_initiators(){
  for i in ${!hbuids[@]}
  do
    j=$(check_storage_group "${hosts[i]}" "${hbuids[i]}")
    while [ $j -eq 0 ]
    do
      #checkin if the initiator is already in storage group
      naviseccli -h $vnx_ip port -list -hba | grep ${hbuids[i]} | wc -l
      if [[ $? == 0 ]]
      then
        for S in ${!sps[@]}
        do
          echo "Adding initiator to hosts and putting in the storage group"
          naviseccli -h $vnx_ip storagegroup -setpath -gname ${hosts[i]} \
                                                -hbauid ${hbuids[i]} \
                                                -type 3 -ip ${ips[i]} \
                                                -host ${hosts[i]}.${system}.ts.wro.nsn-rdnet.net \
                                                -sp ${sps[S]:0:1} -spport ${sps[S]:1:2} -failovermode 4 -o
          sleep 10
        done
      fi
      sleep 5
      j=$(check_storage_group "${hosts[i]}" "${hbuids[i]}")
    done
  done
}

remove_storage_group(){
  for i in ${hosts[@]}
  do
    #checkin if storage group exist
    naviseccli -h $vnx_ip storagegroup -list -gname ${hosts[i]} > /dev/null
    navi=$?
    if [[ $navi -eq 0 ]]
    then
      naviseccli -h $vnx_ip storagegroup -destroy -gname ${hosts[i]} -o
    elif [[ $navi -ne 0 ]]
    then
      echo "storage group exist"
    else
      echo "trouble with connection - exiting"
      exit 1
    fi
  done
}

remove_initiators(){
  for i in ${hosts[@]}
  do
    #checkin if the initiator is already in storage group
    naviseccli -h $vnx_ip port -list -gname ${hosts[i]} | grep ${system}> /dev/null
    navi=$?
    if [[ $navi -eq 0 ]]
    then
      naviseccli -h $vnx_ip port -removeHBA -host ${hosts[i]} -o
    else
      echo "initiator doesn't exist"
      exit 1
    fi
  done
}

create_luns(){
  printf "Provide luns sp: "
  read luns_sp
  echo "creating luns"
  for i in ${!luns_names[@]}
  do
    naviseccli -h $vnx_ip lun -list -name ${luns_names[i]} > /dev/null
    if [[ $? == 0 ]]
    then
      echo "Lun exist removing"
      naviseccli -h $vnx_ip lun -destroy -name ${luns_names[i]} -o
    fi
    naviseccli -h $vnx_ip lun -create -type Thin -capacity ${luns_sizes[i]} \
                                  -deduplication on -sq gb -poolname ${luns_sp} \
                                  -name ${luns_names[i]} -o
    sleep 5
  done
}
delete_luns(){
 echo "deleting luns"
  for i in ${!hosts[@]}
  do
    naviseccli -h $vnx_ip storagegroup -removehlu -gname ${hosts[i]} -hlu 0 1 2 3 4 5 6 7 8 10 11 -o
  done
  for n in ${!luns_names[@]}
  do
    naviseccli -h $vnx_ip lun -list -name ${luns_names[n]} > /dev/null
    if [[ $? == 0 ]]
    then
      naviseccli -h $vnx_ip lun -destroy -name ${luns_names[n]} -o > /dev/null
    else
      echo "lun doesn't exist"
    fi
  done
}

assign_luns(){
  echo "assigning luns to storage group"

  for i in ${!hosts[@]}
  do
    esx="Esx"$((i+1))
    for n in ${!luns_names[@]}
    do
      lun_id=$(naviseccli -h $vnx_ip lun -list -name ${luns_names[n]} -o | grep "LOGICAL UNIT NUMBER" | tr -dc 0-9)
      if [[ "${luns_names[n]}" == *"${esx}"*  ]]
      then
        naviseccli -h $vnx_ip storagegroup -addhlu -gname ${hosts[i]} -hlu ${luns_ids[n]} -alu $lun_id -nonshared -o
      elif [[ "${luns_names[n]}" == *"Esx"* ]]
      then
        echo "nothing to do"
      else
        naviseccli -h $vnx_ip storagegroup -addhlu -gname ${hosts[i]} -hlu ${luns_ids[n]}  -alu $lun_id -o
      fi
      sleep 5
    done
  done
}
export_luns(){
  exportfile=luns_naa_$system_`date +%Y-%m%d_%H-%M-%S`.txt
  touch $exportfile
  echo "exporting luns"
  for i in ${!luns_names[@]}
  do
    id=$(naviseccli -h $vnx_ip lun -list -name ${luns_names[i]} | grep "UID" | sed -r 's/^.{6}//' | sed 's/://g' | tr '[:upper:]' '[:lower:]')
    lun_naa=naa."${id}"
    echo ${luns_names[i]} >> $exportfile
    echo $lun_naa >> $exportfile
  done
}
