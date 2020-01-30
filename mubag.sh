#!/bin/bash

# TODO: Complete --edit/-e functionality
# TODO: Verify all early exits don't leave a zip behind.
# TODO: Trap CTRL-C to attempt cleanups there as well

source config.sh

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE]

 * ${RED}$(tput bold)NOTICE${RST}: All options can decrypt and unpack the archive temporarily. The
           decrypted data is exposed temporarily on the filesystem for a short
           amount of time while operations execute.

 * Any time files are cleaned up, we attempt to use \\'shred\\' to ensure no recovery.  
 * Limited to one OPTION per execution, select which operation to run


OPTIONS:\n
  -b, --existing-backup=FILE      Specify an existing encrypted archive to update
  -a, --add=FILE                  Add FILE to archive, repack
  -o, --out=FILE                  Print contents of FILE to STDOUT, repack
  -e, --edit=FILE                 Open FILE in $EDITOR for modification, repack
"
}

if [[ "$#" -lt 1 ]]; then
  echo "${RED}$(tput bold)ERROR${RST}: incorrect number of args"
  display_usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) display_usage; exit 0;;
    -v|--verbose) verbose=true; shift 1;; 

    -b) existing=true; EXISTING="$2"; shift 2;;
    -a) add=true; FILE="$2"; shift 2;;
    -o) out=true; FILE="$2"; shift 2;;
    -e) edit=true; FILE="$2"; shift 2;;

    --existing-backup=*) existing=true; EXISTING="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --out=*) out=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --add|--out|--edit) echo -e "${RED}$(tput bold)ERROR${RST}: $1 requires an equal sign, ex: $1=FILE" >&2; exit 1;;
    
    -*) echo -e "${RED}$(tput bold)ERROR${RST}: unknown option $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done

main() {
  if [[ $add ]] && [[ -f $FILE ]];then
    [[ $verbose ]] && echo "${GRN}$(tput bold)ADD${RST} BEGIN: $FILE"
    if [[ $EXISTING ]] && [[ -f $EXISTING ]]; then
      [[ $verbose ]] && echo "${GRN}$(tput bold)ADD${RST}: backup already exists at $EXISTING - decrypting"
      decrypt_zip
      create_or_update_zip
      encrypt_zip
      secure_remove_file $ZIPLOC
    elif [[ -f $ZIPLOC.gpg ]]; then
      echo "${RED}$(tput bold)ERROR${RST}: file $ZIPLOC.gpg exists but --existing-backup= is not set," \
        "please re-run with this option to confirm updating the existing file. If you intended to create" \
        "a new archive, please change the ZIPNAME in config.sh to something unique. This check is to" \
        "prevent accidental over-writing of a previously encrypted archive. Exiting."
      exit 1
    else
      [[ $verbose ]] && echo "${GRN}$(tput bold)ADD${RST}: existing backup not found - creating new archive at $ZIPLOC"
      create_or_update_zip
      encrypt_zip
      secure_remove_file $ZIPLOC
    fi
  elif [[ $out ]];then
    [[ $verbose ]] && echo "${MAG}$(tput bold)OUT${RST} BEGIN: $FILE"
    if [[ $EXISTING ]] && [[ -f $EXISTING ]]; then
      [[ $verbose ]] && echo "${MAG}$(tput bold)OUT${RST}: backup already exists at $EXISTING - decrypting"
      decrypt_zip
      output_requested_file_from_archive
      secure_remove_file $ZIPLOC
    else
      echo "${MAG}$(tput bold)OUT${RST} ${RED}$(tput bold)FAIL${RST}: --existing-backup= either not set or" \
      "the backup was not found. Please check and re-try. Exiting."
      exit 1
    fi
  elif [[ $edit ]];then
    echo "Edit true, FILE $FILE"
  else
    echo "${RED}$(tput bold)ERROR${RST}: $FILE not found! Exiting."
    exit 1
  fi
}

output_requested_file_from_archive() {
  [[ $verbose ]] && echo "${MAG}$(tput bold)OUT${RST}: routing $FILE to STDOUT from ${EXISTING%????}"
  echo "${WHT}$(tput bold)--- BEGIN OUTPUT ---${RST}"
  unzip -p ${EXISTING%????} $FILE
  echo "${WHT}$(tput bold)---  END OUTPUT  ---${RST}"
}

secure_remove_file() {
  if command -v shred >/dev/null; then # prioritize secure removal over simple rm, if avail
    [[ $verbose ]] && echo "${YEL}$(tput bold)CLEANUP${RST}: shred exists on system, shredding $1"
    shred -uz $1 # -u delete file, -v verbose, -z zero-out before deletion
    if [[ $? -eq 0 ]]; then
      echo "${YEL}$(tput bold)CLEANUP${RST}: success, shred of $1 complete - decrypted archive is securely purged"
    else
      echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}$(tput bold)FAIL${RST}:: shred failed!"
      # TODO: fallback rm if shred really did fail
      exit 1
    fi
  else
    echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}FALLBACK${RST}: secure file erasure shred not found, resorting to rm"
    rm $1
    if [[ $? -eq 0 ]]; then
      echo "${YEL}$(tput bold)CLEANUP${RST}: success, rm of $1 complete - decrypted archive may be recoverable!"
    else
      echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}$(tput bold)FAIL${RST}: rm failed!"
      exit 1
    fi
  fi
}

create_or_update_zip() {
  if [[ $EXISTING ]]; then # check for potential duplicate file
    local filename=$(basename $FILE)
    unzip -l $ZIPLOC | grep -q $filename
    if [[ $? -eq 0 ]]; then
      echo "${RED}$(tput bold)ERROR${RST}: Unable to add $FILE to $ZIPLOC, filename already exists in the archive."
      secure_remove_file $ZIPLOC
      exit 1
    fi
  fi
  zip -u -r -j $ZIPLOC $FILE # -u update zip (if it exists), -j ignores dir structure of $FILE
  if [[ $? -eq 0 ]]; then
    echo "${GRN}$(tput bold)ADD${RST}: archive creation/update successful"
  elif [[ $? -eq 12 ]]; then
    echo "${GRN}$(tput bold)ADD${RST} ${YEL}$(tput bold)NO-OP${RST}:: zip update failed 'nothing to do'?"
  else
    echo "${GRN}$(tput bold)ADD${RST} ${RED}$(tput bold)FAIL${RST}:: unknown zip creation or update error! Exiting."
    if [[ -f $ZIPLOC ]]; then secure_remove_file $ZIPLOC; fi
    exit 1
  fi
}

decrypt_zip() {
  gpg -q --no-symkey-cache -o ${EXISTING%????} --decrypt $EXISTING
  if [[ $? -eq 0 ]]; then
    echo "$(tput bold)${CYN}DECRYPT${RST}: successful"
  else
    echo "$(tput bold)${CYN}DECRYPT${RST} ${RED}$(tput bold)FAIL${RST}:: gpg decryption error. Exiting,"
    exit 1
  fi
}

encrypt_zip() {
  gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $ZIPLOC
  if [[ $? -eq 0 ]]; then
    echo "$(tput bold)${BLU}ENCRYPT${RST}: successful"
  else
    echo "$(tput bold)${BLU}ENCRYPT${RST} ${RED}$(tput bold)FAIL${RST}:: gpg encryption error. Exiting,"
    exit 1
  fi
}

main
exit 0
