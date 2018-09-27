
#!/bin/bash
SMSTDIR=$HOME/.smartstart
SPOOLDIR=$SMSTDIR/spool
LOGDIR="$SMSTDIR/log"
DBASE="$SMSTDIR/dbase.csv"
CONF="$SMSTDIR/smartstart.conf"

RESETCOLOR="\e[0m"


##################################################
#These can be changed by the user:
#For escape sequences see https://misc.flogisoft.com/bash/tip_colors_and_formatting
user_variables="SUCCESSCOLOR ERRCOLOR REPORT_SUCCESSCOLOR REPORT_ERRCOLOR REPORT_WARNCOLOR WARNTIME ERRTIME"
SUCCESSCOLOR="\e[48;5;28m"
ERRCOLOR="\e[41m"
REPORT_SUCCESSCOLOR="\e[48;5;28m"
REPORT_ERRCOLOR="\e[48;5;1m"
REPORT_WARNCOLOR="\e[48;5;172m"
WARNTIME=3d
ERRTIME=5d
##################################################

function print_usage {
 SNAME=`basename $0`
 cat <<"EOF"
usage: $SNAME [<options>] <command>

options:
[-c|--conf] <filename>: specify a configuration file (default: "$CONF").
[-d|--dbase] <filename>": use <filename> for database (default: "$DBASE").

EOF
  exit 1
}

function report_line {
 now=`date +%s`
 shift 2

 cmdname="$*"
 hash=`get_hash "$cmdname"`
 SPOOLFILE="$SPOOLDIR"/"$hash"

 if [ -r $SPOOLFILE ]; then
   #If $SPOOLFILE exists, set its modification time
   modtime=`stat -c"%Y" $SPOOLFILE`
   seconds=$((now-modtime))
   minutes=$((seconds/60))
   hours=$((minutes/60))
   days=$((hours/24))
   # Set colors:
   echo -en "$REPORT_SUCCESSCOLOR"
   test $minutes -gt $WARNMIN && echo -en "$REPORT_WARNCOLOR"
   test $minutes -gt $ERRMIN && echo -en "$REPORT_ERRCOLOR"
   # Output
   printf "%03dd %02dh %02dm ago: $cmdname  (`basename $SPOOLFILE`)" ${days} $((hours%24)) $((minutes%60))
 else
  echo -en "${REPORT_ERRCOLOR}Never successful: ${cmdname}"
 fi
 echo -e "${RESETCOLOR}"
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
    test $days -ge $WARNTIME && col="$(color black yellow)"
    test $days -ge $ERRTIME && col="$(color black magenta)"
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
    echo "${scripts} smartsart scripts were run in the last $WARNTIME days"
    echo "$(color black magenta)Warnings:$(color nm)"
    do_print_warnings
  else
    echo "$(color black green)${scripts} smartsart scripts were run in the last $WARNTIME days$(color nm)"
  fi
  exit 0
}



