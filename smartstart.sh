#!/bin/bash
#Needs ansi-color installed: https://code.google.com/p/ansi-color/


SPOOLDIR=$HOME/localroot/var/spool/smartstart
LOGDIR="$HOME/localroot/var/log"

WARNTHRESHHOLD=3
ERRTHRESHHOLD=7

function print_usage {
 SNAME=`basename $0`
 echo
 echo "usage: $SNAME <options> <delta time> <idle time> <command>"
 echo "  where <delta time> and <idle time>"
 echo "  are specified as <integer>[m|h\d]."
 echo
 echo "Runs <command>, if the X system was idle <idletime> AND"
 echo "<command> was last run <delta time> ago"
 echo
 echo "To print warnings or report use --warnings --report or --color-report"
 exit 1
}

function print_report {
 now=`date +%s`
# echo time passed since last successful runs:
#echo

#  echo -e ${LIGHTRED} smartstart report:
 for sfile in $SPOOLDIR/*; do
   cmdname=`cat "$sfile"`
   hash=`get_hash "$cmdname"`
   modtime=`stat -c"%Y" $sfile`
   seconds=$((now-modtime))
   minutes=$((seconds/60))
   hours=$((minutes/60))
   days=$((hours/24))
   printf "%03dd %02dh %02dm ago:   $cmdname  (`basename $sfile`)\n" ${days} $((hours%24)) $((minutes%60))
#    printf "%03dd %02dh %02dm %02ds ago:   $cmdname  (`basename $sfile`)\n" ${days} $((hours%24)) $((minutes%60)) $((seconds%60))
 done | sort -r
}

function print_color_report {
  print_report | \
  while read line; do
    days=`echo $line | cut -c 1-3`
    col="$(color green)"
    test $days -ge 2 && col="$(color black yellow)"
    test $days -ge 7 && col="$(color black magenta)"
#     test $days -gt 3 && echo "$(color black magenta)$line$(color nm)"
    echo "$col$line$(color nm)"
  done
  exit 0
}

function do_print_warnings {
  print_report | \
  while read line; do
    days=`echo $line | cut -c 1-3`
    col=""
    test $days -ge $WARNTHRESHHOLD && col="$(color black yellow)"
    test $days -ge $ERRTHRESHHOLD && col="$(color black magenta)"
    test "$col" != "" && echo "$col$line$(color nm)" && wct=$((wct+1))
  done
}

function count_scripts {
  print_report | wc -l
}

function print_warnings {
  scripts=`print_report | wc -l`
  warnings=`do_print_warnings | wc -l`
  if [ $warnings -ge 1 ]; then
    echo "${scripts} smartsart scripts were run in the last $WARNTHRESHHOLD days"
    echo "$(color black magenta)Warnings:$(color nm)"
    do_print_warnings
  else
    echo "$(color black green)${scripts} smartsart scripts were run in the last $WARNTHRESHHOLD days$(color nm)"
  fi
  exit 0
}



function string_to_minutes {
  #$1: string of the form <integer><spec>, where <spec> is one of 'h','m','d'.
  #$2: stores return value, which is the # of minutes represented by the string

  local timestr=$1

  #check length of $timestr
  test ${#timestr} -le 1 && echo "error: '$1' is not a valid time specification" && print_usage

  #get the correct time parameter:
  local spec=${timestr: -1:1}
  local int=${timestr:0:$((${#timestr}-1))}
  local mins
  case $spec in
    m)
      mins="$int";;
    h)
      mins="$((int*60))";;
    d)
      mins="$((int*60*24))";;
    *)
      echo "error: '$1' is not a valid time specification"
      print_usage
  esac
  eval $2="'$mins'"
}

function get_hash {
 #$1: string to generate the hash from
 hash=`echo "$1" | $MD_SUM -`
 hash="${hash:0:32}"
 echo "$hash"
}

thiscmd="$*"

#Check executables
MD_SUM=/usr/bin/md5sum
#XIDLETIME=$HOME/bin/xidletime.py
XPRINTIDLE=/usr/bin/xprintidle
for cmd in {$MD_SUM,$XPRINTIDLE}; do
  if [ ! -x "$cmd" ]; then
   print_usage
   echo "error: cannot find executable '$cmd'"
   exit 1
  fi
done

test "$1" = "--help" && print_usage
test "$1" = "--report" && print_report && exit 0
test "$1" = "--color-report" && print_color_report
test "$1" = "--warnings" && print_warnings


#get parameters and Xidle time
delta="$1"
shift
idle="$1"
shift
to_exec="$*"
hash=`get_hash "$to_exec"`
d=`date "+%Y-%m-%d %H:%M:%S"`
echo -n "$d; $to_exec; $hash; "
XidleMin=0
XidleMSec=`$XPRINTIDLE`
XidleSec=$((XidleMSec/1000))

test -z "$XidleSec" || XidleMin=$(($XidleSec/60))
test "$delta" = "-h" -o "$idle" = "-h" -o "$to_exec" = "-h" && print_usage

f=`date "+%H%M%S"`
echo "$f: $XidleSec sec = $XidleMin min"


#convert strings "delta" and "idle" into integers repr. minutes
string_to_minutes $delta delta_mins
string_to_minutes $idle idle_mins
echo -n "required delta/idle time: ${delta_mins}m/${idle_mins}m. "

SPOOLFILE="$SPOOLDIR"/"$hash"
LOGFILE="$LOGDIR"/"$hash.log"

test -d "$SPOOLDIR" || mkdir "$SPOOLDIR"
if [ ! -d "$SPOOLDIR" ]; then
  echo "error: cannot create $SPOOLDIR"
  exit
fi

test -d "$LOGDIR" || mkdir "$LOGDIR"
if [ ! -d "$LOGDIR" ]; then
  echo "error: cannot create $LOGDIR"
  exit
fi


#Check idle time
test $XidleMin -lt $idle_mins && echo "insufficient idle time" && exit
#Check delta time
s=`find "$SPOOLFILE" -cmin "-$delta_mins" -print | tr -d ' '`
test "$s" != "" && echo "insufficient delta time" && exit

echo "executing '$to_exec'"
echo -e "\n\n-----------------------------------------------------------------------------" >> "$LOGFILE"
echo "$d" >> "$LOGFILE"
echo "$0 $thiscmd" >> "$LOGFILE"
echo >> "$LOGFILE"
($to_exec 2>&1) >> "$LOGFILE"

if [ "$?" = "0" ]; then
  echo "succeeded" >> "$LOGFILE"
  echo "execution of '$to_exec' succeeded."
  echo "$to_exec" >| "$SPOOLFILE"
else
  echo "execution of '$to_exec' failed."
  echo "failed" >> "$LOGFILE"
fi
