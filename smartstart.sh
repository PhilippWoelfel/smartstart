#!/usr/bin/env bash

##################################################
# Required executables
# We will check whether all the onese mentioned are present
CAT="cat"
DATE="date"
GETOPT="getopt"
GREP="grep"
MD_SUM="md5sum"
MV="mv"
PS="ps"
RM="rm"
SED="sed"
SORT="sort"
TR="tr"
UNIQ="uniq"
WC="wc"
XPRINTIDLE=`which xprintidle 2> /dev/null`
test -x "$XPRINTIDLE" || XPRINTIDLE=`which xprintidle-ng`
exec_list="$CAT $DATE $GETOPT $GREP $MD_SUM $MV $PS $RM $SED $SORT $TR $UNIQ $WC $XPRINTIDLE"
##################################################

#########################################
# Error handling
# See https://www.davidpashley.com/articles/writing-robust-shell-scripts/#id2382181
set -e #stop on first error
set -u #stop if using uninitialized variable
#########################################

##################################################
# Defaults that can easily be changed in script
##################################################
SMSTDIR=$HOME/.smartstart
SPOOLDIR=$SMSTDIR/spool
LOGDIR="$SMSTDIR/log"
REPORT_FILE="$SMSTDIR/report.txt"
TMP_REPORT_FILE="$SMSTDIR/.report.tmp"

##################################################
# Defaults that can be changed by options
NO_EXECUTE="False" # Will be set to True if "-g" option is chosen
REPORT_LEVEL=0 # Level of report to be printed (default 0 means no report)
NOCOLOR="False" # Will be set to true if "--nocolor" option is chosen
CONFFILE="$HOME/.config/smartstart.conf" # Configuration file; can be changed by option -c
MAX_REPORT_AGE="2h" #maximum age of report until regeneration; can be changed by option -m
##################################################

##################################################
#Defaults that can be changed by the user in the config file
#For escape sequences see https://misc.flogisoft.com/bash/tip_colors_and_formatting
REPORT_SUCCESSCOLOR="\e[48;5;28m"
REPORT_ERRCOLOR="\e[48;5;1m"
REPORT_WARNCOLOR="\e[48;5;172m"
SUCCESSCOLOR="\e[48;5;28m" #Color for success message when script is run
ERRCOLOR="\e[41m" #Color for error  message when script is run
WARNCOLOR="\e[48;5;172m" #Color for warning message when script is run
WARNTIME=3d
ERRTIME=7d
##################################################
user_variables="SUCCESSCOLOR ERRCOLOR WARNCOLOR REPORT_SUCCESSCOLOR REPORT_ERRCOLOR REPORT_WARNCOLOR WARNTIME ERRTIME"
##################################################

##################################################
# Other variables
SCRIPTNAME=$0
RESETCOLOR="\e[0m"
##################################################

