#!/bin/bash

# vars
SLEEP_TIME=2

# wait for initialization
sleep $SLEEP_TIME

# line
echo '******************************************************************************'
echo '* Starting Reactive Drop server                                              *'
echo '******************************************************************************'

# check for last minute game updates
steam-run-script install.server

# get the ip address
#ip=$(wget -q -O- "https://api.ipify.org/")

# bind to the internal container id
ip=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | cut -d ' ' -f 2 | head -n 1)

# gui/console
export DISPLAY=:0
export WINEARCH="win32"
export WINEDEBUG="-all"
export WINEDLLOVERRIDES="mscoree=d;mshtml=d"
#export WINEDEBUG="+synchronous,+loaddll,+seh,+msgbox,+fixme"

function write_server_config()
{
    file=$1

    # load the server.cfg file
    echo "exec server.cfg" > $file

    # look for other settings for this server
    for vars in $(set | grep "^rd\_server\_${nr}\_"); do
        var=$(echo "${vars}" | cut -d '_' -f 4- | cut -d '=' -f 1)
        value=$(echo "${vars}" | cut -d '=' -f 2- | sed "s/\\\\'/\#/g" | sed "s/'//g" | sed "s/#/'/g")

        # write the var the the server config file
        echo "${var} ${value}" >> $file
    done
}

function write_sourcemod_admins_simple()
{
    file="reactivedrop/addons/sourcemod/configs/admins_simple.ini"

    if [[ "$sourcemod_admin_steamid" != "" ]]; then
        echo "\"$sourcemod_admin_steamid\" \"z\"" > $file
        echo "" > $file
    fi

}

function write_sourcemod_sourcebans_config()
{
    file="reactivedrop/addons/sourcemod/configs/databases.cfg"

    if [[ "${sourcebans_host}" != "" ]]; then
        sed -i'' "s/#sourcebans_host#/${sourcebans_host}/g" $file
        sed -i'' "s/#sourcebans_port#/${sourcebans_port}/g" $file
        sed -i'' "s/#sourcebans_user#/${sourcebans_user}/g" $file
        sed -i'' "s/#sourcebans_password#/${sourcebans_password}/g" $file
        sed -i'' "s/#sourcebans_database#/${sourcebans_database}/g" $file
    fi
}

function write_sourcebans_serverid()
{
    base=$1
    nr=$2

    id=$(set | grep "rd_sourcebans_${nr}_id")
    if [[ "$id" != "" ]]; then
        sed -i'' "s/\-1/${nr}/g" $base/configs/sourcebans/sourcebans.cfg
    fi
}

function write_sourcemod_whitelist_config()
{
    base=$1
    nr=$2

    group=$(set | grep "rd_whitelist_${nr}_group")
    if [[ "$group" != "" ]]; then
        echo "Whitelist configuration found, enabling whitelist"

        # write config
        echo "${group}" | cut -d '=' -f 2 > $base/configs/whitelist/whitelist.txt

        # enable plugin
        ln -sf ../plugins-available/serverwhitelistadvanced.smx $base/plugins/serverwhitelistadvanced.smx
    fi
}

function install_steam_client()
{
    if [[ ! -f ~/prefix32/drive_c/Program\ Files/Steam/uninstall.exe ]]; then
      # install steam client, it will dispatch itself into the background after update
      winetricks --unattended win7
      winetricks --unattended steam
      run_steam_client
    else
      # just start it in the background
      run_steam_client &
    fi
}

function run_steam_client()
{
  wine ~/prefix32/drive_c/Program\ Files/Steam/Steam.exe
}

# run a persistent wine server during initialization
/usr/bin/wineserver -k -p 60

# set ifs
IFS=$'\n'

# get defined servers
servers=$(set | grep "^rd\_server\_[0-9]\{1,\}\_port=[0-9]\{4,5\}$")

# switch to reactive drop folder
cd /root/reactivedrop || exit 1

# patch content servers
#patch_content_servers
install_steam_client

# remove some leftovers if present
find ./reactivedrop -name '*.campaignsave' -or -name '*.log' -delete

# loop
while [[ true ]]; do

    # iterate
    for server in $servers; do

        # get server number
        nr=$(echo "${server}" | cut -d '_' -f 3)
        port=$(echo "${server}" | cut -d '=' -f 2-)

        # check if the server is running already
        running=$(pgrep -f "${port}")

        if [[ "$running" = "" ]]; then

            # write a configuration file for this server
            config="server_${nr}.cfg"
            console="console_${nr}.log"
            file="reactivedrop/cfg/${config}"

            # write some configs
            write_server_config "${file}"
            write_sourcemod_admins_simple
            write_sourcemod_sourcebans_config

            # create a copy of the sourcemod folder
            smbase="addons/sourcemod_${nr}"
            cp -a reactivedrop/addons/sourcemod reactivedrop/$smbase

            # sourcebans
            write_sourcebans_serverid "reactivedrop/${smbase}" $nr
            write_sourcemod_whitelist_config "reactivedrop/${smbase}" $nr

            # check if the env does exist
            echo "======================"
            echo "| Starting server #${nr} |"
            echo "======================"

            # startup parameters of config, smbase, lobby, ip must be in exactly this order
            wine start \
                ./srcds.exe \
                -console \
                -game reactivedrop \
                -autoupdate \
                -port "${port}" \
                -threads 1 \
                -nomessagebox \
            	  -nocrashdialog \
            	  -authkey "${srcds_authkey}" \
                -num_edicts 4096 \
                +con_logfile /dev/stderr \
                +con_timestamp 1 \
                +exec $config \
                +sm_basepath $smbase \
                +ip "${ip}" ${srcds_params}

            # wait a bit before attempting to start the next server
            sleep $SLEEP_TIME
         fi
    done

    sleep $SLEEP_TIME
done
