# check_ndrestart
System/services restart need check plugin for Nagios/Icinga

## Description
Nagios plugin (script) to if the system needs to be restarted or if some processes/services need to be restarted following some package updates.

## Usage
./check_ndrestart.sh

## Installation
Some sudo settings need to be configured. Add a file /etc/sudoers.d/check_ndrestart containing:
```
Defaults:icinga   !requiretty
icinga ALL=(root) NOPASSWD: /usr/bin/needs-restarting
```
