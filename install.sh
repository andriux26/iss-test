#!/bin/bash
set -e

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
BOLD=$(tput bold)
RESET=$(tput sgr0)

die() {
    >&2 echo "${RED}error: $1${RESET}" && exit 1
}

log() {
    echo "$*"
}

log_done() {
    echo " ${GREEN}✓${RESET} $1"
}

log_running() {
    echo " ${YELLOW}*${RESET} $1"
}

log_error() {
    echo " ${RED}error: $1${RESET}"
}

success() {
    echo "${GREEN}$1${RESET}"
}

### Run as a normal user
if [ $EUID -eq 0 ]; then
    die "This script shouldn't be run as root."
fi

### Verify cloned repo
if [ ! -e "$HOME/ISS" ]; then
    die "Is https://github.com/andriux26/ISS.git atsiunciama ?"
fi

### Install required packages
log_running "Instaliuojami paketai..."

raspbian_version="$(lsb_release -c --short)"

if [ "$raspbian_version" == "stretch" ]; then
    wget -q https://packages.sury.org/php/apt.gpg -O- | sudo apt-key add -
    echo "deb https://packages.sury.org/php/ stretch main" | sudo tee /etc/apt/sources.list.d/php7.list
fi

sudo apt update -yq
sudo apt install -yq predict \
                     python-setuptools \
                     ntp \
                     cmake \
                     libusb-1.0-0-dev \
                     sox \
                     at \
                     bc \
                     nginx \
                     libncurses5-dev \
                     libncursesw5-dev \
                     libatlas-base-dev \
                     python3-pip \
                     imagemagick \
                     libxft-dev \
                     libxft2 \
                     libjpeg9 \
                     libjpeg9-dev \
                     socat \
                     php7.2-fpm \
                     php7.2-sqlite3 \
                     sqlite3

if [ "$raspbian_version" == "stretch" ]; then
    sudo apt install -yq libgfortran-5-dev
else
    sudo apt install -yq libgfortran5
fi

sudo python3 -m pip install numpy ephem  Pillow
log_done "Packages installed"

### Create the database schema
if [ -e "$HOME/ISS/panel.db" ]; then
    log_done "Database already created"
else
    sqlite3 "panel.db" < "templates/webpanel_schema.sql"
    log_done "Database schema created"
fi

### Blacklist DVB modules
if [ -e /etc/modprobe.d/rtlsdr.conf ]; then
    log_done "DVB modules were already blacklisted"
else
    sudo cp templates/modprobe.d/rtlsdr.conf /etc/modprobe.d/rtlsdr.conf
    log_done "DVB modules are blacklisted now"
fi

### Install RTL-SDR
if [ -e /usr/local/bin/rtl_fm ]; then
    log_done "rtl-sdr was already installed"
else
    log_running "Installing rtl-sdr from osmocom..."
    (
        cd /tmp/
        git clone https://github.com/osmocom/rtl-sdr.git
        cd rtl-sdr/
        mkdir build
        cd build
        cmake ../ -DINSTALL_UDEV_RULES=ON -DDETACH_KERNEL_DRIVER=ON
        make
        sudo make install
        sudo ldconfig
        cd /tmp/
        sudo cp ./rtl-sdr/rtl-sdr.rules /etc/udev/rules.d/
    )
    log_done "rtl-sdr install done"
fi


### Install default config file
if [ -e "$HOME/.noaa.conf" ]; then
    log_done "$HOME/.noaa.conf already exists"
else
    cp "templates/noaa.conf" "$HOME/.noaa.conf"
    log_done "$HOME/.noaa.conf installed"
fi

if [ -d "$HOME/.predict" ] && [ -e "$HOME/.predict/predict.qth" ]; then
    log_done "$HOME/.predict/predict.qth already exists"
else
    mkdir "$HOME/.predict"
    cp "templates/predict.qth" "$HOME/.predict/predict.qth"
    log_done "$HOME/.predict/predict.qth installed"
fi














