#!/usr/bin/env bash

#Copyright Ben Kazemi 2016

printf "Welcome, this script will get you up and running with my Stereo Listener.\nBy the end you will have a script that you can call by typing './listen'."

#Checking if updated distro
printf "\nMake sure to update your distro.\nIf you need to update now then go ahead, but the script will reboot requiring you to call this script again.\n\n"
read -p "Update now? (y/n)" -n 1 -r
echo    
if [[ $REPLY =~ ^[Yy]$ ]];
then
    printf "Please wait.\n\n" 
	sudo apt-get update -y | sudo apt-get upgrade -y && printf "Rebooting now, call me when I'm back.\n\n" && sudo reboot && exit 0 
fi

printf "\nDistro should be up-to-date."

mkdir -p ~/stereoListener
rm -rf ~/stereoListener/del
mkdir -p ~/stereoListener/del
mkdir -p ~/stereoListener/src
mkdir -p ~/stereoListener/backup
mkdir -p ~/stereoListener/bin

#enabling i2s in the device tree
printf "\n\nEnabling I2S in the device tree."
printf "\nBacking up /boot/config.txt\n"
sudo cp /boot/config.txt ~/stereoListener/backup/config.txt
sudo cp /boot/config.txt /boot/config.bak
CONFIG_I2S=$(grep -q 'i2s' /boot/config.txt)
if [[ "$CONFIG_I2S" == *"#"* ]]
then
	grep -vq 'i2s' /boot/config.txt > ~/stereoListener/config.txt
	echo "dtparam=i2s=on" >> ~/stereoListener/config.txt
	sudo rm -f /boot/config.txt
	sudo cp -f ~/stereoListener/config.txt /boot/config.txt
	printf "I2S enabled."	
else 
	printf "I2S Already enabled."	
fi

#Invoking i2s and DMA peripherals at boot 
printf "\n\nSetup to invoke I2S and DMA modules at boot.\n"	
declare -a MODULE_ARRAY=("snd_soc_bcm2708" "snd_soc_bcm2708_i2s" "bcm2708_dmaengine")
sudo cp -f /etc/modules /etc/modules.bak
sudo cp -f /etc/modules ~/stereoListener/backup/modules
for i in "${MODULE_ARRAY[@]}" # delete what's there 
do
	grep -Fv "$i" ~/stereoListener/backup/modules > ~/stereoListener/del/modules.tmp
done
for i in {0..2} # add desired 
do
	echo "${MODULE_ARRAY[i]}" >> ~/stereoListener/del/modules.tmp
done
awk '!a[$0]++' ~/stereoListener/del/modules.tmp > ~/stereoListener/del/modules.tmp2 # delete duplicates 
sudo cp -f ~/stereoListener/del/modules.tmp2 /etc/modules
printf "\nAdded modules."

#Download kernel source
printf "\n\nWe'll download the RPi kernel source now, this may take a while.\n"
cd ~
sudo apt-get install bc -y
echo
sudo apt-get install libncurses5-dev -y
printf "\nCleaning up existing builds."
# rm -rf rpi-source linux linux-* linux linux-*.*
git clone http://github.com/notro/rpi-source
cd rpi-source
python rpi-source

#make sound driver 
printf "\n\nBuilding Sound Driver.\n"
cd ~/stereoListener/
mkdir -p del/snd_driver
cp -f src/asoc_simple_card.c del/snd_driver/asoc_simple_card.c 
cd del/snd_driver
cat > Makefile <<EOL
obj-m := asoc_simple_card.o
KDIR := /lib/modules/\$(shell uname -r)/build
PWD := \$(shell pwd)
default:
EOL
echo -e "\t\$(MAKE) -C \$(KDIR) SUBDIRS=\$(PWD) modules" >> Makefile
make 
printf "\nLoading Sound Driver.\n"
cd ~/stereoListener/
mv del/snd_driver/asoc_simple_card.ko bin/asoc_simple_card.ko
cd bin/
#Variables check if module loaded or not
unset MODULE
unset MODEXIST
MODULE="asoc_simple_card"
MODEXIST=/sbin/lsmod | grep "$MODULE"
if [ -z "$MODEXIST" ]; then
	sudo insmod asoc_simple_card.ko
	/sbin/modprobe "$MODULE" >/dev/null 2>&1
fi

#make loader
printf "\n\nBuilding the Sound Card Loader.\n"
cd ~/stereoListener/
mkdir -p del/loader
cp -f src/loaderPiSlave.c del/loader/loaderPiSlave.c
cd del/loader
cat > Makefile <<EOL
obj-m := loaderPiSlave.o
KDIR := /lib/modules/\$(shell uname -r)/build
PWD := \$(shell pwd)
default:
EOL
echo -e "\t\$(MAKE) -C \$(KDIR) SUBDIRS=\$(PWD) modules" >> Makefile
make 
printf "\nLoading Kernel Driver.\n\n"
cd ~/stereoListener/
mv del/loader/loaderPiSlave.ko bin/loaderPiSlave.ko
cd bin/
#Variables check if module loaded or not
unset MODULE
unset MODEXIST
MODULE="loaderPiSlave"
MODEXIST=/sbin/lsmod | grep "$MODULE"
if [ -z "$MODEXIST" ]; then
	sudo insmod loaderPiSlave.ko
	/sbin/modprobe "$MODULE" >/dev/null 2>&1
fi

#finished loading drivers, show available soundcards
printf "\nAll kernel drivers have been built and loaded, here's your soundcard:\nzn"
sleep 1
arecord -l
printf "\nBuilding script to load at boot so the driver is loaded between power cycles.\n"
cd ~/stereoListener/bin
cat > load_i2s_driver.sh <<EOL
cd /home/pi/stereoListener/bin/
sudo insmod asoc_simple_card.ko
sudo insmod loaderPiSlave.ko
exit 0
EOL
sudo chmod +x load_i2s_driver.sh
printf "\nAppending script call.\n\n"

if ! grep -q 'load_i2s_driver.sh' /etc/rc.local ; then
	file="/etc/rc.local"
	sudo sed -i '$ibash /home/pi/stereoListener/bin/load_i2s_driver.sh' "$file"
fi

#creating listen script 
printf "\n\nCreating Listener Script."
cd ~
echo "arecord -D hw:1,0 -t wav -c 2 -r 48000 -f S16_LE | aplay -D hw:0,0 -t wav -c 2 -r 48000 -f S16_LE" > ~/listen.sh
sudo chmod +x listen.sh
printf "Pipe audio in to HDMI and the 3.5mm jack (noisy) by calling ./listen.sh\n\n"


#exiting 
printf "Deleting temporary files."
rm -rf ~/stereoListener/del
printf "\n\nExiting\nStereo Listener Script by Ben Kazemi 2016"
echo
exit 0