function string_to_minutes {
  #$1: string of the form <integer><spec>, where <spec> is one of 'h','m','d'.
  #$2: stores return value, which is the # of minutes represented by the string

  local timestr=$1

  #check length of $timestr
  test ${#timestr} -le 1 && return 1

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
      return 1
  esac
  eval $2="'$mins'"
}

function get_hash {
 #$1: string to generate the hash from
 hash=`echo "$1" | $MD_SUM -`
 hash="${hash:0:32}"
 echo "$hash"
}

function run_it {
  #get parameters and Xidle time
  delta="$1"
  shift
  idle="$1"
  shift
  to_exec="$*"

  hash=`get_hash "$to_exec"`
  d=`date "+%Y-%m-%d %H:%M:%S"`
  echo -n "$to_exec ($hash). "
  XidleMin=0
  XidleMSec=`$XPRINTIDLE`
  XidleSec=$((XidleMSec/1000))
  test -z "$XidleSec" || XidleMin=$(($XidleSec/60))
  #test "$delta" = "-h" -o "$idle" = "-h" -o "$to_exec" = "-h" && return 1

  #f=`date "+%H%M%S"`
  #echo "$f: $XidleSec sec = $XidleMin min"

  #convert strings "delta" and "idle" into integers repr. minutes
  string_to_minutes $delta delta_mins || return 1
  string_to_minutes $idle idle_mins || return 1
  echo -n "Required delta/idle: ${delta_mins}m/${idle_mins}m. "

  SPOOLFILE="$SPOOLDIR"/"$hash"
  ERRLOG="$LOGDIR"/"$hash.err"
  OUTLOG="$LOGDIR"/"$hash.log"

  #Check idle time
  test $XidleMin -lt $idle_mins && echo "Insufficient idle time (${XidleMin}m)" && return 0

  #Check delta time
  if [ -e "$SPOOLFILE" ]; then
    s=`find "$SPOOLFILE" -cmin "-$delta_mins" -print | tr -d ' '`
    test "$s" != "" && echo "Insufficient delta time (${delta_mins}m)" && return 0
  fi

  # Create outputs and execute command
  echo -n "Executing..."
  echo -e "\n\n-----------------------------------------------------------------------------" | tee -a "$OUTLOG" "$ERRLOG" > /dev/null
  echo "$d" | tee -a $OUTLOG "$ERRLOG" > /dev/null
  echo "see '$ERRLOG' for stderr output" >> "$OUTLOG"
  echo "see '$OUTLOG' for stdout output" >> "$OUTLOG"
  echo -e "Stdout output of '$to_exec':" >> "$OUTLOG"
  echo -e "Stderr output of '$to_exec':" >> "$ERRLOG"

  ###########################################
  # Executing the command
  #bash -c "$to_exec 2>&1 >> $LOGFILE >& /dev/null"
  bash -c "$to_exec > >(tee -a $OUTLOG) 2> >(tee -a $ERRLOG >&2)" >& /dev/null
  ###########################################
  EXITSTAT="$?"


  echo -e "-----------------------------------------------------------------------------\nExit status: $EXITSTAT" | tee -a "$OUTLOG" "$ERRLOG" > /dev/null


  # Check return status
  if [ "$EXITSTAT" = "0" ]; then
    echo -e "${SUCCESSCOLOR}Success.${RESETCOLOR}"
    echo "$to_exec" >| "$SPOOLFILE"
  else
    echo -e "${ERRCOLOR}Failed.${RESETCOLOR}"
  fi
  echo -e "-----------------------------------------------------------------------------\n\n" | tee -a "$OUTLOG" "$ERRLOG" > /dev/null
}

function process_configuration_file {
  #########################################
  # Parsing the configuration file
  #########################################
  lineno=0
  set -e
  while read -r line; do
      #note: $line has leading and trailing white space removed!
      ((lineno+=1))
      #echo $lineno: $line

      #Test for comment and empty lines
      line="$(echo $line | sed -e 's%\([^#]*\)#.*%\1%')" #Remove comments
      line="$(echo $line | sed -e 's%^[[:space:]]*%%')" #Remove leading white space
      test -z "$line" && continue

      #Check if the line looks like a variable specification:
      set +e
      varspec=$(echo "$line" | grep -x "[^[:space:]]*=.*$")
      set -e
      if [ ! -z $varspec ]; then
        # Looks like a variable specification
        var=""
        set +e
        for v in ${user_variables}; do
          var=$var`echo "$line" | grep -x "$v=.*$"`
        done
        set -e
        # If it is a valid variable, then $var now has the set command
        if [ -z "$var" ]; then
          # Unknown variable specified. Get its name and print error
          var=$(echo $line | sed -e 's%\([^[:space:]]*\)=.*$%\1%')
          echo "error (line $lineno): unknown variable '$var'"
        else
          #set the variable and check the syntax
          test "$REPORT" = "1" || echo "setting $var"
          eval $var
          string_to_minutes "$WARNTIME" WARNMIN || echo "error (line $lineno): invalid time specification"
          string_to_minutes "$ERRTIME" ERRMIN || echo "error (line $lineno): invalid time specification"
        fi
      else
        # The line is not a variable specification. Try to execute it.
        set -- $line
        if [ $# -ge 3 ]; then #make sure there are at least 3 arguments
          if [ "$REPORT" = "1" ]; then
            report_line $*
          else
            run_it $* || echo "error in line $lineno"
          fi
        else
          echo "error (line $lineno): syntax error in command specification"
        fi
      fi
  done < "$CONF"
}


#########################################
# Error handling
# See https://www.davidpashley.com/articles/writing-robust-shell-scripts/#id2382181
set -e #stop on first error
set -u #stop if using uninitialized variable
#########################################



#########################################
# Check  executables
#########################################
#Check executables
#XIDLETIME=$HOME/bin/xidletime.py
GETOPT=`which getopt`
MD_SUM=`which md5sum`
XPRINTIDLE=`which xprintidle`
for cmd in {$MD_SUM,$XPRINTIDLE,$GETOPT}; do
  if [ ! -x "$cmd" ]; then
   print_usage
   echo "error: cannot find executable '$cmd'"
   exit 1
  fi
done

##########################################
# Set default values for warn and err time
##########################################
string_to_minutes "$WARNTIME" WARNMIN
string_to_minutes "$ERRTIME" ERRMIN


#########################################
# Parsing parameters
#########################################
set -- $($GETOPT --unquoted --options c:d:hr --longoptions conf:,dbase:,help,report -- "$@")
echo checking options "$*"

# Checking options
REPORT=0
while (($#)); do
  case "$1" in
    -d|--dbase)
      DBASE="$2"
      shift 2
      ;;
    -c|--conf)
        CONF="$2"
        shift 2
        ;;
    -h|--help)
        shift
        print_usage
        ;;
    -r|--report)
        shift
        REPORT=1
        ;;
    --)
      shift
      break
      ;;
    *)
      print_usage
      ;;
  esac
done

test -z ${1+x} || print_usage

#########################################
# Checking files
#########################################
for d in {$SPOOLDIR,$LOGDIR}; do
  mkdir -p $d
  if [ ! -d $SPOOLDIR ]; then
    echo "error: configuration file '$CONF'" not found
    exit 1
  fi
done

if [ ! -r "$CONF" ]; then
  echo "error: configuration file '$CONF'" not found
  exit 1
fi
if [ ! -r "$DBASE" ]; then
  echo "warning: database '$DBASE' not found. Creating."
  touch "$DBASE" > /dev/null || echo "error: cannot create '$DBASE'" && exit 1
fi

if [ "$REPORT" = "1" ]; then
  process_configuration_file | uniq
else
  process_configuration_file
fi
