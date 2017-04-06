#!/bin/bash

############################################
# PerfInsight for Linux systems
# By: Guillaume Ducroix & Vincent Bastianon
#
#######
#
# Script used to test performances on Linux Azure virtual machines
#
#
####### Supported Linux distributions
#
# CentOS 6.8, 7.1, 7.2
# Ubuntu 14.04, 16.04
# RHEL 6.8, 7.2, 7.3
# SLES 12SP1
# Debian 7, 8
#
####### Requirements/Limits
#
# Requires an internet connection to install required software (epel, sysstat, iotop and fio)
# Supports MDADM RAIDs
#
####### Versions
#
# 1.0 - 2016-05-24 - Initial version
# 1.1 - 2016-05-25 - Devices information gathering
# 1.2 - 2016-05-26 - Tests optimization (warm-up phase and several runs)
# 1.3 - 2016-11-04 - Support RedHat
# 1.4 - 2016-11-07 - Script enhancements
# 1.5 - 2016-11-09 - RHEL 6.8, 7.2, 7.3
# 1.6 - 2016-11-10 - SLES 12SP1
# 1.7 - 2016-11-10 - Debian in progress
# 1.8 - 2016-11-14 - Ubuntu 16.04, CentOS 6.8
# 1.9 - 2016-11-15 - Debian 7, Debian 8
# 2.0 - 2016-11-15 - Oracle Linux in progress
# 3.0 - 2016-11-24 - Perfinsights branch
# 3.1 - 2016-11-29 - Adding bench tuning
# 3.2 - 2017-01-24 - Arguments handling and fixes
# 3.3 - 2017-01-25 - Archive output logs
# 3.4 - 2017-02-02 - General counter collection with sysstat
# 3.5 - 2017-04-06 - Added "pointintime" scenario
#
####### To do
#
# * Collect data and output as Windows version
# * Identify LUNs: ls -l /sys/block/*/device
# * Identify kind of RAID
# * Identify disk layout
#
####### To do
#
#  * CPU clock incorrect on CentOS 6.8, 7.20
#
####### Resources
#
# * https://azure.microsoft.com/en-us/documentation/articles/azure-subscription-service-limits/#storage-limits
# * FIO for red hat: http://dag.wieers.com/rpm/packages/fio/
# * http://brick.kernel.dk/snaps/
# * https://pkgs.org
# * FreeBSD https://www.cyberciti.biz/faq/freebsd-hard-disk-information/
#
############################################

# Constants

SCRIPTVERSION=3.4
SCRIPT=`realpath $0`
SCRIPTPATH=${PWD} #`dirname $SCRIPT`
BLUE='\034[0;34m'
RED='\033[0;31m'

# Global variables
global_executiondatetime=$(date +%Y-%m-%d_%H-%M-%S)
global_outputpath=$SCRIPTPATH/log_perfinsight_$global_executiondatetime

global_fioversion=fio-2.8
global_fiopath=mstemp/$global_fioversion
global_sysstatversion=sysstat-11.4.3


global_arg_scenario=''
global_arg_forceprompts=n
global_arg_skipdisks=n
global_bypasssystemdisk=n
global_bypasstempdisk=n
global_arg_repro=n
global_arg_samples=0
global_arg_interval=1
global_arg_debug=n

global_distro=""
global_distroversion=""
global_vmsize=""
global_targetvolume=""
#declare -a global_disklist=($*) 
declare -a global_disklist 
#declare -a global_volumelist=($*)
declare -a global_volumelist
global_currentcount=3
global_threadnumber=1
global_vmmaxiops=0
global_vmmaxthroughput=0
global_vmstoragetier=""

##### Libraries

#source ./TECHNIQUES.source

##### Functions

DisplayOutput(){
	local arg_texttodisplay=$1
	local arg_display=$2
	local arg_header=$3
	local arg_logtofile=$4
	
	#echo $arg_texttodisplay $arg_display $arg_logtofile  > /dev/stderr
	
	local lcurrenttime=$(date +%Y-%m-%d_%H:%M:%S)
	if [ $arg_display -eq 1 ];then
		if [[ ! -z $arg_texttodisplay ]];then
			if [[ "$arg_texttodisplay" == "> "* ]];then
				echo -ne "\e[34m"
			fi
			if [[ "$arg_texttodisplay" == ">> "* ]];then
				echo -ne "\e[94m"
			fi
			if [[ "$arg_texttodisplay" == ">>> "* ]];then
				echo -ne "\e[36m"
			fi
			case $arg_header in
				0)
					echo -n;;
				1)
					echo -ne "\e[31m";;
				2)
					echo -ne "\e[32m";;
				3)
					echo -ne "\e[33m";;
				*)
					echo -n;;
			esac
			
			echo $arg_texttodisplay > /dev/stderr
			if [ ! -z $arg_logtofile ];then
				echo "$lcurrenttime | $arg_texttodisplay" >> $arg_logtofile
			fi
			
			echo -ne "\033[0m"
		else
			echo "" >> $arg_logtofile
		fi
	fi
}

DisplayUsage(){

	echo "" > /dev/stderr
	echo "PerfInsight for Linux $SCRIPTVERSION" > /dev/stderr
	echo "" > /dev/stderr
	echo "Usage: $0 [-s] [-k] [-h] [-f] [-r|-a N] [-i N]" > /dev/stderr
	echo " "
	echo -e "-s|--scenario \t\t [pointintime,diskinfo|diskbenchmark|slowanalysis] (PerfInsight scenario)" > /dev/stderr
	echo -e "-k|--skip \t\t [system|temp|all] (skip system and/or temp disks diskbenchmark)" > /dev/stderr
	echo -e "-f|--force \t\t (force, bypass all prompts)" > /dev/stderr
	echo -e "-a|--samples N \t\t (slowanalysis scenario, specify number of samples to collect), best used with -i" > /dev/stderr
	echo -e "-i|--interval N \t (slowanalysis scenario, specify interval between samples in seconds), best used with -a" > /dev/stderr
	echo -e "-r|--repro \t\t (slowanalysis scenario, used to capture metrics during a slow behavior scenario and let user stop it), can be used with -i but not with -a" > /dev/stderr
	echo -e "-h|--help \t\t Usage" > /dev/stderr
	echo "" > /dev/stderr


	echo -e "**** Examples ****" > /dev/stderr
	echo "" > /dev/stderr
	echo -e "Collect point in time VM status/performance and configuration" > /dev/stderr
	echo -e "\t $0 -s poinintime" > /dev/stderr
	echo "" > /dev/stderr
	echo -e "Run disk benchmark on all disks" > /dev/stderr
	echo -e "\t $0 -s diskbenchmark" > /dev/stderr
	echo "" > /dev/stderr
	echo -e "Run disk benchmark on all disks except OS disk" > /dev/stderr
	echo -e "\t $0 -s diskbenchmark -k system" > /dev/stderr
	echo "" > /dev/stderr
	echo -e "Run slow analysis counter collection for a period of 5 minutes with a sample interval of 5 seconds:" > /dev/stderr
	echo -e "\t $0 -s slowanalysis -a 60 -i 5" > /dev/stderr
	echo "" > /dev/stderr
	echo -e "Run slow analysis counter collection when reproducing a slow behavior with a sample interval of 2 seconds:" > /dev/stderr
	echo -e "\t $0 -s slowanalysis -r -i 2" > /dev/stderr
	echo "" > /dev/stderr
	exit
}

OutputDataToFile(){
	local arg_texttodisplay=$1
	local arg_logtofile=$2
	
	echo $arg_texttodisplay >> $arg_logtofile
}

VerifyUserInput(){
	local arg_text=$1
	local lresultvar=$2
	
	local linput=''
	
	echo "" > /dev/stderr
	echo -en "\e[91m $arg_text " > /dev/stderr
	
	#read -n 1 linput
	
	while [[ "$linput" != "y" && "$linput" != "n" ]]
	do
		read -n 1 linput
	done

	echo -e "\033[0m"
	echo "" > /dev/stderr
	
	#echo "'$linput' .................;;" > /dev/stderr
	eval $lresultvar="'$linput'"
}

