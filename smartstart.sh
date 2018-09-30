#!/bin/bash

##################################################
# Required executables
# We will check whether all the onese mentioned in $exec_list are present
DATE=`which date`
GETOPT=`which getopt`
GREP=`which grep`
MD_SUM=`which md5sum`
PS=`which ps`
SED=`which sed`
SORT=`which sort`
TR=`which tr`
UNIQ=`which uniq`
WC=`which wc`
XPRINTIDLE=`which xprintidle`
exec_list="$GETOPT $GREP $MD_SUM $PS $SED $SORT $TR $UNIQ $WC $XPRINTIDLE"
##################################################


##################################################
# Default directories and files
##################################################
SCRIPTNAME=$0
SMSTDIR=$HOME/.smartstart
SPOOLDIR=$SMSTDIR/spool
LOGDIR="$SMSTDIR/log"
DBASE="$SMSTDIR/dbase.csv"
RESETCOLOR="\e[0m"


##################################################
#These can be changed by the user:
#For escape sequences see https://misc.flogisoft.com/bash/tip_colors_and_formatting
SUCCESSCOLOR="\e[48;5;28m"
ERRCOLOR="\e[41m"
WARNCOLOR="\e[48;5;172m"
REPORT_SUCCESSCOLOR="\e[48;5;28m"
REPORT_ERRCOLOR="\e[48;5;1m"
REPORT_WARNCOLOR="\e[48;5;172m"
WARNTIME=3d
ERRTIME=7d
##################################################
user_variables="SUCCESSCOLOR ERRCOLOR REPORT_SUCCESSCOLOR REPORT_ERRCOLOR REPORT_WARNCOLOR WARNTIME ERRTIME"
##################################################


##################################################
#Affected by options
STATS="False" # Whether or not "--stats" option was chosen
REPORT="False" # Whether or not "--report" option was chosen
REPORT_LEVEL=0
COLPRE="" # Will be set to $RESETCOLOR, if "--nocolor" option was chosen.
CONFFILE="$HOME/.config/smartstart.conf" # Configuration file; can be changed by option
##################################################

##################################################
# Other options
NOW=`${DATE} +%s`
##################################################

function print_usage {
  s=`basename $SCRIPTNAME`
  cat <<EOF
usage: $s [<options>] <command>

options:
[-c|--conf] <filename>: specify a configuration file (default: "$CONFFILE").

EOF
  exit 1
}

