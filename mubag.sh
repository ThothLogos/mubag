#!/bin/bash

# TODO: Complete --edit/-e functionality
# TODO: Trap CTRL-C to attempt cleanups there as well
# TODO: (?) Perhaps offer option to bail out of rm'ing and let them handle secure deletion manually?
# TODO: What happens when when --out a non-ASCII file? :) Can we detect that early?
# TODO: Change ZIPNAME to use a prompt, we only really need it for --add creation

source config.sh

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE] ( -o [OUTFILE NAME] || -b [EXISTING BACKUP ARCHIVE] )

 * ${YEL}$(tput bold)NOTICE${RST}: All options will decrypt and unpack the archive temporarily. The
           decrypted data is exposed on the filesystem for a short amount of
           time while operations execute. Attempts are made to use secure file
           removal tools like 'srm' and 'shred', but 'rm' is used for cleanup
           tasks in the event of these tools not being available.

OPTIONS:

  -o FILE, --out=FILE           Specify name of output file
  -d DIR,  --dir=DIR            Specify a directory to send the --out FILE
                                  (default: local to $(basename $0))
  -b FILE, --backup=FILE        Specify existing encrypted archive to use

  -l, --list                    List contents of backup archive, repack
  -a FILE, --add=FILE           Add FILE to archive (or create a new one)
  -p FILE, --print=FILE         Print contents of FILE to STDOUT, repack
  -e FILE, --edit=FILE          Open FILE in $EDITOR for modification, repack

  -v, --verbose                 Increase output to assist in debugging
  -ex, --examples               Print examples of usage
  -h, --help                    This screen
"
}

display_examples() {
  echo "
EXAMPLES:

  Create a new encrypted archive, use any file:

    $(basename $0) --add=backup.txt
    $(basename $0) -a dirtypic.png

  List contents of existing encrypted archive:

    $(basename $0) --list --backup=/home/user/backup.zip.gpg
    $(basename $0) -l -b /home/user/backup.zip.gpg

  Add new file to existing encrypted archive:

    $(basename $0) --add=qr_code.jpg --backup=/home/user/backup.zip.gpg
    $(basename $0) -a latest.log -b /home/user/backup.zip.gpg

  Print contents of file inside an encrypted archive to STDOUT:

    $(basename $0) --print secrets.txt -b /home/user/backup.zip.gpg
    $(basename $0) -p recovery_key --backup=/home/user/backup.zip.gpg

  Edit existing file inside an encrypted archive:

    $(basename $0) --edit 2fa.bak -b /home/user/backup.zip.gpg
    $(basename $0) -e rosebud.conf --backup=/home/user/backup.zip.gpg
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
    -ex|--examples) display_examples; exit 0;;
    -v|--verbose) verbose=true; shift 1;; 

    -b|--backup) BACKUP="$2"; shift 2;;

    -l|--list) list=true; shift 1;;
    -a|--add) add=true; FILE="$2"; shift 2;;
    -p|--print) prnt=true; FILE="$2"; shift 2;;
    -e|--edit) edit=true; FILE="$2"; shift 2;;
    -o|--out) out=true; OUTFILE="$2"; shift 2;;

    --backup=*) BACKUP="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --print=*) prnt=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --out=*) out=true; OUTFILE="${1#*=}"; shift 1;;
    
    -*) echo -e "${RED}$(tput bold)ERROR${RST}: unknown option $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done