IsOSSupported(){
	
	which python > /dev/null 2>&1
	python_status=`echo $?`

	if [ "$python_status" -eq 0 ]; then
		global_distro=`python -c 'import platform ; print platform.dist()[0]'`
	else
		global_distro=$(awk '/DISTRIB_ID=/' /etc/*-release | sed 's/DISTRIB_ID=//' | tr '[:upper:]' '[:lower:]')
	fi

	case $global_distro in
		redhat)
			echo -n;;
		Ubuntu)
			echo -n;;
		centos)
			echo -n;;
		SuSE)
			echo -n;;
		debian)
			echo -n;;
		oracle)
			echo -n;;
		*)
			DisplayOutput " ~ This distribution ($global_distro) is not supported by this script." 1 0 $global_outputpath/perfinsights.log
			exit;;
	esac
	
	global_distroversion=`cat /etc/*release | grep VERSION_ID= | grep -Eo '[0-9]+(\.{0,1})([0-9]+){0,1}'`
	if [ -z $global_distroversion ];then
		global_distroversion=`cat /etc/*release | grep "Red Hat Enterprise Linux Server release" | grep -Eo '[0-9]+(\.{0,1})([0-9]+){0,1}' | head -n 1`
	fi
	if [ -z $global_distroversion ];then
		global_distroversion=`cat /etc/*release | grep "CentOS release" | grep -Eo '[0-9]+(\.{0,1})([0-9]+){0,1}'`
	fi
}

TestModule(){
	local modulename=$1
	local moduleversion=$2

	local lresult=1
	
	if [ -z $moduleversion ]; then
		case $global_distro in
			redhat)
				yum list installed $modulename > /dev/null 2>&1
				lresult=`echo $?`
				#if [ $lresult -ne 0 ]; then
				#	find ./ -name $modulename > /dev/null 2>&1
				#	lresult=`echo $?`
				#fi
				if [ $lresult -ne 0 ]; then
					which $modulename > /dev/null 2>&1
					lresult=`echo $?`
				fi;;
				
			Ubuntu)
				#apt list $modulename > /dev/null 2>&1
				#dpkg-query --list $modulename > /dev/null 2>&1
				#lresult=`echo $?`
				ltempresult=`dpkg-query -l $modulename | tail -n 1 | awk '{print $1}'` > /dev/null 2>&1
				if [[ "$ltempresult" == "ii" ]]; then
					lresult=0
				fi;;
			centos)
				yum list installed $modulename > /dev/null 2>&1
				lresult=`echo $?`;;
			SuSE)
				#yast2 $modulename > /dev/null 2>&1
				#zypper search -i -n $modulename
				rpm -q $modulename > /dev/null 2>&1
				lresult=`echo $?`;;
			debian)
				dpkg -l | grep $modulename > /dev/null 2>&1
				lresult=`echo $?`;;
			oracle)
				yum list installed $modulename > /dev/null 2>&1
				lresult=`echo $?`;;
			*)
		esac
	else
		if [ -d "$moduleversion" ]; then
			lresult=0
		fi
	fi
	
	echo $lresult
}

GetTempDisk(){
	local arg_size=$1
	local arg_sizewithunit=$2
	
	local ltempdisk
	local ltempdisksize
	
	# swapon -s
	
	for ldevice in $(df -h | awk '{print $1}' | grep /dev/)
	do
		for lvolume in $(df -h | grep $ldevice | awk '{print $6}')
		do
			 if [ -e $lvolume/DATALOSS_WARNING_README.txt ];then
				ltempdisk=$lvolume
				break
			fi
		done
	done
		
	local lresult=''
	if [ $arg_size -eq 0 ];then
		if [ $arg_sizewithunit -eq 1 ];then
			lresult=`df | grep -w $ltempdisk | awk '{print $1}'`
		else
			lresult=$ltempdisk
		fi
	elif [ $arg_size -eq 1 ];then
		if [ $arg_sizewithunit -eq 0 ];then
			ltempdisksize=`df | grep $ltempdisk | awk '{print $4}'`
		else
			ltempdisksize=`df -h | grep $ltempdisk | awk '{print $4}'`
		fi
		#ltempdisksize+="G"
		lresult=$ltempdisksize
	fi
	
	echo $lresult
}

GetVMInfo(){
	
	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Virtual Machine" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log
	
	lrefvmsize=""
	lcores=`lscpu | grep "CPU(s):" | grep -Eo '([0-9]+)' | head -n 1`
	lcpuclock=`lscpu | grep MHz | grep -Eo '([0-9]){3}' | sed ':a;s/\B[0-9]\{2\}\>/.&/;ta' | head -n 1`
	lmemory=`awk '/MemTotal/ {print $2}' /proc/meminfo | awk '{$1=($1+1023)/1024/1024;printf "%.2f\n",$1}'`
	ltempdisk=`GetTempDisk 0 0`
	ltempvolume=`GetTempDisk 0 1`
	ltempdisksize=`GetTempDisk 1 1`

	OIFS=$IFS
	IFS=";"
	while IFS='' read -r line || [[ -n "$line" ]]; do
		set -- "$line"
		declare -a sizeArray=($*) 
		lrefcores=${sizeArray[5]}
		if [[ "$lrefcores" != "CPU Cores" ]]; then
			lrefmemory=${sizeArray[6]}
			lreftempsize=${sizeArray[7]}
			lrefcpuclock=${sizeArray[8]}
			if [[ "$lrefcores" == "$lcores" ]]; then
				#echo "$lrefcores - $lrefmemory - $lreftempsize - $lrefcpuclock" > /dev/stderr
				if [[ "$lrefcpuclock" == "$lcpuclock" ]]; then
					if [[ "$lrefmemory" = "$lmemory" ]]; then
						if [[ "$lreftempsize" == "$ltempdisksize" ]]; then
							global_vmsize=${sizeArray[0]}
							break
						fi
					fi
				fi
			fi
		fi
	done < ./linuxvmsizes.csv
	IFS=$OIFS
	
	if [ -z $global_vmsize ];then
		DisplayOutput "-> Virtual machine size could not be identified" 1 0 $global_outputpath/perfinsights.log
	else
		DisplayOutput "-> Size: $global_vmsize" 1 0 $global_outputpath/perfinsights.log
	fi
	
	DisplayOutput "-> Core(s): $lcores" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-> CPU clock: $lcpuclock MHz" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-> Memory: $lmemory GB" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-> Temp disk: $ltempdisk (volume: $ltempvolume)" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-> Temp disk size: $ltempdisksize" 1 0 $global_outputpath/perfinsights.log
	
	if [ ! -z $global_vmsize ];then
		OIFS=$IFS
		IFS=";"
		while IFS='' read -r line || [[ -n "$line" ]]; do
			set -- "$line"
			declare -a slaArray=($*) 
			lrefvmsize=${slaArray[0]}
			
			if [[ "$lrefvmsize" = "$global_vmsize" ]]; then
				global_vmmaxiops=${slaArray[6]}
				global_vmmaxthroughput=${slaArray[7]}
				global_vmstoragetier=${slaArray[14]}
				global_vmstoragetier=${global_vmstoragetier/[^[:alnum:]]/}
				break
			fi
		done < ./linuxvmslas.csv
		IFS=$OIFS
		
		DisplayOutput "-> Max IOPS: $global_vmmaxiops" 1 0 $global_outputpath/perfinsights.log
		DisplayOutput "-> Max throughput: $global_vmmaxthroughput" 1 0 $global_outputpath/perfinsights.log
		DisplayOutput "-> Storage tier: $global_vmstoragetier" 1 0 $global_outputpath/perfinsights.log
		
	fi
}

GetSystemInformation(){

	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Gather system informations" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "-> Linux distribution: $global_distro $global_distroversion" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log
	
	cat /etc/*release >> $global_outputpath/perfinsights.log
	echo "uname -a " >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
	echo -n "uptime: " >> $global_outputpath/perfinsights.log
	uptime >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
	echo "LAD version: " >> $global_outputpath/perfinsights.log
	waagent --version >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
	lsmod >> $global_outputpath/perfinsights.log
	echo "----------------------------------------- " >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
	modinfo hv_storvsc  >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
	echo "----------------------------------------- " >> $global_outputpath/perfinsights.log
	modinfo hv_netvsc >> $global_outputpath/perfinsights.log
	echo "----------------------------------------- " >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
	modinfo hv_utils  >> $global_outputpath/perfinsights.log	
	echo "" >> $global_outputpath/perfinsights.log
	echo "----------------------------------------- " >> $global_outputpath/perfinsights.log
	modinfo hv_vmbus >> $global_outputpath/perfinsights.log
	echo "" >> $global_outputpath/perfinsights.log
}

FindLVMVolGroupFromMountPoint(){
	local lvolume=$1
	local lresultvar=$2
	local lvolgroup=''
	
	df -h | grep -w $lvolume | grep /dev/mapper > /dev/null 2>&1
	local lresult=`echo $?`
	if [[ $lresult -eq 0 ]];then
		local testvar=`df -h | grep -w $lvolume | grep /dev/mapper | awk -F / '{print $4}' | awk '{print $1}'`
		if [[ "$testvar" == *"--"* ]];then
			testvar="${testvar/--/-}"
			DisplayOutput " ~ Volume has a - in the name: $testvar" 1 0 $global_outputpath/perfinsights.log
		else
			lvolgroup=`echo $(df -h | grep -w $lvolume | grep /dev/mapper | awk -F / '{print $4}' | awk '{print $1}' | awk -F "-" '{print $1}')` #> /dev/null 2>&1
			## logvol=`df -h | grep -w $volume | grep /dev/mapper | awk -F - '{print $2}' | awk '{print $1}'`
		fi
	fi
	
	eval $lresultvar="'$lvolgroup'"
}

######## FIND THE LVPATH of an existing FS. Query the lvm using FS' mount point
fileSystem_to_lvPath(){
    FS_TO_QUERY=$1
    #Call like this:  $0 /tmp
    #Relevant commands for debug: blkid, lsblk, dmsetup, lvdisplay, lvs
    #OLD Solution: DEV_MAPPER=$(df -l --output=source $1 | awk '{print $1}' | cut -d"/" -f 4 | tail -1)

    #Find DeviceMapper_MajorMinorNumber for specific fs
    DeviceMapper_MajorMinorNumber=$(lsblk --noheadings --output TYPE,MAJ:MIN,MOUNTPOINT | grep -w lvm | grep -w $FS_TO_QUERY | awk '{print $2}')

    #VG=$(lvs --noheadings --separator : --options lv_kernel_major,lv_kernel_minor,vg_name,lv_name,lv_path | grep $DeviceMapper_MajorMinorNumber | awk -F : '{print $3}')
    #LV=$(lvs --noheadings --separator : --options lv_kernel_major,lv_kernel_minor,vg_name,lv_name,lv_path | grep $DeviceMapper_MajorMinorNumber | awk -F : '{print $4}')
    LV_PATH=$(lvs --noheadings --separator : --options lv_kernel_major,lv_kernel_minor,vg_name,lv_name,lv_path | grep $DeviceMapper_MajorMinorNumber | awk -F : '{print $5}')
    echo $LV_PATH
    #echo "$VG/$LV"
}

######## FIND THE FS (and FS' mountpoint) of an existing LVPATH:
 lvPath_to_fileSystem(){
    LV_PATH=$1
    #Call like this:  $0 /dev/vg00/opt
    #Relevant commands for debug: blkid, lsblk, dmsetup, lvdisplay, lvs
    #OLD Solution: DEV_MAPPER=$(df -l --output=source $1 | awk '{print $1}' | cut -d"/" -f 4 | tail -1)

    #Find DeviceMapper_MajorMinorNumber for specific lv_path
    DeviceMapper_MajorMinorNumber=$(lvs --noheadings --separator : --options lv_kernel_major,lv_kernel_minor,vg_name,lv_name,lv_path | grep $LV_PATH | awk -F : '{print $1":"$2}')

    FS=$(lsblk --noheadings --output TYPE,MAJ:MIN,MOUNTPOINT | grep -w lvm | grep -w $DeviceMapper_MajorMinorNumber | awk '{print $3}')

    echo $FS
}

GetSCSIPath(){
	local arg_device=$1
	local arg_pathsegment=$2
	
	local lresult=-1
	local deviceid=`echo $arg_device | awk -F / '{print $3}'`

	case $arg_pathsegment in
		SCSIBus)
			lresult=`ls -l /sys/block/*/device | grep $deviceid | awk '{print $11}' | awk -F / '{print $4}' | awk -F : '{print $1}'`;;
		SCSILun)
			lresult=`ls -l /sys/block/*/device | grep $deviceid | awk '{print $11}' | awk -F / '{print $4}' | awk -F : '{print $2}'`;;
		SCSIPort)
			lresult=`ls -l /sys/block/*/device | grep $deviceid | awk '{print $11}' | awk -F / '{print $4}' | awk -F : '{print $3}'`;;
		TargetID)
			lresult=`ls -l /sys/block/*/device | grep $deviceid | awk '{print $11}' | awk -F / '{print $4}' | awk -F : '{print $4}'`;;
	esac
	
	echo $lresult

}

GetDiskSpindles(){
	local arg_volume=$1
	local lspindles=1
	
	local lresult=$(TestModule mdadm)
	if [[ $lresult -eq "0" ]]; then
		local ldevice=`df -h | grep -w $arg_volume | awk '{print $1}'`
		mdadm --detail $ldevice > /dev/null 2>&1
		lresult=`echo $?`
		if [[ $lresult -eq 0 ]];then
			lspindles=`mdadm --detail $ldevice | grep "Active Devices" | awk '{print $4}'`
		fi
	fi
	
	lresult=$(TestModule lvm*)
	if [[ $lresult -eq "0" ]]; then
		vgdisplay $arg_volume > /dev/null 2>&1
		lresult=`echo $?`
		if [[ $lresult -eq 0 ]];then
			lspindles=`vgdisplay $arg_volume | grep "Metadata Areas" | awk '{print $3}'`
		fi
	fi
	
	echo $lspindles

}

DisplayDiskInformation(){

	local lresult=''
	local lcount=0
	
	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Disks information" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log
	
	DisplayOutput ">> List disks" 1 0 $global_outputpath/perfinsights.log
	for ldisk in $(fdisk -l | awk '$1=="Disk" && $2 ~ /^\/dev\/.*/ {print $2}')
	do
		if  [[ "$ldisk" != "/dev/ram"* ]];then
			global_disklist[$lcount]=${ldisk/":"/""}
			ldevice=${ldisk/":"/""}
			DisplayOutput "--> $ldevice" 1 0 $global_outputpath/perfinsights.log
			((lcount++))
		fi
	done
	
	DisplayOutput ">> Get mount information" 1 0 $global_outputpath/perfinsights.log
	mount -l >> $global_outputpath/perfinsights.log
	fdisk -l >> $global_outputpath/perfinsights.log
	DisplayOutput ">> Get parted information" 1 0 $global_outputpath/perfinsights.log
	parted -l >> $global_outputpath/perfinsights.log > /dev/null 2>&1
	DisplayOutput ">> Get blkid information" 1 0 $global_outputpath/perfinsights.log
	blkid >> $global_outputpath/perfinsights.log
	DisplayOutput ">> Get lsblk information" 1 0 $global_outputpath/perfinsights.log
	lsblk >> $global_outputpath/perfinsights.log
	DisplayOutput ">> List volumes" 1 0 $global_outputpath/perfinsights.log
	lcount=0
	for ldevice in $(df -h | awk '{print $1}' | grep /dev/)
	do
		for lvolume in $(df -h | grep $ldevice | awk '{print $6}')
		do
			local lvoldevice=""
			local lvolsize=""
			echo "$lvolume" | grep /dev/ > /dev/null 2>&1
			lresult=`echo $?`
			if [[ $lresult -ne 0 ]];then
				if [[ "$lvolume" = "/" ]]; then
					lvoldevice=`df -h | grep -w "/" | head -n 1 | awk '{print $1}'`
				else
					lvoldevice=`df -h | grep "$lvolume" | awk '{print $1}'`
				fi
				lvolsize=`df -h | grep "$lvoldevice" | awk '{print $2}'`
				global_volumelist[$lcount]=$lvolume

				DisplayOutput "--> $lvolume on $lvoldevice ($lvolsize)" 1 0 $global_outputpath/perfinsights.log
				((lcount++))
			fi
		done
	done
	
	if [ $global_distro = redhat ]; then
		echo -n
		#parted print all quit > $global_outputpath/info_diskinfo_parted.txt
	fi
	
	lresult=$(TestModule mdadm)
	if [[ $lresult -ne "0" ]]; then
		DisplayOutput "-> MDADM library is not present" 1 0 $global_outputpath/perfinsights.log
	else
		DisplayOutput ">> Get MDADM information" 1 0 $global_outputpath/perfinsights.log
		for lvolume in "${global_volumelist[@]}"
		do
			lvoldevice=`df -h | grep -w $lvolume | awk '{print $1}'`
			mdadm --detail $lvoldevice > /dev/null 2>&1
			lresult=`echo $?`
			if [[ $lresult -eq 0 ]];then
				#lspindles=`mdadm --detail $lvoldevice | grep "Active Devices" | awk '{print $4}'`
				lspindles=`GetDiskSpindles $lvolume`
				DisplayOutput "--> $lvolume ($lvoldevice) is a mdadm volume with $lspindles spindles" 1 0 $global_outputpath/perfinsights.log
			fi
		done
		##### TODO: test number of volumes to diplay "No LVM volume"
	fi
	lresult=$(TestModule lvm*)
	if [[ $lresult -ne "0" ]]; then
		DisplayOutput "-> LVM library is not present" 1 0 $global_outputpath/perfinsights.log
	else
		DisplayOutput ">> Get LVM information" 1 0 $global_outputpath/perfinsights.log
		lvmdiskscan | grep "LVM physical volume" >> $global_outputpath/perfinsights.log
		DisplayOutput ">>> Get physical volume(s) information" 1 0 $global_outputpath/perfinsights.log
		pvs >> $global_outputpath/perfinsights.log
		pvdisplay >> $global_outputpath/perfinsights.log
		DisplayOutput ">>> Get volume group(s) information" 1 0 $global_outputpath/perfinsights.log
		vgs >> $global_outputpath/perfinsights.log
		vgdisplay >> $global_outputpath/perfinsights.log
		DisplayOutput ">>> Get logical volume(s) information" 1 0 $global_outputpath/perfinsights.log
		lvs >> $global_outputpath/perfinsights.log
		lvdisplay >> $global_outputpath/perfinsights.log
		lvdisplay -m >> $global_outputpath/perfinsights.log
		
		DisplayOutput ">>> List LVM logical volumes" 1 0 $global_outputpath/perfinsights.log
		for lvolume in "${global_volumelist[@]}"
		do
			#echo "$lvolume ${global_volumelist[$ltempcount]}"
			df -h | grep -w $lvolume | grep /dev/mapper > /dev/null 2>&1
			lresult=`echo $?`
			if [[ $lresult -eq 0 ]];then
				lvoldevice=`df -h | grep -w $lvolume | awk '{print $1}'`
				FindLVMVolGroupFromMountPoint $lvolume llvmvolgroupname
				lspindles=`GetDiskSpindles $llvmvolgroupname`
				DisplayOutput "---> $lvolume ($lvoldevice) is a LVM volume group with $lspindles spindle(s)" 1 0 $global_outputpath/perfinsights.log
			fi
		done
		##### TODO: test number of volumes to diplay "No LVM volume"
	fi
}

GetDiskInformation(){

	## Disk_Map
	
	OutputDataToFile "{" $global_outputpath/Disk_Map.json
	OutputDataToFile "    \"diskObj\" : [" $global_outputpath/Disk_Map.json
	OutputDataToFile "        {" $global_outputpath/Disk_Map.json
	lcount=0
	for ldisk in $(fdisk -l | awk '$1=="Disk" && $2 ~ /^\/dev\/.*/ {print $2}')
	do
		if  [[ "$ldisk" != "/dev/ram"* ]];then
			global_disklist[$lcount]=${ldisk/":"/""}
			ldevice=${ldisk/":"/""}
			
			OutputDataToFile "            \"DiskNumber\" : $lcount," $global_outputpath/Disk_Map.json
			OutputDataToFile "            \"DriveName\" : ${global_disklist[$lcount]}," $global_outputpath/Disk_Map.json
			ltempvalue=`fdisk -l $ldevice | grep $ldevice | awk '{print $2}' | tail -n 1`
			if [[ "$ltempvalue" == "*" ]];then
				OutputDataToFile "            \"IsOSDisk\" : true," $global_outputpath/Disk_Map.json
				OutputDataToFile "            \"IsTempDisk\" : false," $global_outputpath/Disk_Map.json
			else
				OutputDataToFile "            \"IsOSDisk\" : false," $global_outputpath/Disk_Map.json
				ltempvalue2=`GetTempDisk 0 1`
				if [[ "$ltempvalue2" == "$ltempvalue" ]];then
					OutputDataToFile "            \"IsTempDisk\" : true," $global_outputpath/Disk_Map.json
				else
					OutputDataToFile "            \"IsTempDisk\" : false," $global_outputpath/Disk_Map.json
				fi
			fi
			ltempvalue=`df -h | grep $ldevice | head -n 1 | awk '{print $6}'`
			OutputDataToFile "            \"Letter\" : \"$ltempvalue\"," $global_outputpath/Disk_Map.json
			OutputDataToFile "            \"Partition\" : 0," $global_outputpath/Disk_Map.json
			OutputDataToFile "            \"PhysicalDiskName\" : \"${global_disklist[$lcount]}\"," $global_outputpath/Disk_Map.json
			ltempvalue=`GetSCSIPath $ldevice SCSIBus`
			OutputDataToFile "            \"SCSIBus\" : $ltempvalue," $global_outputpath/Disk_Map.json
			ltempvalue=`GetSCSIPath $ldevice SCSILun`
			OutputDataToFile "            \"SCSILun\" : $ltempvalue," $global_outputpath/Disk_Map.json
			ltempvalue=`GetSCSIPath $ldevice SCSIPort`
			OutputDataToFile "            \"SCSIPort\" : $ltempvalue," $global_outputpath/Disk_Map.json
			ltempvalue=`GetSCSIPath $ldevice TargetID`
			OutputDataToFile "            \"SCSITargetId\" : $ltempvalue," $global_outputpath/Disk_Map.json
			ltempvalue=`fdisk -l $ldevice | grep $ldevice | awk '{print $2}' | tail -n 1`
			if [[ "$ltempvalue" == "*" ]];then
				ltempvalue=`fdisk -l $ldevice | grep $ldevice | awk '{print $6}' | tail -n 1`
			else
				ltempvalue=`fdisk -l $ldevice | grep $ldevice | awk '{print $5}' | tail -n 1`
			fi
			ltempvalue=${ltempvalue/"G"/""}
			OutputDataToFile "            \"SizeGB\" : $ltempvalue," $global_outputpath/Disk_Map.json
			ltempvalue=`df -h | grep $ldevice | head -n 1 | awk '{print $6}'`
			OutputDataToFile "            \"VolumeName\" : \"$ltempvalue\"" $global_outputpath/Disk_Map.json
			OutputDataToFile "            }," $global_outputpath/Disk_Map.json
			((lcount++))
		fi
	done
	OutputDataToFile "    ]" $global_outputpath/Disk_Map.json
	OutputDataToFile "}" $global_outputpath/Disk_Map.json
	
	## Volume_Map
	
	OutputDataToFile "{" $global_outputpath/Volume_Map.json
	OutputDataToFile "    \"volumeObj\" : [" $global_outputpath/Volume_Map.json
	OutputDataToFile "        {" $global_outputpath/Volume_Map.json
	
	for ldisk in $(fdisk -l | awk '$1=="Disk" && $2 ~ /^\/dev\/.*/ {print $2}')
	do
		
		OutputDataToFile "\"AllocationUnitSize\" : \"4 KB\","  $global_outputpath/Volume_Map.json
		OutputDataToFile "\"ClusterSize\" : 4096,"  $global_outputpath/Volume_Map.json
		OutputDataToFile "\"DiskMap\" :"  $global_outputpath/Volume_Map.json
		OutputDataToFile "{" $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Boot\" : true," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"DiskNumber\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"DriveName\" : \"\\\\.\\PHYSICALDRIVE0\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"IsOSDisk\" : true," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"IsTempDisk\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Letter\" : \"C:\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Partition\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"PhysicalDiskName\" : \"PhysicalDisk0\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSIBus\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSILun\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSIPort\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSITargetId\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SizeGB\" : 127," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"VolumeName\" : \"\"" $global_outputpath/Volume_Map.json
		OutputDataToFile "}," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"DiskpartVolume\" : " $global_outputpath/Volume_Map.json
		OutputDataToFile "{" $global_outputpath/Volume_Map.json
			OutputDataToFile "\"BitLockerEncrypted\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Disks\" : [" $global_outputpath/Volume_Map.json
			OutputDataToFile "{" $global_outputpath/Volume_Map.json
				OutputDataToFile "\"DiskNumber\" : 0," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"FreeGB\" : 2048," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"HealthStatus\" : \"Online\"," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"IsDynamic\" : false," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"IsGpt\" : false," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"PhysicalDiskName\" : \"PhysicalDrive0\"," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"SCSIBus\" : 0," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"SCSILun\" : 0," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"SCSIPort\" : 0," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"SCSITargetId\" : 0," $global_outputpath/Volume_Map.json
				OutputDataToFile "\"SizeGB\" : 127" $global_outputpath/Volume_Map.json
			OutputDataToFile "}" $global_outputpath/Volume_Map.json
			OutputDataToFile "]," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"FileSystem\" : \"NTFS\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Hidden\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Info\" : \"System\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Installable\" : true," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"IsDynamic\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Label\" : \"\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Letter\" : \"C:\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"MountPoints\" : null," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"NoDefaultDriveLetter\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"NumberOfDisks\" : 1," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Offline\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"ReadOnly\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"ShadowCopy\" : false," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Size\" : \"126 GB\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Status\" : \"Healthy\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"Type\" : \"Partition\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"VolumeCapacityGB\" : \"126\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"VolumeFreeSpaceGB\" : \"110\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"VolumeNumber\" : 1" $global_outputpath/Volume_Map.json
		OutputDataToFile "}," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"Disks\" : [" $global_outputpath/Volume_Map.json
			OutputDataToFile "{" $global_outputpath/Volume_Map.json
			OutputDataToFile "\"DiskNumber\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"HealthStatus\" : \"Online\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"PhysicalDiskName\" : \"PhysicalDrive0\"," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSIBus\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSILun\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSIPort\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SCSITargetId\" : 0," $global_outputpath/Volume_Map.json
			OutputDataToFile "\"SizeGB\" : 127" $global_outputpath/Volume_Map.json
			OutputDataToFile "}" $global_outputpath/Volume_Map.json
		OutputDataToFile "]," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"DriveType\" : 3," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"DriveTypeName\" : \"LocalDisk\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"DynamicPhysicalDisks\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"FileSystem\" : \"NTFS\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"FreeGB\" : \"110.840\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"FreePerc\" : \"87.28\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsDataDisk\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsDynamic\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsMirrored\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsMountPoint\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsOSDisk\" : true," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsPartition\" : true," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsPooled\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsRAID5\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsResiliencySimple\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsSimple\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsSpanned\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsStriped\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsSystemDisk\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"IsTempDisk\" : false," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"Label\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"NumOfDisks\" : 1," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"PooledPhysicalDisks\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"SizeGB\" : \"126.998\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"StoragePool\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"Type\" : \"Partition\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"VDisk_ProvisioningType\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"VDisk_ResiliencySettingName\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"VirtualDisk\" : null," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"VolumeID\" : \"C:\"," $global_outputpath/Volume_Map.json
		OutputDataToFile "\"VolumeNumber\" : 1" $global_outputpath/Volume_Map.json
		OutputDataToFile "}," $global_outputpath/Volume_Map.json
	done
	OutputDataToFile "    ]" $global_outputpath/Volume_Map.json
	OutputDataToFile "}" $global_outputpath/Volume_Map.json
}

CheckBaseToolsStatus(){

	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "----------------------------------------- " 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Verify presence of required tools" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "----------------------------------------- " 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log

	### Verify gcc
	lmodulename=''
	case $global_distro in
		redhat)
			lmodulename=gcc;;
		Ubuntu)
			lmodulename=gcc;;
		centos)
			echo -n;;
		SuSE)
			echo -n;;
		debian)
			echo -n;;
		*)
			echo -n;;
	esac
	
	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> $lmodulename already installed..." 1 0 $global_outputpath/perfinsights.log
		else
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			case $global_distro in
				redhat)
					yum install -y $lmodulename > /dev/null 2>&1;;
				Ubuntu)
					apt-get -y install $lmodulename
					;;#> /dev/null 2>&1
				centos)
					echo -n;;
				SuSE)
					echo -n;;
				debian)
					echo -n;;
					#apt get $lmodulename;;
				*)
					DisplayOutput "--> Not installing $lmodulename for global_distro $global_distro script exiting - this script does not run on this Linux distribution" 1 0 $global_outputpath/perfinsights.log
					exit;;
			esac
		fi
	fi
	
	### Verify gcc
	lmodulename=''
	case $global_distro in
		redhat)
			echo -n;;
		Ubuntu)
			lmodulename=make;;
		centos)
			echo -n;;
		SuSE)
			echo -n;;
		debian)
			echo -n;;
		*)
			echo -n;;
	esac
	
	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> $lmodulename already installed..." 1 0 $global_outputpath/perfinsights.log
		else
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			case $global_distro in
				redhat)
					echo -n;;
				Ubuntu)
					apt-get -y install $lmodulename
					;;#> /dev/null 2>&1
				centos)
					echo -n;;
				SuSE)
					echo -n;;
				debian)
					echo -n;;
					#apt get $lmodulename;;
				*)
					DisplayOutput "--> Not installing $lmodulename for global_distro $global_distro script exiting - this script does not run on this Linux distribution" 1 0 $global_outputpath/perfinsights.log
					exit;;
			esac
		fi
	fi
}

