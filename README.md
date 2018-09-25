# smartstart
Bash script to start periodic jobs based on X idle time

## Usage:

```bash
smartstart.sh <options> <delta time> <idle time> <command>
```

delta and idle time are in the format `<integer>[m|h|d]`

Runs `<command>`, if the XWindow system was idle for at least `<idle time>` *and* `<command>` was last run at least `<delta time>` ago.

Several reports can be obtained by using options `--warnings`, `--report`, or `--color-report`.

## Requirements:
* ansi-color: https://code.google.com/p/ansi-color/
* xprintidle: https://github.com/g0hl1n/xprintidle (executable`xprintidle` must be in $PATH.