function print_usage {
  s=`basename $SCRIPTNAME`
  "$CAT" <<EOF
usage: $s [<options>] <command>

options:
[-c|--conf] <filename>: specify a configuration file (default: "$CONFFILE").
[-g|--generate]: Force report generation (does not execute any commands).
[-h|--help]: Print help
[-m|--max_report_age] <time>: Change the maximum age of cached report.
[-n|--nocolor]: Use no color in output.
[-r|--report] <level>: prints the latest cached report with reporting level <level>, where the levels are
                       1: only errors
                       2: errors and warnings
                       3: all messages
[--run] '<cmd>': Runs command <cmd> unconditionally. It is recommended to use quotes '' around the command to avoid parameter expansion.
[-s|--status]: prints status information obtained from the latest cached report.

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
  shift 4

  cmdname="$*"
  hash=`get_hash "$cmdname"`
  SPOOLFILE="$SPOOLDIR"/"$hash"

  #If $SPOOLFILE exists, set its modification time
  modtime=0 # Use beginning of epoch in case SPOOLFILE does not exist
  test -r "$SPOOLFILE" && modtime=`stat -c"%Y" $SPOOLFILE`
  NOW=`${DATE} +%s`
  seconds=$((NOW-modtime))
  minutes=$((seconds/60))
  hours=$((minutes/60))
  days=$((hours/24))

  # Set status prefix
  if [ $minutes -le $WARNMIN ]; then
    #stat=SUCCESS
    OUTPREFIX="(s)"
    eval $__stat=0 #Set return status
    #echo -en "${RESETCOLOR}$REPORT_SUCCESSCOLOR"
  else
    if [ $minutes -le $ERRMIN ]; then
     #stat=WARN
     OUTPREFIX="(w)"
     eval $__stat=1 #Set return status
     #echo -en "${RESETCOLOR}$REPORT_WARNCOLOR"
    fi
  fi
  if [ $minutes -gt $ERRMIN ]; then
    #stat=ERROR
    OUTPREFIX="(e)"
    eval $__stat=2 #Set return status
    #echo -en "${RESETCOLOR}$REPORT_ERRCOLOR"
  fi

  # Output
  if [ $modtime = 0 ]; then
    #echo -en "${REPORT_ERRCOLOR}${COLPRE}$OUTPREFIX Never successful: ${cmdname}"
    echo -en "$OUTPREFIX Never successful: ${cmdname}"
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
  ##########################################
  #Set up variables
  delta="$1"
  shift
  idle="$1"
  shift
  commandid=$1
  shift
  to_exec="$*"
#  command=`basename $1`
  pidfile=$SPOOLDIR/.$commandid.pid

  hash=`get_hash "$to_exec"`
  SPOOLFILE="$SPOOLDIR"/"$hash"
  ERRLOG="$LOGDIR"/"$hash.err"
  OUTLOG="$LOGDIR"/"$hash.log"

  # Make sure no colors are printed if --nocolor option was chosen
  if [ "$NOCOLOR" = "True" ]; then
    WARNCOLOR=""; ERRCOLOR=""; SUCCESSCOLOR=""
  fi

  echo -n "$to_exec ($hash). "
  ##########################################

  #################################
  #Check for concurrent script
  if [ -r "$pidfile" ]; then
    pid=`"$CAT" "$pidfile" | $TR -d ' '`
    #echo $pid
    set +e
    ptime=`$PS -o etime $pid | $GREP "[[:digit:]]:[[:digit:]]" | tr -d ' '`
    set -e
    #echo $ptime
    if [ "$ptime" != "" ]; then
      echo -e "${WARNCOLOR}Skipping: ${RESETCOLOR}Concurrent process with ID '$commandid' with PID $pid found. (Elapsed time : $ptime.)"
      return
    else
      echo -n "Removing stale PID file. "
      rm "$pidfile"
    fi
  fi
  #################################

  #################################3
  #Check idle requirements
  XidleMin=0
  XidleMSec=`$XPRINTIDLE`
  XidleSec="$((XidleMSec/1000))"
  XidleMin="$(($XidleSec/60))"
  echo -n "Idle (msec / sec / min): $XidleMSec / $XidleSec / $XidleMin. "

  #convert strings "delta" and "idle" into integers repr. minutes
  string_to_minutes $delta delta_mins || return 1
  string_to_minutes $idle idle_mins || return 1
  echo -n "Required delta/idle: ${delta_mins}m/${idle_mins}m. "

  test $XidleMin -lt $idle_mins && echo "Insufficient idle time (${XidleMin}m)" && return 0
  #################################3

  #################################
  #Check delta time
  if [ -e "$SPOOLFILE" ]; then
    s=`find "$SPOOLFILE" -cmin "-$delta_mins" -print | ${TR} -d ' '`
    test "$s" != "" && echo "Insufficient delta time (${delta_mins}m)" && return 0
  fi
  #################################

  #################################
  # Create outputs and execute command
  d=`${DATE} "+%Y-%m-%d %H:%M:%S"`
  echo -n "Executing..."
  echo -e "\n\n-----------------------------------------------------------------------------" | tee -a "$OUTLOG" "$ERRLOG" > /dev/null
  echo "$d" | tee -a $OUTLOG "$ERRLOG" > /dev/null
  echo "see '$ERRLOG' for stderr output" >> "$OUTLOG"
  echo "see '$OUTLOG' for stdout output" >> "$OUTLOG"
  echo -e "Stdout output of '$to_exec':" >> "$OUTLOG"
  echo -e "Stderr output of '$to_exec':" >> "$ERRLOG"
  #################################


  ###########################################
  # Executing the command
  #bash -c "$to_exec 2>&1 >> $LOGFILE >& /dev/null"
  bash -c "$to_exec > >(tee -a $OUTLOG) 2> >(tee -a $ERRLOG >&2)" >& /dev/null &
  pid="$!"
  echo $pid > "$pidfile"
  wait $!
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
  ##########################################
}