CheckDiskToolsStatus(){

	### Verify libiperf0
	lmodulename=''
	case $global_distro in
		redhat)
			echo -n;;
		Ubuntu)
			#lmodulename=libiperf0;;
			echo -n;;
		centos)
			echo -n;;
		SuSE)
			echo -n;;
		debian)
			echo -n;;
		oracle)
			echo -n;;
		*)
			echo -n;;
	esac

	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			apt-get -y install $lmodulename > /dev/null 2>&1
		fi
	fi
	
	### Verify libaio
	lmodulename=''
	case $global_distro in
		redhat)
			lmodulename=libaio-devel;;
		Ubuntu)
			lmodulename=libaio1;;
		centos)
			lmodulename=libaio;;
		SuSE)
			lmodulename=libaio1;;
		debian)
			lmodulename=libaio1;;
		*)
			echo -n;;
	esac

	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> $lmodulename already installed..." 1 0 $global_outputpath/perfinsights.log
		else
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			case $global_distro in
				redhat)
					yum install -y $lmodulename > /dev/null 2>&1;;
				Ubuntu)
					apt-get -y install $lmodulename > /dev/null 2>&1;;
				centos)
					#wget http://mirror.centos.org/centos/7/os/x86_64/Packages/libaio-0.3.109-13.el7.x86_64.rpm
					#rpm -iv libaio-0.3.109-13.el7.x86_64.rpm
					yum install -y $lmodulename > /dev/null 2>&1;;
				SuSE)
					#yast2 -i $lmodulename
					zypper --non-interactive install $lmodulename  > /dev/stderr 2>&1;;
				debian)
					apt-get -y install $lmodulename > /dev/stderr 2>&1;;
				*)
					DisplayOutput "--> Not installing $lmodulename for global_distro $global_distro script exiting - this script does not run on this Linux distribution" 1 0 $global_outputpath/perfinsights.log
					exit;;
			esac
		fi
	fi

	### Verify epel
	lmodulename=''
	case $global_distro in
		redhat)
			echo -n;;
		Ubuntu)
			echo -n;;
		centos)
			lmodulename="epel-release*rpm";;
		SuSE)
			echo -n;;
		debian)
			echo -n;;
		oracle)
			echo -n;;
		*)
			echo -n;;
	esac

	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			if [ $global_distro = centos ]; then
				wget http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-8.noarch.rpm > /dev/null 2>&1
				rpm -Uvh epel-release*rpm > /dev/null 2>&1
			fi
		fi
	fi

	### Verify fio
	lmodulename=''
	case $global_distro in
		redhat)
			lmodulename=fio;;
		Ubuntu)
			lmodulename=fio;;
		centos)
			lmodulename=fio;;
		SuSE)
			lmodulename=fio;;
		debian)
			lmodulename=fio;;
		oracle)
			lmodulename=fio;;
		*)
			echo -n;;
	esac

	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> $lmodulename already installed..." 1 0 $global_outputpath/perfinsights.log
		else
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			case $global_distro in
				redhat)
					CheckBaseToolsStatus
					mkdir mstemp > /dev/null 2>&1
					cd mstemp > /dev/stderr 2>&1
					wget http://brick.kernel.dk/snaps/$global_fioversion.tar.gz > /dev/null 2>&1
					tar -xzvf $global_fioversion.tar.gz > /dev/null 2>&1
					cd $global_fioversion > /dev/stderr 2>&1
					make clean > /dev/null 2>&1
					make > /dev/null 2>&1
					make install > /dev/null 2>&1;;
				Ubuntu)
					apt-get -y install $lmodulename > /dev/null 2>&1;;
				centos)
					if [[ "$global_distroversion" = "6" ]]; then
						#yum install -y libibverbs.x86_64 > /dev/null 2>&1
						wget http://ftp.tu-chemnitz.de/pub/linux/dag/redhat/el6/en/x86_64/rpmforge/RPMS/fio-2.1.7-1.el6.rf.x86_64.rpm > /dev/null 2>&1
						rpm -iv fio-2.1.7-1.el6.rf.x86_64.rpm > /dev/null 2>&1
					fi
					if [[ "$global_distroversion" = "7" ]]; then
						yum install -y $lmodulename > /dev/null 2>&1
					fi;;
				SuSE)
					wget ftp://rpmfind.net/linux/opensuse/distribution/12.3/repo/oss/suse/x86_64/fio-2.0.10-2.1.1.x86_64.rpm > /dev/null 2>&1
					rpm -ivh fio-2.0.10-2.1.1.x86_64.rpm > /dev/null 2>&1;;
				debian)
					apt-get -y install $lmodulename > /dev/null 2>&1;;
				oracle)
					yum install -y $lmodulename > /dev/null 2>&1;;
				*)
					DisplayOutput "--> Not installing $lmodulename for global_distro $global_distro script exiting - this script does not run on this Linux distribution" 1 0 $global_outputpath/perfinsights.log
					exit;;
			esac
		fi
	fi
}