function report_line {
  # $1 is used for return value
  # The rest of the argument is a command line
  # Prints the command status, and stores status in $1
  # Status: 0 if success, 1 if warning, 2 if error.
  #
  __stat=$1
  shift 3

  cmdname="$*"
  hash=`get_hash "$cmdname"`
  SPOOLFILE="$SPOOLDIR"/"$hash"

  #If $SPOOLFILE exists, set its modification time
  modtime=0 # Use beginning of epoch in case SPOOLFILE does not exist
  test -r $SPOOLFILE && modtime=`stat -c"%Y" $SPOOLFILE`
  seconds=$((NOW-modtime))
  minutes=$((seconds/60))
  hours=$((minutes/60))
  days=$((hours/24))

  # Set colors and return possibly return if report level is low enough
  if [ $minutes -le $WARNMIN ]; then
    OUTPREFIX="(s)"
    eval $__stat=0 #Set return status
    test $REPORT_LEVEL -gt 0 && return
    echo -en "${RESETCOLOR}$REPORT_SUCCESSCOLOR"
  else
    if [ $minutes -le $ERRMIN ]; then
     OUTPREFIX="(w)"
     eval $__stat=1 #Set return status
     test $REPORT_LEVEL -gt 1 && return
     echo -en "${RESETCOLOR}$REPORT_WARNCOLOR"
    fi
  fi
  if [ $minutes -gt $ERRMIN ]; then
    OUTPREFIX="(e)"
    eval $__stat=2 #Set return status
    echo -en "${RESETCOLOR}$REPORT_ERRCOLOR"
  fi

  #Reset color, if --nocolor option was chosen
  echo -en "${COLPRE}"

  # Output
  if [ $modtime = 0 ]; then
    echo -en "${REPORT_ERRCOLOR}${COLPRE}$OUTPREFIX Never successful: ${cmdname}"
  else
    printf "$OUTPREFIX %03dd %02dh %02dm ago: $cmdname  (`basename $SPOOLFILE`)" ${days} $((hours%24)) $((minutes%60))
  fi

  echo -e "${RESETCOLOR}"
  return
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

function run_line {
  #get parameters and Xidle time
  delta="$1"
  shift
  idle="$1"
  shift
  to_exec="$*"
  command=`basename "$1"`
  pidfile=$SPOOLDIR/.$command.pid

  hash=`get_hash "$to_exec"`
  d=`${DATE} "+%Y-%m-%d %H:%M:%S"`
  echo -n "$to_exec ($hash). "


  if [ -r "$pidfile" ]; then
    pid=`cat $pidfile | $TR -d ' '`
    #echo $pid
    set +e
    ptime=`$PS -o etime $pid | $GREP "[[:digit:]]:[[:digit:]]" | tr -d ' '`
    set -e
    #echo $ptime
    if [ "$ptime" != "" ]; then
      echo -e "${WARNCOLOR}Skipping: ${RESETCOLOR}Concurrent process '$command' with PID $pid found. (Elapsed time : $ptime.)"
      return
    else
      echo -n "removing stale PID file."
      rm "$pidfile"
    fi
  fi

  XidleMin=0
  XidleMSec=`$XPRINTIDLE`
  XidleSec=$((XidleMSec/1000))
  test -z "$XidleSec" || XidleMin=$(($XidleSec/60))
  #test "$delta" = "-h" -o "$idle" = "-h" -o "$to_exec" = "-h" && return 1

  #f=`${DATE} "+%H%M%S"`
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
    s=`find "$SPOOLFILE" -cmin "-$delta_mins" -print | ${TR} -d ' '`
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
  bash -c "$to_exec > >(tee -a $OUTLOG) 2> >(tee -a $ERRLOG >&2)" >& /dev/null &
  pid="$!"
  echo $pid > "$pidfile"
  wait $!
  ##########################################
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
  #####################################################################
  # Parses the configuration file and either executes or reports each
  # line, depending on status of REPORT variable
  # If REPORT=True, then it sets $1, $2, and $3 to the number
  # of successes, warnings, and errors reported
  #####################################################################
  lineno=0
  # The following array will contain the number of successful/failed/and errors.
  # But we're not using it right now.
  STATARR=(0 0 0)
  while read -r line; do
      #note: $line has leading and trailing white space removed!
      ((lineno+=1))
      #echo $lineno: $line

      #Test for comment and empty lines
      line="$(echo $line | ${SED} -e 's%\([^#]*\)#.*%\1%')" #Remove comments
      line="$(echo $line | ${SED} -e 's%^[[:space:]]*%%')" #Remove leading white space
      test -z "$line" && continue

      #Check if the line looks like a variable specification:
      set +e
      varspec=$(echo "$line" | ${GREP} -x "[^[:space:]]*=.*$")
      set -e
      if [ ! -z $varspec ]; then
        # Looks like a variable specification
        var=""
        set +e
        for v in ${user_variables}; do
          var=$var`echo "$line" | ${GREP} -x "$v=.*$"`
        done
        set -e
        # If it is a valid variable, then $var now has the set command
        if [ -z "$var" ]; then
          # Unknown variable specified. Get its name and print error
          var=$(echo $line | ${SED} -e 's%\([^[:space:]]*\)=.*$%\1%')
          echo "error (line $lineno): unknown variable '$var'"
        else
          #set the variable and check the syntax
          test "$REPORT" = "False" && echo "setting $var"
          eval $var
          string_to_minutes "$WARNTIME" WARNMIN || echo "error (line $lineno): invalid time specification"
          string_to_minutes "$ERRTIME" ERRMIN || echo "error (line $lineno): invalid time specification"
        fi
      else
        # The line is not a variable specification. Try to execute it.
        set -- $line
        if [ $# -ge 3 ]; then #make sure there are at least 3 arguments
          if [ "$REPORT" = "True" ]; then
            #Output report for line $*, and store return value in stat
            report_line stat $*
            ((STATARR[$stat]+=1))
          else
            run_line $* || echo "error in line $lineno"
          fi
        else
          echo "error (line $lineno): syntax error in command specification"
        fi
      fi
  done < "$CONFFILE"
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
for cmd in $exec_list; do
  if [ ! -x "$cmd" ]; then
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
set -- $($GETOPT --unquoted --options c:d:r:hns --longoptions conf:,dbase:,report:,help,nocolor,stats -- "$@")
#echo checking options "$*"

# Checking options
while (($#)); do
  case "$1" in
    -c|--conf)
        CONFFILE="$2"
        shift 2
        ;;
    -d|--dbase)
      DBASE="$2"
      shift 2
      ;;
    -h|--help)
        shift
        print_usage
        ;;
    -n|--nocolor)
        shift
        COLPRE="$RESETCOLOR"
        ;;
    -r|--report)
        REPORT="True"
        # Test if parameter is integer:
        if [[ $2 =~ ^-?[0-9]+$ ]]; then
          # Test if parameter is between 0 and 3
          if [ $2 -ge 0 -a $2 -le 2 ]; then
            REPORT_LEVEL="$2"
          else
            echo "error: report level must be between 0 and 2"
            exit 1
          fi
        else
          echo -e "error: -r requires numerical argument\n"
          exit 1
        fi
        shift 2

        ;;
    -s|--stats)
        shift
        STATS="True"
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
    echo "error: configuration file '$CONFFILE'" not found
    exit 1
  fi
