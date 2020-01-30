#!/bin/bash

source config.sh

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE]

 * NOTICE: All options can decrypt and unpack the archive temporarily. The
           decrypted data is exposed temporarily on the filesystem for a short
           amount of time while operations execute.

 * Any time files are cleaned up, we attempt to use \\'shred\\' to ensure no recovery.  
 * Limited to one OPTION per execution, select which operation to run


OPTIONS:\n
  -a, --add=FILE               Add FILE to archive, repack
  -o, --out=FILE               Print contents of FILE to STDOUT, repack
  -e, --edit=FILE              Open FILE in $EDITOR for modification, repack
"
}

if [[ "$#" -lt 1 ]]; then
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

    --existing-backup=*) existing=true; EXISTING="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --out=*) out=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --add|--out|--edit) echo "error: $1 requires an equal sign, ex: $1=FILE" >&2; exit 1;;
    
    -*) echo "unknown option: $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done


main() {
  if [[ $add ]] && [[ -f $FILE ]];then
    echo "ADD BEGIN: $FILE"
    if [[ $EXISTING ]] && [[ -f $EXISTING ]]; then
      echo "ADD: backup already exists at $EXISTING - decrypting"
      decrypt_zip
      create_or_update_zip
      encrypt_zip
      remove_zip
    elif [[ -f $ZIPLOC.gpg ]]; then
      echo 'ADD ERROR: file $ZIPLOC.gpg exists but --existing-backup= is not set, please' \
        're-run with this option to confirm updating the existing file. If you intended to' \
        'create a new archive, please change the ZIPNAME in config.sh to something unique.' \
        'This check is to prevent accidental over-writing of a previously encrypted archive.' \
        'Exiting.'
      exit 1
    else
      echo "ADD: existing backup not found - creating new archive at $ZIPLOC"
      create_or_update_zip
      encrypt_zip
      remove_zip
    fi
  elif [[ $out ]];then
    echo "Out true, FILE $FILE"
  elif [[ $edit ]];then
    echo "Edit true, FILE $FILE"
  else
    echo "ADD FAIL: $FILE not found! Exiting."
    exit 1
  fi
}

remove_zip() {
  # check for presence of secure file removal tools, prioritize over simple rm
  if command -v shred >/dev/null; then
    echo "CLEANUP: shred exists on system, shredding old zip"
    shred -uvz $ZIPLOC # -u delete file, -v verbose, -z zero out before deletion
    if [[ $? -eq 0 ]]; then
      echo "CLEANUP: success, shred complete"
    else
      echo "CLEANUP FAIL: shred failed!"
      exit 1
    fi
  else
    echo "CLEANUP: advanced file erasure not found, resorting to rm"
    rm $ZIPLOC
    if [[ $? -eq 0 ]]; then
      echo "CLEANUP: success, rm of zip complete"
    else
      echo "CLEANUP FAIL: rm failed!"
      exit 1
    fi
  fi
}

create_or_update_zip() {
  zip -u -r -j $ZIPLOC $FILE # -u update, -j ignores directory structure of $FILE
  if [[ $? -eq 0 ]]; then
    echo "ADD: create/update successful"
  else
    echo "ADD FAIL: unzip error! Exiting."
    exit 1
  fi
}

encrypt_zip() {
  gpg --no-symkey-cache --cipher-algo $ALGO --symmetric $ZIPLOC
  if [[ $? -eq 0 ]]; then
    echo "ENCRYPT: successful"
  else
    echo "ENCRYPT FAIL: gpg encryption error. Exiting,"
    exit 1
  fi
}

decrypt_zip() {
  gpg --no-symkey-cache -o $ZIPLOC --decrypt $ZIPLOC.gpg
  if [[ $? -eq 0 ]]; then
    echo "ENCRYPT: successful"
  else
    echo "ENCRYPT FAIL: gpg encryption error. Exiting,"
    exit 1
  fi
}

main
exit 0