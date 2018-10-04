# smartstart

## Introduction
Smarstart is a program that starts periodic jobs when convenient for the user.
A job will only be started if the X system has been idle for a specified
amount of time, and if the job has not been run successfully for a specified time.
It can be used as an alternative to cron for scheduling frequent critial jobs, such as backups, and CPU or disk heavy jobs (e.g., btrfs-scrub) that should be run when they do not interfer with the user.

In a configuration file, a user can specify a list of of executable commands together with minimum idle and interval times.
When `smartsart.sh` is executed (e.g., in a cron-job), each listed command is executed, if it has not been run successfully since its specified minimum interval time, and the X Windows system has been idle for at least the specified minimum idle time.

Smartstart can also print reports that allow the user to quickly determine which commands have not recently been run successfully.
This allows, for example, to quickly check if periodice backup scripts (e.g., with rsync) have succeeded recently enough.

Smartstart solves a problem with cron-jobs, which are typically run at specified times, or at specified events, such as system startup.
For disk or cpu heavy tasks, this can be invonvenient for the user.
For example users of the btrfs filesystem are advised to run btrfs-scrub at least once a month, but running btrfs-scrub can slow down a system significantly.
Running it at night time on a desktop is problematic, because a user may switch of the system.
Similarly, running it at system startup may slow down the system when it is likely that a user wants to use it.

