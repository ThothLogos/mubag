#!/bin/bash

EDITOR="nano"
ZIP=""
ALGO=""

source config.sh

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE]

 * Limited to one OPTION per execution, select which operation to run
 * Beware, all options decrypt and unpack the archive temporarily

OPTIONS:\n
  -a, --add=FILE               Add FILE to archive, repack
  -o, --out=FILE               Print contents of FILE to STDOUT, repack
  -e, --edit=FILE              Open FILE in $EDITOR for modification, repack
"
}

if [[ "$#" -lt 1 ]] || [[ "$#" -ge 3 ]]; then
  echo "error: incorrect number of args"
  display_usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help) display_usage; exit 0;;

    -a) add=true; FILE="$2"; shift 2;;
    -o) out=true; FILE="$2"; shift 2;;
    -e) edit=true; FILE="$2"; shift 2;;

    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --out=*) out=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --add|--out|--edit) echo "error: $1 requires an equal sign, ex: $1=FILE" >&2; exit 1;;

    -*) echo "unknown option: $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done

if [[ $add ]];then
    echo "add - $FILE"
  if [[ $ZIP ]]; then
    echo "zip exists at $ZIP - unpacking"
  else
    echo "zip empty - creating new archive"
  fi
fi

if [[ $out ]];then
  echo "Out true, FILE $FILE"
fi

if [[ $edit ]];then
  echo "Edit true, FILE $FILE"
fi