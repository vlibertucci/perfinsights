#!/bin/bash
#
# set -e
#
# Vittorio Franco Libertucci
#
# Azure Support - Microsoft
# By running this script you are agreeing to data collection from your VM for analysis to be performed by Microsoft 
#
#
#
# Verify Linux Distro - this will work with RHEL, SuSE, Ubuntu
# Verify if iostat is installed if not it will install
# Collect memory info and stats 
# Collect disk data 
# Collect sar if available
# Collect logs
########################################

exec 2> /var/tmp/linux-reports.log

# Frequency and repetitions for iostat and vmstat
fre=1
#rep=60

#to allow enough time to complete
safetime=20

clear

echo "By running this script you agree for data collection from your Virtual Machine"
echo "The data will be analysed by Microsoft employees."
echo -n "sysstat (enabling iostat) will be installed if not already installed -  Please enter Y or N [ENTER]: "
        
	read answer

if [ "$answer" = "Y" ] || [ "$answer" = "y" ]
  then
    echo " "
    echo -n "Please supply a 15 digit Microsoft case number: "
    read sr
    LEN=$(echo ${#sr})

 if [ $LEN -ne 15 ]; then
        echo $sr "Microsoft case number should be of 15 digits"
        exit
 fi
else

if [ "$answer" = "N" ]
        then
        echo "you answered  "$answer "exiting.." 
        fi
exit
fi

export case=$sr
direc="/var/tmp/$sr"

####################################
#
# Change frequency to collect data
# or go with default of 300 seconds
####################################

echo ""
echo "The data collection for vmstat and iostat is set to 5 minutes (300 seconds) with 1 second intervals"
echo " "
echo -en "Enter a new value to change from default of [300 seconds] "

        read rep

if [ -z "$rep" ]
  then
    rep="300"
fi


if [ $rep -ne 0 -o $rep -eq 0 2>/dev/null ]
then

# An integer is either equal to 0 or not equal to 0.
# 2>/dev/null suppresses error message.
echo " "
    echo "will run vmstat and iostat for $rep seconds"

else

echo ""
    echo "Supplied Input $rep is not an Integer..exiting"
exit
fi


echo " "
echo " "
echo "Proceeding to data collection"

sleepduration=`expr $rep + $safetime`
###############

dd=`date +%d-%h-%Y`                                 
mkdir -p $direc/$sr/`hostname`_$dd
datadir=$direc/$sr/`hostname`_$dd
timest=`date +%d-%h-%Y_%H:%M:%S`


#########################
#
# Verify distro
#
#########################

which python  > /dev/null 2>&1
python_status=`echo $?`  
#echo $python_status

if [ "$python_status" -eq 0 ];  then
#	echo "python is installed"
	distro=`python -c 'import platform ; print platform.dist()[0]'`
	echo " "
	echo "This is Linux distro" $distro
else
	distro=$(awk '/DISTRIB_ID=/' /etc/*-release | sed 's/DISTRIB_ID=//' | tr '[:upper:]' '[:lower:]')
echo $distro
fi


#######################################################
#                                         
#   Verify if iostat is installed if not install it.   
#
########################################################

which iostat > /dev/null 2>&1
iostat_status=`echo $?` 
# echo $iostat_status
if [ "$iostat_status" -eq 0 ];  then 
	echo ""
	echo "iostat already installed..."

elif
	[ $distro = Ubuntu ];  then
	echo "Installing iostat"
	sudo apt-get -y install sysstat

elif
        [ $distro = centos ] || [ $distro = redhat ];  then
	echo "Installing iostat"
	yum -y install sysstat
        yum update -y sysstat

elif
	[ $distro = SuSE ];  then	
	echo "Installing iostat"
	sudo su -c "zypper install -y sysstat"
else
	echo "Not installing iostat for distro $distro script exiting - this script runs on centos, oracle, ubuntu and sles"
exit
fi

	cat /etc/*release > $datadir/vminfo

	echo "uname -a " >> $datadir/vminfo
	echo " " >> $datadir/vminfo
	
	echo " " >> $datadir/vminfo
	echo "uptime " >> $datadir/vminfo
       
	uptime >> $datadir/vminfo
	echo " " >> $datadir/vminfo

	waagent --version >> $datadir/vminfo
	echo " " >> $datadir/vminfo
	
	lsmod >> $datadir/vminfo
	echo "**************************** " >> $datadir/vminfo
	echo " " >> $datadir/vminfo
	
	modinfo hv_storvsc  >> $datadir/vminfo
	echo " " >> $datadir/vminfo
	echo "**************************** " >> $datadir/vminfo
 
	modinfo hv_netvsc >> $datadir/vminfo
	echo "**************************** " >> $datadir/vminfo
	echo " " >> $datadir/vminfo
	
	modinfo hv_utils  >> $datadir/vminfo	
	echo " " >> $datadir/vminfo
	echo "**************************** " >> $datadir/vminfo
	
	modinfo hv_vmbus >> $datadir/vminfo
	echo " " >> $datadir/vminfo
	echo "**************************** " >> $datadir/vminfo

#################################
#
# Collect memory info. and stats
#
#################################

mkdir $datadir/memory
memory="$datadir/memory/memory_$timest.txt"
vmst=$datadir/memory/vmstat_$timest.txt

	echo "Summary for VM `hostname` " > $memory
	echo " " >> $memory
	echo " " >> $memory
	free -m >> $memory
	echo " " >> $memory
	echo "*************************************** " >> $memory
	cat /proc/meminfo >> $memory
	echo " " >> $memory

	echo "Top 30 processe Resident Size memory usage" >> $memory
	ps aux --sort -rss | head -30 >> $memory
	echo "*************************************** " >> $memory
	echo " " >> $memory
	
	echo "Top 30 processes memory usage" >> $memory
	ps aux --sort -pmem | head -30  >> $memory
	echo " " >> $memory
	echo "*************************************** " >> $memory
	echo " " >> $memory


#################################
#
# Collect cpu info. and stats
#
#################################

mkdir $datadir/cpu
cpu="$datadir/cpu/cpu_$timest.txt"

	echo "Summary for VM `hostname` " > $cpu
	echo " " >> $cpu
	echo " " >> $cpu
	echo "*************************************** " >> $cpu
	cat /proc/cpuinfo >> $cpu
	echo " " >> $cpu
	echo " " >> $cpu
	
	echo "Top cpu processes usage" >> $cpu
	ps aux --sort=-pcpu | head -n 20 >> $cpu
	echo "*************************************** " >> $cpu
	echo " " >> $cpu


	
##############################
#
# Collect disk info and stats
#
##############################

mkdir $datadir/disks
disks=$datadir/disks/disks_$timest.txt

	#df -h, df -i, fdisk -l,blkid, /etc/fstab , /etc/mdadm.conf  cat /proc/mdstat	

	echo "disk utilisation" >> $disks
	df -h >> $disks
	echo " " >> $disks

	echo "disk inode utilisation" >> $disks
	df -i >> $disks
	echo " "
	
	echo "disks attached " >> $disks
	fdisk -l >> $disks
	echo " " >> $disks
	
	echo " " >> $disks
	echo "disks blkid " >> $disks
	blkid >> $disks
	echo " " >> $disks

	echo "swap file configuration" >> $disks
	swapon -s >> $disks

	cp /etc/fstab $datadir/disks/
	cp /proc/mdstat $datadir/disks/ > /dev/null 2>&1


#####################
#                   #
# Collect vmstat and#
# iostat            #
#                   #
#####################

echo "collecting data..."

# Collect vmstat and iostat data with normal load 
# Check disk values as per the official values
# https://msdn.microsoft.com/en-us/library/azure/dn197896.aspx
# If required locate no. of processors per VM - grep -i processor /proc/cpuinfo 

	echo "vmstat data" > $vmst
	#strftime does not work with awk on ubuntu 12
	#vmstat 1 2 | awk '{now=strftime("%Y-%m-%d %T "); print now $0}'  >> $vmst

	vmstat $fre $rep  >> $vmst &


iostat_detailed=$datadir/disks/iostat_detailed.txt
iostat_summ=$datadir/disks/iostat_summ.txt

if [ $distro = Ubuntu ]; then
        osver=`grep -i version_id /etc/os-release`
                        if [ $osver = VERSION_ID=\"12.04\" ]; then
                        #iostatcmd1="`iostat -xd $fre $rep > $datadir/disks/iostat_detailed.txt`"
                        iostatcmd1="`iostat -xd $fre $rep > $iostat_detailed`" &
                        iostatcmd2="`iostat $fre $rep > $iostat_summ`" &

                elif [ $osver = VERSION_ID=\"14.04\" ] || [ $osver = VERSION_ID=\"14.10\" ] ;then

                        iostat -yxd $fre $rep  | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_detailed &
                        iostat -y $fre $rep  | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_summ &
                        #iostatcmd1="`iostat -yxd $fre $rep  | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_detailed`" &
                        #iostatcmd2="`iostat -y $fre $rep  | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_summ`" &
                
	fi

#check suse version
elif [ $distro = SuSE ]; then

        osver=`grep -i version /etc/SuSE-release|awk '{print $3}'`

                        if [ $osver = 11 ]; then
                        iostatcmd1="`iostat -xd $fre $rep > $iostat_detailed`" &
                        iostatcmd2="`iostat $fre $rep > $iostat_summ`" &

                elif [ $osver = 12 ] ;then
                        iostatcmd1="`iostat -yxd $fre $rep  | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_detailed`" &
                        iostatcmd2="`iostat -y $fre $rep  | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_summ`" &

	fi

# Not checkking for Centos,Oracle or Rhel version
# if required new [ $distro = centos ] || [ $distro = redhat ];  then


else
	iostat -xd $fre $rep | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_detailed &
        iostat $fre $rep | awk '{now=strftime("%Y-%m-%d %T "); print now $0}' > $iostat_summ &

fi

#

###############
#             # 
#    network  #
#             #
###############

mkdir $datadir/network
network=$datadir/network/network_$timest.txt

echo "N e t w o r k     C o n f i g u r a t i o n..." >> $network
ip addr show >> $network
echo " " >> $network

echo "(Routing table...)" >> $network
netstat -rn >> $network
echo " " >> $network

ip route show >> $network
echo " " >> $network

echo "(DNS Configuration...)" >> $network
cat /etc/resolv.conf  >> $network
echo " " >> $network

echo "(Hosts file...)" >> $network
cat /etc/hosts  >> $network
echo " " >> $network

echo "(Network Connections...)" >> $network
netstat -tulpn >> $network
echo " " >> $network

echo "(Network statistics...)" >> $network
netstat -s >> $network
echo " " >> $network
########################################################
#	
# Collect only last versions of log files and sar data
#
########################################################

mkdir $datadir/log
mkdir -p $datadir/sar
logdir=$datadir/log
sardata=$datadir/sar

ls -ltr /var/log > $logdir/logfiles_listing

if [ $distro = Ubuntu ]; then
	logs=("wtmp" "btmp" "dmesg" "boot.log" "lastlog" "dpkg.log" "kern.log" "waagent.log" "syslog" "cloud-init.log" )
	sarlogs="/var/log/sysstat"
	#cp "${logs[@]}" $logdir > /dev/null 2>&1
 	cp "${logs[@]/#//var/log/}" $logdir
	cp -R $sarlogs/. $sardata > /dev/null 2>&1

elif
        [ $distro = centos ] || [ $distro = redhat ]; then
	logs=("wtmp" "btmp" "dmesg" "boot.log" "lastlog" "yum.log" "messages" "waagent.log" "cron" "secure" "debug")
	sarlogs="/var/log/sa"
	#cp "${logs[@]}" $logdir > /dev/null 2>&1
 	cp "${logs[@]/#//var/log/}" $logdir
	cp -R $sarlogs/. $sardata > /dev/null 2>&1

elif

        [ $distro = SuSE ]; then
	logs=("wtmp" "btmp" "boot.*" "pbl.log" "lastlog" "zypper.log" "cloudregister" "waagent.log" "messages" "warn")
	sarlogs="/var/log/sa"
	#cp "${logs[@]}" $logdir > /dev/null 2>&1
 	cp "${logs[@]/#//var/log/}" $logdir
	cp -R $sarlogs/. $sardata > /dev/null 2>&1

fi

	cp /etc/waagent.conf $logdir > /dev/null 2>&1
	sysctl -a > $logdir/kernel_params.txt 
	
#################################
#
#Collect the data in a tar file
#
#################################

#allow enough time for iostat, vmstat to complete
sleep $sleepduration


        cd $direc
        tar -cvf $case"_"`hostname`_$dd.tar . > /dev/null 2>&1
        mv $case"_"`hostname`_$dd.tar /var/tmp
	gzip /var/tmp/$case"_"`hostname`_$dd.tar
	echo "Please send the file "/var/tmp/$case"_"`hostname`_$dd".tar.gz"
	cd /var/tmp
	rm -Rf $direc/
	
