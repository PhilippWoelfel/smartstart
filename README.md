# smartstart
Bash script to start periodic jobs based on X idle time

## Usage:

smartstart.sh <options> <delta time> <idle time> <command>
  
delta time: <integer>[m|h|d]
idle time: <integer>[m|h|d]
  
Runs <command>, if the XWindow system was idle for at least <idle time> *and* <command> was last run at least <delta time> ago.
  
To see an overview of scripts run last, use the options --warnings, --report, or --color-report

## Requirements:
* ansi-color: https://code.google.com/p/ansi-color/
* xprintidle: https://github.com/g0hl1n/xprintidle (executable`xprintidle` must be in $PATH.