done

if [ ! -r "$CONFFILE" ]; then
  echo "error: configuration file '$CONFFILE'" not found
  exit 1
fi
if [ ! -r "$DBASE" ]; then
  echo "warning: database '$DBASE' not found. Creating."
  touch "$DBASE" > /dev/null || echo "error: cannot create '$DBASE'" && exit 1
fi

if [ "$REPORT" = "True" ]; then
  # The following removes duplicate lines and escape sequences
  process_configuration_file | ${UNIQ}
  # output=$(process_configuration_file | ${UNIQ} )
  # echo "$output"
fi

if [ "$STATS" = "True" ]; then
  # if [ "$REPORT" != "True" -o "$REPORT_LEVEL" != "0" ]; then
   # if we haven't computed a proper output already, we need to comput it:
   # REPORT="True"
   # REPORT_LEVEL=0
   # output=$(process_configuration_file | ${UNIQ} )
  output=$($SCRIPTNAME -r 0)
  # fi
  # Remove escape sequences, see
  # https://www.commandlinefu.com/commands/view/12043/remove-color-special-escape-ansi-codes-from-text-with-sed
  output=$(echo "$output" | ${SED} "s,\x1B\[[0-9;]*[a-zA-Z],,g")

  # Grep for the right lines
  set +e
  NB_SUCCESS=`echo "$output" | ${GREP} -x -c "(s).*$"`
  NB_WARN=`echo "$output" | ${GREP} -x -c "(w).*$"`
  NB_ERR=`echo "$output" | ${GREP} -x -c "(e).*$"`
  TOTAL=`echo "$output" | ${WC} -l`
  set -e
  # test  $NB_WARN -gt 0 && echo -e -n "$REPORT_WARNCOLOR"
  # test  $NB_ERR -gt 0 && echo -e -n "$REPORT_ERRCOLOR"
  echo -e "Among $TOTAL different smarstart commands $NB_SUCCESS have status success, $NB_WARN status warn, and $NB_ERR status error.${RESETCOLOR}"
fi

if [ "$REPORT" != "True" -a "$STATS" != "True" ]; then
  process_configuration_file
fi
