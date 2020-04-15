#!/bin/sh

full_cmd=$(cat /proc/cmdline) 
trimmed_cmd=${full_cmd#*XORGCONFIG=}
#echo $trimmed_cmd
xorg_conf_path=${trimmed_cmd%% *}
echo $xorg_conf_path
ln -s -f /etc/X11/$xorg_conf_path /etc/X11/xorg.conf
