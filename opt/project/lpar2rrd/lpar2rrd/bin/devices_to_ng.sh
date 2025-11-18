#!/bin/env sh
# use to export device list to NG

APPDIR=$(CDPATH= cd -- "$(dirname -- "$0")"/.. && pwd)
cd "$APPDIR/bin"

echo

WEBCFG="$APPDIR/etc/web_config"

if [ -f "$WEBCFG/hosts.json" ]; then
    APPNAME="LPAR2RRD"
    CFGFILE="hosts.json"
elif [ -f "$WEBCFG/devicecfg.json" ]; then
    APPNAME="STOR2RRD"
    CFGFILE="devicecfg.json"
  else
    echo "This script must be placed and run in LPAR2RRD/STOR2RRD bin/ directory. Exiting..."
    exit
fi

if command -v gpg > /dev/null; then
    ENCRYPTED=1
    FILENAME="$APPDIR/www/devex-$(od -An -N4 -tx /dev/urandom | tr -d '\t ').gpg"
    echo "Creating password protected $APPNAME device list for Xormon NG..."
    echo "Next you will choose some password, press [Enter] to continue:"
    read
    GPGRES=$(gpg -c -o $FILENAME $WEBCFG/$CFGFILE)
    if [ ! $? -eq 0 ]; then
      echo "GPG encryption failed, exiting... : $?"
      exit  1
    fi
else
    echo "Creating $APPNAME device list for Xormon NG, press [Enter] to continue..."
    FILENAME="$APPDIR/www/devex-$(od -An -N4 -tx /dev/urandom | tr -d '\t ').json"
    read
    cp $WEBCFG/$CFGFILE $FILENAME
fi

BASENAME=$(basename $FILENAME)

echo "In Xormon NG, use this filename to import $APPNAME devices:"
echo ""
echo "$BASENAME"
echo ""
if [ $ENCRYPTED ]; then
  echo "You'll be asked for the password used in this export tool."
fi
echo "Don't forget to remove $FILENAME when done!"
