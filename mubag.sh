#!/bin/bash

EDITOR="nano"

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE]

 * Limited to one OPTION per execution, select which operation to run
 * Beware, all options decrypt and unpack the archive temporarily

OPTIONS:\n
  -a, --add FILE               Add FILE to archive, repack
  -o, --out FILE               Print contents of FILE to STDOUT, repack
  -e, --edit FILE              Open FILE in $EDITOR for modification, repack
"
}

if [[ "$#" -le 1 ]] || [[ "$#" -ge 3 ]]; then
    display_usage
    exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -a) add=true; FILE="$2"; shift 2;;
    -o) out=true; FILE="$2"; shift 2;;
    -e) edit=true; FILE="$2"; shift 2;;

    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --out=*) out=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --add|--out|--edit) echo "$1 requires an argument" >&2; exit 1;;

    -*) echo "unknown option: $1" >&2; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done