CheckSysToolsStatus(){
	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "----------------------------------------- " 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Verify presence of required system tools" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "----------------------------------------- " 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log
	
	local lresult=0
	
	### Verify sysstat
	local lmodulename='sysstat'
	local lmoduleversion=$global_sysstatversion
	case $global_distro in
		redhat)
			echo -n;;
		Ubuntu)
			echo -n;;
		centos)
			echo -n;;
		SuSE)
			echo -n;;
		debian)
			echo -n;;
		oracle)
			echo -n;;
		*)
			echo -n;;
	esac

	if [ ! -z $lmodulename ]; then
		DisplayOutput ">> Verify $lmodulename" 1 0 $global_outputpath/perfinsights.log
		lresult=$(TestModule $lmodulename $lmoduleversion)
		if [[ $lresult -eq "0" ]]; then
			DisplayOutput "--> $lmodulename already installed..." 1 0 $global_outputpath/perfinsights.log
		else
			DisplayOutput "--> Will download and install $lmodulename" 1 0 $global_outputpath/perfinsights.log
			case $global_distro in
				redhat)
					yum install -y $lmodulename > /dev/null 2>&1;;
				Ubuntu)
					#apt-get -y install $lmodulename #> /dev/null 2>&1
					CheckBaseToolsStatus
					wget https://gdxperfinsight.blob.core.windows.net/packages/$global_sysstatversion.tar.gz #> /dev/null 2>&1
					tar -xzvf $global_sysstatversion.tar.gz > /dev/null 2>&1
					cd $global_sysstatversion
					sh ./configure
					make
					make install
					cd ..
					#apt-get -y install alien
					#alien sysstat-11.5.4-1.src.rpm
					#dpkg -i sysstat_11.5.4-2_amd64.deb
					lresult=`echo $?`
					if [ $lresult -eq 100 ]; then
						DisplayOutput "---> Error installation package. Please run 'sudo dpkg --configure -a' and execute this script again" 1 0 $global_outputpath/perfinsights.log
						exit
					fi
					;;
				centos)
					yum install -y $lmodulename > /dev/null 2>&1;;
				SuSE)
					zypper --non-interactive install $lmodulename  > /dev/stderr 2>&1;;
				debian)
					apt-get -y install $lmodulename > /dev/stderr 2>&1;;
				*)
					DisplayOutput "--> Not installing $lmodulename for global_distro $global_distro script exiting - this script does not run on this Linux distribution" 1 0 $global_outputpath/perfinsights.log
					exit;;
			esac
		fi
	fi
	
}

