#!/bin/bash

# Patikrinkime, ar skriptas paleistas su root teisëmis
if [ "$(id -u)" -ne 0 ]; then
    echo "Praðome paleisti ðá skriptà kaip root (naudojant sudo)."
    exit 1
fi

# Atnaujiname sistemà ir diegiame priklausomybes
echo "Atnaujiname sistemà ir diegiame reikalingus paketus..."
apt update && apt upgrade -y

# Ádiegiame Python ir reikiamas bibliotekas
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

# Diegiame screen (jei dar neádiegta)
echo "Diegiame screen..."
apt install -y screen

# Sukuriame screen sesijà
SCRIPT_PATH="/home/pi/iss/iss.py"  # Jûsø Python skripto kelias

if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Skriptas nerastas: $SCRIPT_PATH"
    exit 1
fi

echo "Pridedame screen sesijà ir crontab áraðà..."
(crontab -l 2>/dev/null; echo "@reboot screen -dmS iss_tracking python3 $SCRIPT_PATH") | crontab -

# Sukuriame alias komandà "iss"
echo "Pridedame 'iss' komandà..."
echo "alias iss='screen -r iss_tracking'" >> ~/.bashrc
source ~/.bashrc

# Uþbaigta
echo "Diegimas baigtas! Programa bus paleista automatiðkai po perkrovimo. Norëdami perþiûrëti veikianèià sesijà, naudokite komandà 'iss'."
