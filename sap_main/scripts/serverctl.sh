#!/bin/bash

cd $(dirname $0)/..
basehome=$(pwd)

cd $basehome
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$basehome/lib:$basehome/lib64
source $basehome"/scripts/var.sh"

function usage
{
    echo "$0 role start|stop|restart|offline|online" && exit 1
}

if [ "$1" == "-h" ]
then
    usage
fi

role=$1
action=$2

if [ "X$role" == "X" -o "X$action" == "X" ]
then
    echo "parameters required, -h for help"
    exit 1
fi

exec_base="runscript.pl"
cmd_prefix="$exec_base -n $role -d $basehome"


function do_offline
{
    local tip=`hostname -i`
    local ret=0
    for f in $status_filename
    do
        if [ -f $basehome/www/$f ]
        then
            mv -f $basehome/www/$f{,.off}
        fi
    done

    for c in $clsname
    do
        ssh $sapcm "$cmpath/bin/cm_ctrl -f $cmpath/conf/cm_ctrl.cfg -c setnodeoffline -v '$c|$tip|$service'"
    done

    ret=$?
    if [ $ret -eq 0 ]
    then
        echo "offline done"
        return 0
    else
        echo "offline failed"
        return 1
    fi 
}

function do_online 
{
    local tip=`hostname -i`
    local ret=0
    for f in $status_filename
    do
        rm -f $basehome/www/$f.off
        touch $basehome/www/$f
    done

    for c in $clsname
    do
        ssh $sapcm "$cmpath/bin/cm_ctrl -f $cmpath/conf/cm_ctrl.cfg -c setnodeonline -v '$c|$tip|$service'"
    done

    ret=$?
    if [ $ret -eq 0 ]
    then
        echo "online done"
        return 0
    else
        echo "online failed"
        return 1
    fi
}

function save_state
{
    local tip=`hostname -i`
    local state_online=0
    local ret=0
    rm -f $basehome/www/*.restarting
    for f in $status_filename
    do
        if [ -f $basehome/www/$f ]
        then
            state_online=1
            mv -f $basehome/www/$f{,.restarting}
        fi
    done

    if [ $state_online -eq 1 ]
    then
        for c in $clsname
        do
            ssh $sapcm "$cmpath/bin/cm_ctrl -f $cmpath/conf/cm_ctrl.cfg -c setnodeoffline -v '$c|$tip|$service'"
        done
        ret=$?
        if [ $ret -eq 0 ]
        then
            sleep 5s
            echo "offline done"
        else
            echo "offline failed"
        fi
    fi
    return $ret
}

function restore_state
{
    local tip=`hostname -i`
    local state_online=0
    local ret=0
    for f in $status_filename
    do
        if [ -f $basehome/www/$f.restarting ]
        then
            state_online=1
            mv -f $basehome/www/$f{.restarting,}
        fi
    done

    if [ $state_online -eq 1 ]
    then
        for c in $clsname
        do
            ssh $sapcm "$cmpath/bin/cm_ctrl -f $cmpath/conf/cm_ctrl.cfg -c setnodeonline -v '$c|$tip|$service'"
        done
        ret=$?
        if [ $ret -eq 0 ]
        then
            echo "online done"
        else
            echo "online failed"
        fi
    fi
    return $ret
}

function sig_kill
{
    local pid=$1
    ps --pid=$pid >/dev/null 2>&1    
    ret=$?

    try=0
    while [ $ret -eq 0 -a $try -lt 5 ]
    do
        kill -9 $pid >/dev/null 2>&1
        sleep 2
        ps --pid=$pid >/dev/null 2>&1
        ret=$?
        let try=try+1
    done
    
    if [ $ret -ne 0 ]
    then
        return 0
    else
        return 1 
    fi
}

function run_start
{
    pid=$(ps -C $exec_base -o pid=,cmd= | grep "$cmd_prefix" | awk '{print $1}')
    if [ "X$pid" != "X" ]
    then
        cpid=$(ps --ppid=$pid -o pid= | awk '{print $1}')
        if [ "X$cpid"  != "X" ]
        then
            echo "$role($cpid) is already running, exit"
            return 1
        else
            echo -n "stop zoobie runscript.pl($pid), "
            sig_kill $pid
            if [ $? -eq 0 ]
            then
                echo "ok"
            else
                echo "failed"
                return 1
            fi
        fi
    fi

    echo -n "starting .."
    scripts/runscript.pl -n $role -d $basehome -b -k start >/dev/null 2>&1
    sleep 2
    pid=$(ps -C $exec_base -o pid=,cmd= | grep "$cmd_prefix" | awk '{print $1}')
    if [ "X$pid" != "X" ]
    then
        cpid=$(ps --ppid $pid -o pid= | awk '{print $1}')
        if [ "X$cpid" != "X" ]
        then
            echo "done($cpid)"
            return 0
        fi
    fi
    echo "failed"
    return 1
}

function run_stop
{
    pid=$(ps -C $exec_base -o pid=,cmd= | grep "$cmd_prefix" | awk '{print $1}')
    if [ "X$pid" = "X" ]
    then
        echo "$role already startd?"
        return 0
    else
        cpid=$(ps --ppid=$pid -o pid= | awk '{print $1}')
    fi

    echo -n "safe stop .."
    scripts/runscript.pl -n $role -d $basehome -k stop >/dev/null 2>&1
    sleep 3

    ps --pid=$pid,$cpid >/dev/null 2>&1

    if [ $? -eq 1 ]
    then
        echo "ok"
        return 0
    else
        echo "failed"
        echo -n "force terminate .."
        sig_kill $pid && sig_kill $cpid
        if [ $? -eq 0 ]; then
            echo "ok"
            return 0
        else
            echo "failed"
            return 1
        fi
    fi
}


case $action in
"offline")
    do_offline
    ;;
"online")
    do_online
    ;;
"start")
    run_start
    ;;
"stop")
    run_stop
    ;;
"restart")
    save_state
    run_stop
    run_start
    restore_state
    ;;
*)
    echo -n "invalid option"
    usage
esac