main() {
  if [[ $list ]]; then
    [[ $verbose ]] && echo "${BLU}$(tput bold)LIST${RST} BEGIN: $(basename $FILE)"
    decrypt_zip
    list_archive_contents
    secure_remove_file $ZIPLOC
  elif [[ $add ]] && [[ -f $FILE ]];then
    [[ $verbose ]] && echo "${GRN}$(tput bold)ADD${RST} BEGIN: $FILE"
    if [[ $BACKUP ]] && [[ -f $BACKUP ]]; then
      [[ $verbose ]] && echo "${GRN}$(tput bold)ADD${RST}: backup already exists at $BACKUP - decrypting"
      decrypt_zip
      create_or_update_zip
      encrypt_zip
      secure_remove_file $ZIPLOC
    elif [[ -f $ZIPLOC.gpg ]]; then
      echo "${RED}$(tput bold)ERROR${RST}: file $ZIPLOC.gpg exists but --backup= is not set," \
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
  elif [[ $prnt ]];then
    [[ $verbose ]] && echo "${MAG}$(tput bold)PRINT${RST} BEGIN: $FILE"
    if [[ $BACKUP ]] && [[ -f $BACKUP ]]; then
      [[ $verbose ]] && echo "${MAG}$(tput bold)PRINT${RST}: backup already exists at $BACKUP - decrypting"
      decrypt_zip
      print_requested_file_from_archive
      secure_remove_file $ZIPLOC
    else
      echo "${MAG}$(tput bold)PRINT${RST} ${RED}$(tput bold)FAIL${RST}: --backup= either not set or" \
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

list_archive_contents() {
  if ! [[ $BACKUP ]] || ! [[ -f $BACKUP ]]; then
    echo "${RED}$(tput bold)ERROR${RST}: must set -b/--backup= !"
  fi
  unzip -l ${BACKUP%????}
}

print_requested_file_from_archive() {
  [[ $verbose ]] && echo "${MAG}$(tput bold)PRINT${RST}: routing $FILE to STDPRINT from ${BACKUP%????}"
  echo "${WHT}$(tput bold)--- BEGIN OUTPUT ---${RST}"
  unzip -p ${BACKUP%????} $(basename $FILE)
  echo "${WHT}$(tput bold)---  END OUTPUT  ---${RST}"
}

secure_remove_file() {
  if command -v srm >/dev/null; then
    [[ $verbose ]] && echo "${YEL}$(tput bold)CLEANUP${RST}: srm exists on system, target $1"
    srm -zv $1 # -z zero-out, -v verbose (srm can be slow, shows progress)
    if [[ $? -eq 0 ]]; then
      echo "${YEL}$(tput bold)CLEANUP${RST}: success, srm of $1 complete - decrypted archive is securely purged"
    else
      echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}$(tput bold)FAIL${RST}: srm failed!"
      unsecure_remove_file $1
      exit 1
    fi
  elif command -v shred >/dev/null; then # prioritize secure removal over simple rm, if avail
    [[ $verbose ]] && echo "${YEL}$(tput bold)CLEANUP${RST}: shred exists on system, shredding $1"
    shred -uz $1 # -u delete file, -z zero-out
    if [[ $? -eq 0 ]]; then
      echo "${YEL}$(tput bold)CLEANUP${RST}: success, shred of $1 complete - decrypted archive is securely purged"
    else
      echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}$(tput bold)FAIL${RST}: shred failed!"
      unsecure_remove_file $1
      exit 1
    fi
  else # resort to rm'ing
    echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}FALLBACK${RST}: secure file erasure not found, resorting to rm"
    unsecure_remove_file $1
  fi
}

unsecure_remove_file() {
  rm -f $1
  if [[ $? -eq 0 ]]; then
    echo "${YEL}$(tput bold)CLEANUP${RST}: rm of $1 complete - ${RED}$(tput bold)WARNING${RST} decrypted" \
      "archive may still be recoverable!"
  else
    echo "${YEL}$(tput bold)CLEANUP${RST} ${RED}$(tput bold)FAIL${RST}: rm failed!"
    # TODO: what else can be done, just warn harder? why might this fail?
    exit 1
  fi
}

create_or_update_zip() {
  if [[ $BACKUP ]]; then # check for potential duplicate file
    unzip -l $ZIPLOC | grep -q $(basename $FILE)
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
    echo "${GRN}$(tput bold)ADD${RST} ${YEL}$(tput bold)NO-OP${RST}: zip update failed 'nothing to do'?"
    if [[ -f $ZIPLOC ]]; then secure_remove_file $ZIPLOC; fi
    exit 1
  else
    echo "${GRN}$(tput bold)ADD${RST} ${RED}$(tput bold)FAIL${RST}: unknown zip creation or update error! Exiting."
    if [[ -f $ZIPLOC ]]; then secure_remove_file $ZIPLOC; fi
    exit 1
  fi
}

decrypt_zip() {
  gpg -q --no-symkey-cache -o ${BACKUP%????} --decrypt $BACKUP
  if [[ $? -eq 0 ]]; then
    echo "$(tput bold)${CYN}DECRYPT${RST}: successful"
  else
    echo "$(tput bold)${CYN}DECRYPT${RST} ${RED}$(tput bold)FAIL${RST}: gpg decryption error. Exiting,"
    if [[ -f $ZIPLOC ]]; then secure_remove_file $ZIPLOC; fi
    exit 1
  fi
}

encrypt_zip() {
  gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $ZIPLOC
  if [[ $? -eq 0 ]]; then
    echo "$(tput bold)${BLU}ENCRYPT${RST}: successful"
  else
    echo "$(tput bold)${BLU}ENCRYPT${RST} ${RED}$(tput bold)FAIL${RST}: gpg encryption error. Exiting,"
    if [[ -f $ZIPLOC ]]; then secure_remove_file $ZIPLOC; fi
    exit 1
  fi
}

main
exit 0