ConfigureSysstat(){
	local lsamples=$1
	local linterval=$2
	
	cp /etc/default/sysstat /etc/default/systat.ms.bck
	echo 'ENABLED="true"' > /etc/default/sysstat
	
	#cp /etc/cron.d/sysstat /etc/cron.d/sysstat.ms.bck
	#echo 'PATH=/usr/lib/sysstat:/usr/sbin:/usr/sbin:/usr/bin:/sbin:/bin' > /etc/cron.d/sysstat
	# Activity reports every 10 minutes everyday
	#echo '/0.$2 * * * * root command -v debian-sa1 > /dev/null && debian-sa1 1 1' >> /etc/cron.d/sysstat
		
}

GetTestfileSize(){
	local arg_volume=$1
	
	local ltestfilesize=1024M
	#local lvolsize=`df -h | grep $arg_volume | awk '{print $2}' | grep -Eo '([0-9]+)'`
	
	case $global_vmstoragetier in
		Basic)
			ltestfilesize=1024M;;
		Standard)
			ltestfilesize=1024M;;
		Premium)
			ltestfilesize=4096M
			if [ $lvolsize -ge 126 ];then
				echo -n
			fi
			if [ $lvolsize -ge 512 ];then
				echo -n
			fi
			if [ $lvolsize -ge 1024 ];then
				echo -n
			fi;;
		*)
	esac

	echo $ltestfilesize
}

