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


## Usage:

```bash
smartstart.sh <options>
```

Reads the configuration file (default [$HOME/.config/smartstart.conf]()), and processes the commands specified therein.



Runs `<command>`, if the XWindow system was idle for at least `<idle time>` *and* `<command>` was last run at least `<delta time>` ago.

Several reports can be obtained by using options `--warnings`, `--report`, or `--color-report`.

## Time specification
Time will be specified in days (d), hours (d), or minutes (m), by the following syntax: `<integer>[m|h|d]`

## Configuration file:
Each line is of one of following types:

### Comment Lines
Indicated by  leading `#`. Comment lines are ignored

### Command specification lines
Of the form

```
  <delta time> <idle time> <command>
```

where `delta time` and `idle time` must be valid time specifications.

`<command>` will be executed, if it was not run successfully for `<delta time>`, and the X system has been idle for at least `<idle time>`

### Variable configurations
A line of the form `<variable>=<value>`
This sets the variable to the given value.
Currently, the following variables are recognized:

* `WARNTIME`: Reports flag each command in the following command specification lines as *warning*, if the command was not run for the time specified.
* `ERRTIME`: Reports flag each command in the following command specification lines as *error*, if the command was not run for the time specified.



## Requirements:
* ansi-color: https://code.google.com/p/ansi-color/
* xprintidle: https://github.com/g0hl1n/xprintidle (executable`xprintidle` must be in $PATH.
* md5sum