function process_configuration_file {
  #####################################################################
  # Parses the configuration file and either executes or reports each
  # line, depending on status of REPORT variable
  # If REPORT_LEVEL>=1, then it sets $1, $2, and $3 to the number
  # of successes, warnings, and errors reported
  #####################################################################
  lineno=0

  # Replace the report file
  echo "smarstart in progress -- no report available" > "$REPORT_FILE"
#  $RM -f "$REPORT_FILE"

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
          eval $var
          string_to_minutes "$WARNTIME" WARNMIN || echo "error (line $lineno): invalid time specification"
          string_to_minutes "$ERRTIME" ERRMIN || echo "error (line $lineno): invalid time specification"
        fi
      else
        # The line is not a variable specification. Try to execute it.
        set -- $line
        if [ $# -ge 3 ]; then #make sure there are at least 3 arguments
          if [ "$NO_EXECUTE" != "True" ]; then #Check the NO_EXECUTE flag
            run_line $* || echo "error in line $lineno"
          fi
          #Output report for line $*, and store return value in stat
          report_line stat $* >> "$TMP_REPORT_FILE"
          ((STATARR[$stat]+=1))
        else
          echo "error (line $lineno): syntax error in command specification"
        fi
      fi
  done < "$CONFFILE"

  $MV $TMP_REPORT_FILE $REPORT_FILE
}

function assert_report_file {
  # Makes sure recent enough report file exists.
  if [ -r "$REPORT_FILE" ]; then
    string_to_minutes $MAX_REPORT_AGE __max_report_age
    s=`find "$REPORT_FILE" -cmin "-$__max_report_age" -print | ${TR} -d ' '`
    if [ "$s" = "" ]; then
      echo "Report file too old. Generating..." > /dev/stderr
      "$SCRIPTNAME" -g
    fi
  else
    echo "Cannot read file '$REPORT_FILE'. Generating..." > /dev/stderr
    "$SCRIPTNAME" -g
  fi

  if [ ! -r "$REPORT_FILE" ]; then
    echo "Error!"
    exit 1
  fi
}

function print_stats {
  # Prints stats based on $REPORT_FILE

  assert_report_file

  # Remove escape sequences, see
  # https://www.commandlinefu.com/commands/view/12043/remove-color-special-escape-ansi-codes-from-text-with-sed
  # (Not necessary aymore, because we don't add them in file creation.)
  # output=$("$CAT" "$REPORT_FILE" | ${SED} "s,\x1B\[[0-9;]*[a-zA-Z],,g")

  # get only unique lines
  output=`"$CAT" "$REPORT_FILE" | ${UNIQ}`

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
}

function print_report {
  assert_report_file

  output=`"$CAT" $REPORT_FILE | ${UNIQ}`
  set +e
  #Remove "(s)" lines for for REPORT_LEVEL <= 2 and (w) lines for REPORT_LEVEL<=1.
  test $REPORT_LEVEL -le 2 && output=`echo "$output" | ${GREP} -v "(s)"`
  test $REPORT_LEVEL -le 1 && output=`echo "$output" | ${GREP} -v "(w)"`
  set -e

  #Adjust color variables, if --nocolor option was given
  if [ "$NOCOLOR" = "True" ]; then
    REPORT_WARNCOLOR=""
    REPORT_ERRCOLOR=""
    REPORT_SUCCESSCOLOR=""
  fi

  #Replace (s), (w), and (e) with color codes:
  output=`echo "$output" \
  | $SED -e "s%^(s) %\\\\${REPORT_SUCCESSCOLOR}%" \
  | $SED -e "s%^(w) %\\\\${REPORT_WARNCOLOR}%" \
  | $SED -e "s%^(e) %\\\\${REPORT_ERRCOLOR}%"`

  echo -e "$output" | $UNIQ
}

#########################################
# Check  executables
#########################################
#Check executables
#XIDLETIME=$HOME/bin/xidletime.py
set +e
for cmdname in $exec_list; do
  cmd=`command -v $cmdname`
  if [ ! -x "$cmd" ]; then
   echo "error: cannot find executable '$cmdname'"
   exit 1
  fi
done
set -e

##########################################
# Set default values for warn and err time
##########################################
string_to_minutes "$WARNTIME" WARNMIN
string_to_minutes "$ERRTIME" ERRMIN


#########################################
# Parsing parameters
#########################################
opt=$($GETOPT --unquoted --options c:m:r:ghns --longoptions conf:,max_report_age:,report:,run:,generate,help,nocolor,stats -- "$@")
set -- $opt
#echo checking options "$*"

# Checking options
PRINT_REPORT="False"
PRINT_STATS="False"
while (($#)); do
  case "$1" in
    -c|--conf)
        CONFFILE="$2"
        shift 2
        ;;
    -g|--generate)
        NO_EXECUTE="True"
        process_configuration_file
        shift
        ;;
    -h|--help)
        shift
        print_usage
        ;;
    -m|--max_report_age)
        test -z "$2" && print_usage
        MAX_REPORT_AGE="$2"
        shift 2
        ;;
    -n|--nocolor)
        shift
        NOCOLOR="True"
        ;;
    -r|--report)
        # Test if parameter is integer:
        if [[ $2 =~ ^-?[0-9]+$ ]]; then
          # Test if parameter is between 1 and 3
          if [ $2 -ge 1 -a $2 -le 3 ]; then
            REPORT_LEVEL="$2"
            PRINT_REPORT="True"
          else
            echo "error: report level must be between 1 and 3"
            exit 1
          fi
        else
          echo -e "error: -r requires numerical argument\n"
          exit 1
        fi
        shift 2
        ;;
    --run)
      shift
      set -- "${@:1:$(($#-1))}" # Remove last argument, which is "--"
      run_line 0m 0m cli_run $*
      $SCRIPTNAME --generate
      exit
      ;;
    -s|--stats)
        shift
        if [ "$PRINT_REPORT" = "True" ]; then
          echo "error: at most one of '-z' and '-r' can be used"
          exit 1
        fi
        PRINT_STATS="True"
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
# Checking / creating files/directories
#########################################
for d in {$SPOOLDIR,$LOGDIR}; do
  mkdir -p "$d"
  if [ ! -d "$d" ]; then
    echo "error: cannot create directory '$d'"
    exit 1
  fi
done

if [ ! -r "$CONFFILE" ]; then
  echo "error: configuration file '$CONFFILE'" not found
  exit 1
fi


if [ "$PRINT_REPORT" = "True" ]; then
  print_report
  exit $?
fi

if [ "$PRINT_STATS" = "True" ]; then
  print_stats
  exit $?
fi

if [ "$NO_EXECUTE" = "False" ] ;then
  echo "Running smartstart scripts at `date`"
  process_configuration_file
fi