GetDiskMaxIOPS(){
	local arg_volume=$1
	local arg_spindles=$2
	
	local ldiskmaxiops=300
	
	#local ldevice=`df -h | grep -w $arg_volume | awk '{print $1}'`
	#local lvolsize=`df -h | grep -w $arg_volume | awk '{print $2}' | grep -Eo '([0-9]+)'`

	case "$global_vmstoragetier" in
		Basic)
			ldiskmaxiops=300;;
		Standard)
			ldiskmaxiops=500;;
		Premium)
			if [ $lvolsize -ge 126 ];then
				ldiskmaxiops=500
			fi
			if [ $lvolsize -ge 512 ];then
				ldiskmaxiops=2300
			fi
			if [ $lvolsize -ge 1024 ];then
				ldiskmaxiops=5000
			fi;;
		*)
	esac
	
	ldiskmaxiops=$(($ldiskmaxiops * $arg_spindles))
	
	echo $ldiskmaxiops
}

GetQueueDepth(){
	local arg_spindles=$1
	
	local llatency=5
	local lqueuedepth=64
	
	case $global_vmstoragetier in
		Basic)
			llatency=5
			lqueuedepth=$(($llatency * $global_vmmaxiops * $arg_spindles / 100));;
		Standard)
			llatency=5
			lqueuedepth=$(($llatency * $global_vmmaxiops * $arg_spindles / 100));;
		Premium)
			llatency=15
			lqueuedepth=$(($llatency * $global_vmmaxiops * $arg_spindles / 1000));;
		*)
	esac
	
	echo $lqueuedepth
}

RunBasicCollect(){
	GetVMInfo
	GetSystemInformation
	DisplayDiskInformation
}

