#!/bin/bash

# Patikrinkime, ar skriptas paleistas su root teis�mis
if [ "$(id -u)" -ne 0 ]; then
    echo "Pra�ome paleisti �� skript� kaip root (naudojant sudo)."
    exit 1
fi

# Atnaujiname sistem� ir diegiame priklausomybes
echo "Atnaujiname sistem� ir diegiame reikalingus paketus..."
apt update && apt upgrade -y

# �diegiame Python ir reikiamas bibliotekas
echo "Diegiame Python ir pip..."
apt install -y python3 python3-pip

# Diegiame Python priklausomybes
echo "Diegiame Python bibliotekas..."
pip3 install --upgrade skyfield pytz

# Diegiame RTL-SDR ir sox
echo "Diegiame RTL-SDR ir sox..."
apt install -y rtl-sdr sox

# Diegiame QSSTV
echo "Diegiame QSSTV..."
apt install -y qsstv

# Diegiame screen (jei dar ne�diegta)
echo "Diegiame screen..."
apt install -y screen

# Sukuriame screen sesij�
SCRIPT_PATH="/home/pi/iss/iss.py"  # J�s� Python skripto kelias

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Skriptas nerastas: $SCRIPT_PATH"
    exit 1
fi

echo "Pridedame screen sesij� ir crontab �ra��..."
(crontab -l 2>/dev/null; echo "@reboot screen -dmS iss_tracking python3 $SCRIPT_PATH") | crontab -

# Sukuriame alias komand� "iss"
echo "Pridedame 'iss' komand�..."
echo "alias iss='screen -r iss_tracking'" >> ~/.bashrc
source ~/.bashrc

# U�baigta
echo "Diegimas baigtas! Programa bus paleista automati�kai po perkrovimo. Nor�dami per�i�r�ti veikian�i� sesij�, naudokite komand� 'iss'."
