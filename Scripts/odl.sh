#!/bin/bash

#  odl.sh
#  
#
#  Created by Randall Cleveland on 9/2/16.
#  Version 1.1 9/8/16 - fix list error because of empty datagroup
#

## Constants
export bigip_addr="10.241.105.15"
export user="admin"
export passwd="intel123"
export CURL="/usr/bin/curl"

# test id datagroup is empty
#DGL=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print len(input)")
DG=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print input")

EMPTY=0
#echo $EMPTY
if [[ $DG == *"records"* ]]
then
    EMPTY=1
    #echo datagroup contains records $EMPTY;
fi

if [ $EMPTY = 0 ]
then
    I=0
else
    I=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print len(input [\"records\"])")
fi

declare -a array_dg=( )

if [ $I -ge 1 ]
then
    for X in `seq 0 $((I-1))`;
    do
        #echo $x
        ADDR=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print input [\"records\"][${X}][\"name\"]")
        array_dg=( "${array_dg[@]}" "$ADDR" )
        SFC=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print input [\"records\"][${X}][\"data\"]")
        array_dg=( "${array_dg[@]}" "$SFC" )
    done

    dg_length=$((${#array_dg[*]}/2-1))    
fi


if [ "$1" = "add" ]
then
 
    #checking addrss has 3 decimal point    
    var="$2"
    res="${var//[^.]}"
    
    # checking for address and path id is not empty
    if [ ${#res} -eq 3 -a -n "$3" ]
    then
        records=''
        if [ $I -ge 1 ]
        then
            for i in `seq 0 $dg_length`;
            do
                records="$records{\"name\":\"${array_dg[$(($i*2))]}\",\"data\":\"${array_dg[$(($i*2+1))]}\"}"
            done
        fi
        json="{\"records\":[$records{\"name\":\"$2\",\"data\":\"$3\"}]}"
        #echo "$json"
        OUT=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X PUT -d $json https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg)
        echo "add successful"
        OUTF=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print json.dumps(input[\"records\"], sort_keys = False, indent = 4)")
        echo ""
        echo "Current Datagroup - $OUTF"
    else
        echo "add unsuccessful - address format error or path id empty"
    fi
elif [ "$1" = "del" ]
then
    records=''
    DL=0
    if [ $I -ge 1 ]
    then
        for i in `seq 0 $dg_length`;
        do
            if [ "${array_dg[$(($i*2))]}" != "$2" ]
            then
                records="$records{\"name\":\"${array_dg[$(($i*2))]}\",\"data\":\"${array_dg[$(($i*2+1))]}\"}"
            elif [ "${array_dg[$(($i*2))]}" == "$2" ]
            then
                DL=1
            fi
        done
        
        if [ $DL = 1 ]
        then
            json="{\"records\":[$records]}"
            #echo "$json"
            OUT=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X PUT -d $json https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg)
            echo "del successful"
            if [ $I -gt 1 ]
            then
                OUTF=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print json.dumps(input[\"records\"], sort_keys = False, indent = 4)")
                echo ""
                echo "Current Datagroup - $OUTF"
            else
                echo "datagroup is empty"
            fi
        else
            echo "del unsuccesful - address not found"
            OUTF=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print json.dumps(input[\"records\"], sort_keys = False, indent = 4)")
            echo ""
            echo "Current Datagroup - $OUTF"
        fi
    else
        echo "del unsuccesful"
        echo "datagroup is empty"
    fi
elif [ "$1" = "reset" ]
then
    if [ $I -ge 1 ]
    then
        OUT=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X PUT -d '{"records":[ ]}' https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg)
        echo "reset successful"
    else
        echo "Datagroup was empty"
    fi
    
elif [ "$1" = "list" ]
then
    if [ $I -ge 1 ]
    then
        OUTF=$($CURL -sS -k -u $user:$passwd -H 'Content-Type: application/json' -X GET https://$bigip_addr/mgmt/tm/ltm/data-group/internal/~Common~client_dg | python -c "import sys,json; input=json.load(sys.stdin); print json.dumps(input[\"records\"], sort_keys = False, indent = 4)")
        echo "list Current Datagroup - $OUTF"
    else
        echo "datagroup is empty"
    fi
else
    echo "usage - "
    echo "odl.sh add address/32 path_id"
    echo "odl.sh del address/32"
    echo "reset"
    echo "list"
fi