RunFIO(){
	local arg_volume=$1
	local arg_queuedepth=$2
	local arg_blocksize=$3
	local arg_cachemode=$4
	local arg_timetorun=$5
	local arg_iotype=$6
	local arg_testfilesize=$7
	local arg_threads=$8
	local arg_currentcount=$9
	#local arg_maxiops=$9
		
	#DisplayOutput ">>>> fio parameters: --name=$targetbenchpath/warmup_${arg_iotype%%/}.tst --iodepth=$arg_queuedepth --rw=$arg_iotype --bs=$arg_blocksize --direct=$arg_cachemode --size=$arg_testfilesize --numjobs=$arg_threads --runtime=$arg_timetorun" 1 0 $global_outputpath/perfinsights.log
	
	local targetbenchpath=""
	if [[ "$arg_volume" = "/" ]];then
		mkdir /mstest > /dev/null 2>&1
		targetbenchpath="/mstest"
		volumedisplayname="system"
	else
		targetbenchpath=$arg_volume
		volumedisplayname=${targetbenchpath/#"/"/"-"}
	fi

	if [ $arg_currentcount -gt 0 ]; then
		DisplayOutput ">>>> Run pass $arg_currentcount/$global_currentcount ($arg_timetorun s) on volume $arg_volume" 1 0 $global_outputpath/perfinsights.log 1
		#echo ">>> Output log: $global_outputpath/fio_${arg_queuedepth%%/}_${arg_blocksize%%/}_${arg_cachemode%%/}_${arg_testfilesize%%/}_${arg_timetorun%%/}_${arg_iotype%%/}-Run_${arg_currentcount%%/}.log"
		if [[ "$global_arg_debug" == "n" ]]; then
			if [ $global_distro = redhat ]; then
				cd $global_fiopath > /dev/null 2>&1
				./fio --name="$targetbenchpath/test_${arg_iotype%%/}.tst" --ioengine=libaio --iodepth=$arg_queuedepth --rw=$arg_iotype --bs=$arg_blocksize --direct=$arg_cachemode --size=$arg_testfilesize --numjobs=$arg_threads --runtime=$arg_timetorun --output="$global_outputpath/fio_${volumedisplayname%%/}_${arg_queuedepth%%/}_${arg_blocksize%%/}_${arg_cachemode%%/}_${arg_testfilesize%%/}_${arg_timetorun%%/}_${arg_iotype%%/}-Run_${arg_currentcount%%/}.log" --minimal --append-terse --output-format=text #> /dev/null 2>&1
			else
				#echo -n
				fio --name="$targetbenchpath/test_${arg_iotype%%/}.tst" --ioengine=libaio --iodepth=$arg_queuedepth --rw=$arg_iotype --bs=$arg_blocksize --direct=$arg_cachemode --size=$arg_testfilesize --numjobs=$arg_threads --runtime=$arg_timetorun --output="$global_outputpath/fio_${volumedisplayname%%/}_${arg_queuedepth%%/}_${arg_blocksize%%/}_${arg_cachemode%%/}_${arg_testfilesize%%/}_${arg_timetorun%%/}_${arg_iotype%%/}-Run_${arg_currentcount%%/}.log" --minimal --append-terse --output-format=text #--output-format=text #> /dev/null 2>&1
			fi
		fi
	else
		DisplayOutput ">>>> Warm-up phase ($arg_timetorun s) on volume $arg_volume" 1 0 $global_outputpath/perfinsights.log
		if [[ "$global_arg_debug" == "n" ]]; then
			if [ $global_distro = redhat ]; then
				cd $global_fiopath > /dev/null 2>&1
				./fio --name="$targetbenchpath/warmup_${arg_iotype%%/}.tst" --ioengine=libaio --iodepth=$arg_queuedepth --rw=$arg_iotype --bs=$arg_blocksize --direct=$arg_cachemode --size=$arg_testfilesize --numjobs=$arg_threads --runtime=$arg_timetorun --minimal > /dev/null 2>&1
			else
				echo -n
				fio --name="$targetbenchpath/warmup_${arg_iotype%%/}.tst" --ioengine=libaio --iodepth=$arg_queuedepth --rw=$arg_iotype --bs=$arg_blocksize --direct=$arg_cachemode --size=$arg_testfilesize --numjobs=$arg_threads --runtime=$arg_timetorun --minimal > /dev/null 2>&1
			fi
		fi
	fi
	
	if [[ "$arg_volume" = "/" ]];then
		rm -I -r --force /mstest > /dev/null 2>&1
	fi
	rm -f $targetbenchpath/warmup_*.tst*
	rm -f $targetbenchpath/test_*.tst*
	
}

RunScenarioDiskBenchmark(){
	
	local luserinput=n
	
	if [[ "$global_arg_forceprompts" == "y" ]]; then
		DisplayOutput "> Tools prompt skipped" 1 0 $global_outputpath/perfinsights.log
		luserinput=y
	else
		#luserinput=`VerifyUserInput "Do you allow this script to install additional tools (epel, libaio, fio depending on the Linux distribution) on this system ? (y/n)"`
		VerifyUserInput "Do you allow this script to install additional disk tools (epel, libaio, fio depending on the Linux distribution) on this system ? (y/n)" luserinput
	fi
	
	if [[ "$luserinput" == "y" ]];then
		CheckDiskToolsStatus
	else
		echo ""
		DisplayOutput " ~ You chose to not allow disk tools installation. This script may fail if required tools are not already present on this system." 1 0 $global_outputpath/perfinsights.log
		echo ""
	fi

	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Run benchmark on storage" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log

	for volume in "${global_volumelist[@]}"
	do
		lbenchcurrentdisk=y
		#currentdevice=`df | grep -w $volume | awk '{print $1}'`
		if [[ "$volume" = "/" ]]; then
			lcurrentdevice=`df -h | grep -w "/" | head -n 1 | awk '{print $1}'`
		else
			lcurrentdevice=`df -h | grep "$volume" | awk '{print $1}'`
		fi

		if [[ "$global_bypasssystemdisk" == "y" ]];then
			if [[ "$volume" == "/" ]]; then
				DisplayOutput ">> Bypass benchmark on $volume (device: $lcurrentdevice)" 1 $global_outputpath/perfinsights.log
				lbenchcurrentdisk=n
			fi
		fi
		
		if [[ "$global_bypasstempdisk" == "y" ]];then
			if [[ "$volume" == "/mnt" ]]; then
				DisplayOutput ">> Bypass benchmark on $volume (device: $lcurrentdevice)" 1 $global_outputpath/perfinsights.log
				lbenchcurrentdisk=n
			fi
		fi
		
		if [[ "$lbenchcurrentdisk" == "y" ]]; then
		
			
			DisplayOutput ">> Run benchmark on $volume (device: $lcurrentdevice)" 1 0 $global_outputpath/perfinsights.log

			lthreads=1
			lqueuedepth=64
			ltestfilesize=`GetTestfileSize $volume`
			lmaxiops=300
			
			lvoldevice=`df -h | grep -w $volume | awk '{print $1}'` > /dev/null 2>&1
			mdadm --detail $lvoldevice > /dev/null 2>&1
			lresult=`echo $?`
			if [[ $lresult -eq 0 ]];then
				lthreads=`GetDiskSpindles $volume`
				DisplayOutput "--> This is a mdadm volume with $lthreads spindle(s)" 1 3 $global_outputpath/perfinsights.log
			fi
			
			FindLVMVolGroupFromMountPoint $volume lvmvolgroupname
			if [[ ! -z $lvmvolgroupname ]];then
				lthreads=`GetDiskSpindles $lvmvolgroupname`
				DisplayOutput "--> This is a LVM volume with $lthreads spindle(s)" 1 3 $global_outputpath/perfinsights.log
				lmaxiops=`GetDiskMaxIOPS $lvmvolgroupname $lthreads`
			else
				lthreads=`GetDiskSpindles $volume`
				lmaxiops=`GetDiskMaxIOPS $volume $lthreads`
			fi
			lqueuedepth=`GetQueueDepth $lthreads`
			
			# queue depth =
			# Scenario IOPS: $lmaxiops * $expectedlat * $DriveToTest.NumofDisks
			# Scenario throughput: maxmbps_iops = 1kb * $maxthroughput / ($session.block_size.Split("k")[0])
			
			liotype="randwrite"
			ltimetorun=10
			lblocksize=8k
			lcachemode=1
			DisplayOutput ">>>  Test 1/6 - I/O type: $liotype / Queue depth: $lqueuedepth / Bloc size: $lblocksize / Cache mode: $lcachemode / Threads: $lthreads / Test file size: $ltestfilesize / Runtime: $ltimetorun / Expected IOPS: $lmaxiops" 1 0 $global_outputpath/perfinsights.log
			RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads 0
			for (( lcount=1; lcount<=$global_currentcount; lcount++ ))
			do
				RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads $lcount
				echo "" > /dev/stderr
			done

			liotype="randwrite"
			lblocksize=512k
			lcachemode=1
			DisplayOutput ">>> Test 2/6 - I/O type: $liotype / Queue depth: $lqueuedepth / Bloc size: $lblocksize / Cache mode: $lcachemode / Threads: $lthreads / Test file size: $ltestfilesize / Runtime: $ltimetorun / Expected IOPS: $lmaxiops" 1 0 $global_outputpath/perfinsights.log
			RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads 0
			for (( lcount=1; lcount<=$global_currentcount; lcount++ ))
			do
				RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads $lcount
				echo "" > /dev/stderr
			done

			liotype="randread"
			lblocksize=8k
			lcachemode=1
			DisplayOutput ">>>  Test 3/6 - I/O type: $liotype / Queue depth: $lqueuedepth / Bloc size: $lblocksize / Cache mode: $lcachemode / Threads: $lthreads / Test file size: $ltestfilesize / Runtime: $ltimetorun / Expected IOPS: $lmaxiops" 1 0 $global_outputpath/perfinsights.log
			RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads 0
			for (( lcount=1; lcount<=$global_currentcount; lcount++ ))
			do
				RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads $lcount
				echo "" > /dev/stderr
			done

			liotype="randread"
			lblocksize=512k
			lcachemode=1
			DisplayOutput ">>>  Test 4/6 - I/O type: $liotype / Queue depth: $lqueuedepth / Bloc size: $lblocksize / Cache mode: $lcachemode / Threads: $lthreads / Test file size: $ltestfilesize / Runtime: $ltimetorun / Expected IOPS: $lmaxiops" 1 0 $global_outputpath/perfinsights.log
			RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads 0
			for (( lcount=1; lcount<=$global_currentcount; lcount++ ))
			do
				RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads $lcount
				echo "" > /dev/stderr
			done

			liotype="read"
			lblocksize=8k
			lcachemode=1
			DisplayOutput ">>>  Test 5/6 - I/O type: $liotype / Queue depth: $lqueuedepth / Bloc size: $lblocksize / Cache mode: $lcachemode / Threads: $lthreads / Test file size: $ltestfilesize / Runtime: $ltimetorun / Expected IOPS: $lmaxiops" 1 0 $global_outputpath/perfinsights.log
			RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads 0
			for (( lcount=1; lcount<=$global_currentcount; lcount++ ))
			do
				RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads $lcount
				echo "" > /dev/stderr
			done

			liotype="read"
			lblocksize=512k
			lcachemode=1
			DisplayOutput ">>>  Test 6/6 - I/O type: $liotype / Queue depth: $lqueuedepth / Bloc size: $lblocksize / Cache mode: $lcachemode / Threads: $lthreads / Test file size: $ltestfilesize / Runtime: $ltimetorun / Expected IOPS: $lmaxiops" 1 0 $global_outputpath/perfinsights.log
			RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads 0
			for (( lcount=1; lcount<=$global_currentcount; lcount++ ))
			do
				RunFIO $volume $lqueuedepth $lblocksize $lcachemode $ltimetorun $liotype $ltestfilesize $lthreads $lcount
				echo "" > /dev/stderr
			done
		fi
	done
}

RunScenarioSlowAnalysis(){
	local lnumberofsamples=$1
	local lsampleinterval=$2
	local luserinput=n
	
	if [[ "$global_arg_forceprompts" == "y" ]]; then
		DisplayOutput "> Tools prompt skipped" 1 0 $global_outputpath/perfinsights.log
		luserinput=y
	else
		#luserinput=`VerifyUserInput "Do you allow this script to install additional tools (epel, libaio, fio depending on the Linux distribution) on this system ? (y/n)"`
		VerifyUserInput "Do you allow this script to install additional system tools (systat) on this system ? (y/n)" luserinput
	fi
		
	if [[ "$luserinput" == "y" ]];then
		CheckSysToolsStatus
		echo -n
	else
		echo ""
		DisplayOutput " ~ You chose to not allow system tools installation. This script may fail if required tools are not already present on this system." 1 0 $global_outputpath/perfinsights.log
		echo ""
	fi
	
	DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "> Collect slow analysis counters" 1 0 $global_outputpath/perfinsights.log
	DisplayOutput "-----------------------------------------" 0 0 $global_outputpath/perfinsights.log
	DisplayOutput "" 0 0 $global_outputpath/perfinsights.log
	
	local lsamples=0
	if [ $lnumberofsamples -eq 0 ];then
		DisplayOutput ">> Reproduce the issue and press 's' to stop the capture" 1 0 $global_outputpath/perfinsights.log
		capture=1
		while [[ $capture -eq 1 ]]
		do
			sh ./$global_sysstatversion/sa1 #debian-sa1
			sleep $lsampleinterval
			echo -n "." > /dev/stderr
			((lsamples++))
			read -t 1 -n 1 keypress
			if [[ "$keypress" == "s" ]];then
				break
			fi
		done
	else
		DisplayOutput ">> Capture metrics (samples: $lnumberofsamples / Interval: $lsampleinterval)..." 1 0 $global_outputpath/perfinsights.log
		while [[ $lsamples -le $lnumberofsamples ]]
		do
			sh ./$global_sysstatversion/sa1 #debian-sa1
			sleep $lsampleinterval
			echo -n "." > /dev/stderr
			((lsamples++))
		done
	fi
	
	echo "" > /dev/stderr
	DisplayOutput ">> Gathering information..." 1 0 $global_outputpath/perfinsights.log
	DisplayOutput ">>> Gathering paging information..." 1 0 $global_outputpath/perfinsights.log
	sar -B -o $global_outputpath/perfinsights_paging.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd1=$!
	DisplayOutput ">>> Gathering huge paging information..." 1 0 $global_outputpath/perfinsights.log
	sar -H -o $global_outputpath/perfinsights_hugepaging.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd2=$!
	DisplayOutput ">>> Gathering networking information..." 1 0 $global_outputpath/perfinsights.log
	sar -n ALL -o $global_outputpath/perfinsights_networking.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd3=$!
	DisplayOutput ">>> Gathering memory information..." 1 0 $global_outputpath/perfinsights.log
	sar -r ALL -o $global_outputpath/perfinsights_memory.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd4=$!
	DisplayOutput ">>> Gathering swap usage information..." 1 0 $global_outputpath/perfinsights.log
	sar -S -o $global_outputpath/perfinsights_swapusage.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd5=$!
	DisplayOutput ">>> Gathering swapping information..." 1 0 $global_outputpath/perfinsights.log
	sar -W -o $global_outputpath/perfinsights_swapping.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd6=$!
	DisplayOutput ">>> Gathering CPU information..." 1 0 $global_outputpath/perfinsights.log
	sar -u ALL -o $global_outputpath/perfinsights_cpu.bin $lsampleinterval $lsamples > /dev/null 2>&1 #&
	sarCmd7=$!
	
	DisplayOutput ">> Preparing output..." 1 0 $global_outputpath/perfinsights.log
	#wait $sarCmd1
	DisplayOutput ">>> Prepare graph for paging information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_paging.bin -- -B > $global_outputpath/perfinsights_paging.svg
	#wait $sarCmd2
	DisplayOutput ">>> Prepare graph for huge paging information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_hugepaging.bin -- -H > $global_outputpath/perfinsights_hugepaging.svg
	#wait $sarCmd3
	DisplayOutput ">>> Prepare graph for networking information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_networking.bin -- -n ALL > $global_outputpath/perfinsights_networking.svg
	#wait $sarCmd4
	DisplayOutput ">>> Prepare graph for memory information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_memory.bin -- -r ALL > $global_outputpath/perfinsights_memory.svg
	#wait $sarCmd5
	DisplayOutput ">>> Prepare graph for swap usage information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_swapusage.bin -- -S > $global_outputpath/perfinsights_swapusage.svg
	#wait $sarCmd6
	DisplayOutput ">>> Prepare graph for swapping information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_swapping.bin -- -W > $global_outputpath/perfinsights_swapping.svg
	#wait $sarCmd7
	DisplayOutput ">>> Prepare graph for CPU information..." 1 0 $global_outputpath/perfinsights.log
	sadf -g $global_outputpath/perfinsights_cpu.bin -- -u ALL > $global_outputpath/perfinsights_cpu.svg
}

### MAIN

clear
#echo "the value of $# is " $#


if [ $# -gt 1 ];then
	echo ""
	while [[ $# -gt 0 ]]
	do
		key="$1"
		case $key in
			-s|--scenario)
				global_arg_scenario="$2"
				shift 2
				case $global_arg_scenario in
					pointintime)
						echo -n
						;;
					diskbenchmark)
						echo -n
						;;
					diskinfo)
						echo -n
						;;
					slowanalysis)
						echo -n
						;;
					benchandanalysis)
						echo -n
						;;
					?)
						DisplayUsage
						;;
					*)
						DisplayUsage
						;;
				esac
				
				;; 
			-k|--skip)
				global_arg_skipdisks="$2"
				shift 2
				case "$global_arg_skipdisks" in
					system)
						global_bypasssystemdisk=y
						;;
					temp)
						global_bypasstempdisk=y
						;;
					all)
						global_bypasssystemdisk=y
						global_bypasstempdisk=y
						;;
					?)
						DisplayUsage
						;;
					*)
						DisplayUsage
						;;
				esac
				;;
			-d|--debug)
				global_arg_debug=y
				shift
				;;
			-f|--skip)
				global_arg_forceprompts=y
				shift
				;;
			-r|--repro)
				global_arg_repro=y
				shift
				;;
			-a|--samples)
				global_arg_samples=$2
				shift 2
				;;
			-i|--interval)
				global_arg_interval=$2
				shift 2
				;;
			-h)
				shift
				DisplayUsage
				;;
			-*)
				shift
				DisplayUsage
				;;
			?)
				shift
				DisplayUsage
				;;
			*)
				shift
				DisplayUsage
				;;
		esac
	done
	echo ""
