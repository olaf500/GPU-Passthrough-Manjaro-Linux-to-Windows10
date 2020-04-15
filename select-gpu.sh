#!/bin/sh

## load kernel parameters
full_cmd=$(cat /proc/cmdline) 

## trim all before XORGCONFIG=
trimmed_cmd=${full_cmd#*XORGCONFIG=}

## trim all after the first space including the space
xorg_conf_path=${trimmed_cmd%% *}

## create symlink in the standard location
echo $xorg_conf_path
ln -s -f /etc/X11/$xorg_conf_path /etc/X11/xorg.conf
