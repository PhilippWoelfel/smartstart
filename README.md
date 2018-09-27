# smartstart
Bash script to start periodic jobs based on X idle time

## Usage:

```bash
smartstart.sh <options> <delta time> <idle time> <command>
```

delta and idle time are in the format `<integer>[m|h|d]`

Runs `<command>`, if the XWindow system was idle for at least `<idle time>` *and* `<command>` was last run at least `<delta time>` ago.

Several reports can be obtained by using options `--warnings`, `--report`, or `--color-report`.

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