else
	DisplayUsage
fi
if [[ $global_arg_debug == "y" ]];then
	rm -I -r -f log_perfinsight_*
fi

mkdir $global_outputpath > /dev/null 2>&1

DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
DisplayOutput "############################" 1 0 $global_outputpath/perfinsights.log
DisplayOutput "# PerfInsight for Linux $SCRIPTVERSION #" 1 0 $global_outputpath/perfinsights.log
DisplayOutput "############################" 1 0 $global_outputpath/perfinsights.log
DisplayOutput "" 1 0 $global_outputpath/perfinsights.log

DisplayOutput ">> Scenario: $global_arg_scenario" 1 0 $global_outputpath/perfinsights.log
DisplayOutput ">> Skip: $global_arg_skipdisks" 1 0 $global_outputpath/perfinsights.log
DisplayOutput ">> Debug: enabled" 1 0 $global_outputpath/perfinsights.log

IsOSSupported

case "$global_arg_scenario" in
	pointintime)
	/var/tmp/linux-reports.sh
	#	RunBasicCollect
		;;
	diskinfo)
		RunBasicCollect
		;;
	slowanalysis)
		if [[ "$global_arg_repro" == "y" ]];then
			echo -n
		else
			if [ $global_arg_interval -lt 1 ];then
				DisplayUsage
			fi
			if [ $global_arg_samples -eq 0 ];then
				DisplayUsage
			fi
		fi
		RunBasicCollect
		RunScenarioSlowAnalysis $global_arg_samples $global_arg_interval
		;;
	diskbenchmark)
		RunBasicCollect
		RunScenarioDiskBenchmark
		;;
	?)
		DisplayUsage
		;;
	*)
		DisplayUsage
		;;
esac

DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
DisplayOutput "#########################" 1 2 $global_outputpath/perfinsights.log
DisplayOutput "# PerfInsight completed #" 1 2 $global_outputpath/perfinsights.log
DisplayOutput "#########################" 1 2 $global_outputpath/perfinsights.log

tar -czvf $global_outputpath.tar $global_outputpath > /dev/null 2>&1

DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
DisplayOutput " Gather $global_outputpath.tar and send it to the Microsoft support engineer" 1 0 $global_outputpath/perfinsights.log
DisplayOutput "" 1 0 $global_outputpath/perfinsights.log