### Cron the scheduler
set +e
crontab -l | grep -q "raspberry-noaa"
if [ $? -eq 0 ]; then
    log_done "Crontab for schedule.sh already exists"
else
    cat <(crontab -l) <(echo "1 0 * * * /home/pi/raspberry-noaa/schedule.sh") | crontab -
    log_done "Crontab installed"
fi
set -e

### Setup Nginx
log_running "Setting up Nginx..."
sudo cp templates/nginx.cfg /etc/nginx/sites-enabled/default
(
    sudo mkdir -p /var/www/wx/images
    sudo chown -R pi:pi /var/www/wx
    sudo usermod -a -G www-data pi
    sudo chmod 775 /var/www/wx
)
sudo systemctl restart nginx
sudo cp -rp templates/webpanel/* /var/www/wx/

log_done "Nginx configured"

### Setup ramFS
SYSTEM_MEMORY=$(free -m | awk '/^Mem:/{print $2}')
if [ "$SYSTEM_MEMORY" -lt 2000 ]; then
	sed -i -e "s/1000M/200M/g" templates/fstab
fi
set +e
cat /etc/fstab | grep -q "ramfs"
if [ $? -eq 0 ]; then
    log_done "ramfs already setup"
else
    sudo mkdir -p /var/ramfs
    cat templates/fstab | sudo tee -a /etc/fstab > /dev/null
    log_done "Ramfs installed"
fi
sudo mount -a
sudo chmod 777 /var/ramfs
set -e



success "Install (almost) done!"

read -rp "Ijunkti stiptintuva bias-tee? (y/N)"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sed -i -e "s/enable_bias_tee/-T/g" "$HOME/.noaa.conf"
    log_done "Bias-tee is enabled!"
else
    sed -i -e "s/enable_bias_tee//g" "$HOME/.noaa.conf"
fi

echo "
    Next we'll configure your webpanel language
    and locale settings - you can update these in the
    future by modifying 'lang' in /var/www/wx/Config.php
    and 'date_default_timezone_set' in /var/www/wx/header.php
    "

# language configuration
langs=($(find templates/webpanel/language/ -type f -printf "%f\n" | cut -f 1 -d '.'))
while : ; do
    read -rp "Pasirink Kalba (${langs[*]}): "
    lang=$REPLY

    if [[ ! " ${langs[@]} " =~ " ${lang} " ]]; then
        log_error "choice $lang is not one of the available options (${langs[*]})"
    else
        break
    fi
done
sed -i -e "s/'lang' => '.*'$/'lang' => '${lang}'/" "/var/www/wx/Config.php"

echo "Laiko zonu pavizdziai https://www.php.net/manual/en/timezones.php "
read -rp "Ivesti -> Europe/Vilnius: "
    timezone=$REPLY
timezone=$(echo $timezone | sed 's/\//\\\//g')
sed -i -e "s/date_default_timezone_set('.*');/date_default_timezone_set('${timezone}');/" "/var/www/wx/header.php"

echo "
   Nustatymai
    "

read -rp "Platuma Panevezys (55.57): "
    lat=$REPLY

read -rp "Ilguma Panevezys (24.25): "
    lon=$REPLY

# note: this can probably be improved by calculating this
# automatically - good for a future iteration
read -rp "Laiko zonos ( Vasara 3 Ziema 2): "
    tzoffset=$REPLY

sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/${lon}/g" "$HOME/.noaa.conf"

sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/$(echo  "$lon * -1" | bc)/g" "$HOME/.predict/predict.qth"
sed -i -e "s/change_latitude/${lat}/g;s/change_longitude/${lon}/g;s/change_tz/$(echo  "$tzoffset * -1" | bc)/g" "sun.py"

success "Nustatymai baikti! Pasitikrinti $HOME/.noaa.conf settings"



set +e




echo "
    Atsiunciama Palidovu Laikai
"


./schedule.sh -t -x



echo "
    Sistema Perkraunama
"








sudo reboot