## Installation
1.Make sure the executable xprintidle (see https://github.com/g0hl1n/xprintidle) is in the $PATH.

1. Copy `smartstart.sh` into a directory in `$PATH`, and create a smarstart configuration file `~/.config/smartstart.config` (see Section [Configuration file](#Configuration-file) below, and the provided sample file [smartstart.config.sample]().
Then add the following line to crontab (using `crontab -e`):
```
@hourly smartstart.sh
```

2. To apply regular log rotation, add the provicefile [logrotate.conf]() to directory ~/.smartstart, and the following line into crontab:
```
@daily /usr/sbin/logrotate -s ~/.smartstart/logrotate.state ~/.smartstart/logrotate.conf
```

3. For automatic reporting on each shell start, add the following lines to `~/.bashrc`:
```bash
smartstart.sh -r 2 2> /dev/null
smartstart.sh -s 2> /dev/null
```


## Usage
```bash
smartstart.sh <options>
```

Reads the configuration file (default [~/.config/smartstart.conf]()), and processes the commands specified therein under certain conditions, or reports on their success status.

## Configuration file
The configuration file specifies which commands to be run by smartstart, and when.
In addition it can be used to influence the output of a smartstart execution, and of reports.

Each line must either be a comment (if it starts by `#`), or it must specify a command or set a variable.
Anything in a line following the symbol `#` is ignored.

1. **Specifying commands:**
  A command can be any string `<cmd>` that can be executed in a bash shell, e.g., using `bash -c "<cmd>"`.  A line of the form

  ```
  <delta time> <idle time> <command>
  ```
  specifies a command, where `delta time` and `idle time` must be valid [time specifications](#Time-specification).
  When smartstart is executed, it will try to run the command `<command>` provided it was not run successfully for at least `<delta time>`, and the X system has been idle for at least `<idle time>`.

  For example, to attempt to run btrfs-scrub weekly on /home at a time when the X-system has been idle for at least 30 minutes, the following line can be put into the configuration file:

  ```bash
  7d 30m sudo btrfs scrub start -Bd /home
  ```

  To run btrfs-scrub on /home in addition unconditionally (no matter whether the X system has been idle) provided it was not run for 30 days, the configuration can be extended by a second line:

  ```bash
   7d 30m sudo btrfs scrub start -Bd /home
   30d 0m sudo btrfs scrub start -Bd /home
   ```


2. **Specifying variables:**
  A line of the form `<variable>=<value>` sets the given variable to the given value.
  The following variables are recognized:
  * `WARNTIME`: Specifies the warning time for the following commands. If a command was not run successfully for the specified amount of time, then it will be reported with the warning flag, when smartstart is run with the option `-r` or `-s`. The default is `3d`.
  * `ERRTIME`: Specifies the warning time for the following commands. If a command was not run successfully for the specified amount of time, then it will be reported with the error flag, when smartstart is run with the option `-r` or `-s`. The default is `7d`.
  * `SUCCESSCOLOR`, `WARNCOLOR`, `ERRCOLOR`: Sets the color used to output success, warning, and error messages, following a command execution in the remainder of the smartstart script. Colors can be specified using escape sequences (see [https://misc.flogisoft.com/bash/tip_colors_and_formatting](https://misc.flogisoft.com/bash/tip_colors_and_formatting)).
  * `REPORT_SUCCESSCOLOR`, `REPORT_WARNCOLOR`, `REPORT_ERRCOLOR`: Sets the color used for reporting commands, if the `-r` option is specified. These variables are gloabal, i.e., the last variable specification in the file is being used for reporting. Colors can be specified using escape sequences (see [https://misc.flogisoft.com/bash/tip_colors_and_formatting](https://misc.flogisoft.com/bash/tip_colors_and_formatting)).

## Reports
The smarstart option `-r <reportlevel>` allows to print a report that lists all commands specified in the configuration file together with their success statuses. If a command is not run for a certain amount of time (which can be adjusted through the `WARNTIME` and `ERRTIME` variables in the configuration file), it will be flagged as *warning* or *error*. Distinct colors are used in the report to emphasize such commands. For example, to be informed upon each shell start about commands not being run successfully, add this line to [~/.bashrc]() :
```bash
smarstart -r 2
```
As a result, whenever the user starts a new shell, all commands that have not run successfully for the period specified by `WARNTIME` and `ERRTIME`, will be printed.

Similarly, the option `-s` can be used to print a summary information about the number of commands and their statuses.
(Note that the information printed with options `-r` and `-s` filters out duplicate command specifications.)

Report generation may take a few seconds, so a fresh report will only be generated once in a while, and then cached. The options `-r` and `-s` use that cached report unless it is too old.
In particular, when smartstart executes commands, it will generate a report and cache it.
When smartstart is asked to print a report (`-r`) or stats (`-s`), it uses the cached report, unless it is older than the maximum report age, which is 2 hours by default. The maximum report age can be changed using the `-m` option.
The option `-g` allows to force the generation of a new report.


## Time specification
Times can be specified in days (d), hours (d), or minutes (m), by the following syntax: `<integer>[m|h|d]`.

## Options
* `[-c|--conf] <filename>`: use `<filename>` as configuration file instead of [~/.config/smartstart.conf]()
* `[-g|--generate]`: Force report generation. A report is generated automatically each time smartstart executes command lines (i.e., any time other when the options `-r` or `-s` are used).
* `[-h|--help]`: Print help
* `[-m|--max_report_age]`: Set the maximum age of a report (using time specification format above) until it will be regenerated when the options `-r` or `-s` are used. Report generation may take a few seconds, so by default it will only be generated if smartstart executes commands, or if the report is older than the maximum age.
* `[-n|--nocolor]`: Use no color in output.
* `[-r|--report] <reportlevel>`: Outputs a report that lists commands together with their flags (successful, warning, error). `<reportlevel>` is in {1,2,3}. Level 1 means that only commands with flag error are reported, level 2 means that only commands with flags error and warning are reported, and level 3 means that all commands are reported.
* `[-s|--stats]`: Prints stats on the number of commands and their flags.


## Log files
The stderr and stdout outputs of commands run by smartstart will be logged in the directory `~/.smartstart/log/` in files with names of the form `<mdfile>.log` (for stdout) and `<mdfile>.err` (for stderr). The prefix `<mdfile>` is the md5sum of the corresponding command. It will be printed together with the command, when smarstart is called and the command is executed, and also as part of the report (option `-r`).

Since logfiles can become big, it is recommended to use `logrotate` for managing them.
A default logrotate configuration file [logrotate.conf]() is provided.
Simply copy that file into the directory [~/.smartstart/]() and add the following line to crontab:
```
@daily /usr/sbin/logrotate -s ~/.smartstart/logrotate.state ~/.smartstart/logrotate.conf
```
