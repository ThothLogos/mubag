#!/bin/bash

# TODO: Complete --edit/-e functionality using extract/update functionality
# TODO: Trap CTRL-C to attempt cleanups there as well
# TODO: (?) Perhaps offer option to bail out of rm'ing and let them handle secure deletion manually?
# TODO: What happens when when --print or edit a non-ASCII file? :) Can we detect that early?
# TODO: Experiment: pretty sure I have some redundant RST's on the color tags, prob works like NM
# TODO: Expand --examples, new flags etc
# TODO: --output should check for existing
# TODO: When replacing or updating, can unzip -l | grep | awk to compare date and hashes

source config.sh

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE] ( -o [NEW BACKUP] || -b [EXISTING BACKUP] )

 * ${YL}${BD}NOTICE${RS}: All options will decrypt and unpack the archive temporarily. The
           decrypted data is exposed on the filesystem for a short amount of
           time while operations execute. Attempts are made to use secure file
           removal tools like 'srm' and 'shred', but 'rm' is used for cleanup
           tasks in the event of these tools not being available.

OPTIONS:

  -h, --help                    This screen
  -ex, --examples               Print examples of usage
  -v, --verbose                 Increase output to assist in debugging

  -b FILE, --backup FILE        Specify existing encrypted archive to use
  -o FILE, --out FILE           Specify dir/name of output file for new archive

  -l, --list                    List contents of existing backup archive, repack
  -d, --decrypt                 Decrypt existing backup archive

  -a FILE, --add FILE           Add FILE to archive (or create a new one)
  -p FILE, --print FILE         Print contents of FILE to STDOUT, repack
  -e FILE, --edit FILE          Open FILE in $EDITOR for modification, repack
  -x FILE, --extract FILE       Extract a specific FILE from existing archive
  -u FILE, --update FILE        Update a specific FILE within existing archive
                                  (ie, overwrite keys.txt with a new version)
  -r FILE, --remove FILE        Remove a file from an existing archive

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

if [ "$#" -lt 1 ] || [ "$#" -gt 5 ]; then
  echo "${RD}${BD}ERROR${RS}: incorrect number of args"
  display_usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) display_usage; exit 0;;
    -ex|--examples) display_examples; exit 0;;
    -v|--verbose) verbose=true; shift 1;; 

    -b|--backup) backup=true; if [ $# -gt 1 ];then BACKUP="$2";shift 2
              else echo "${RD}${BD}ERROR${RS}: --backup missing FILE!";exit 1;fi;;
    -o|--out) out=true; if [ $# -gt 1 ];then OUTFILE="$2";shift 2
              else echo "${RD}${BD}ERROR${RS}: --out missing FILE!";exit 1;fi;;

    -l|--list) list=true; shift 1;;
    -d|--decrypt) decrypt=true; shift 1;;

    -a|--add) add=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else echo "${RD}${BD}ERROR${RS}: --add missing FILE!";exit 1;fi;;
    -p|--print) prnt=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else echo "${RD}${BD}ERROR${RS}: --print missing FILE!";exit 1;fi;;
    -x|--extract) extract=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else echo "${RD}${BD}ERROR${RS}: --extract missing FILE!";exit 1;fi;;
    -e|--edit) edit=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else echo "${RD}${BD}ERROR${RS}: --edit missing FILE!";exit 1;fi;;
    -u|--update) update=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else echo "${RD}${BD}ERROR${RS}: --update missing FILE!";exit 1;fi;;
    -r|--remove) remove=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else echo "${RD}${BD}ERROR${RS}: --remove missing FILE!";exit 1;fi;;

    --backup=*) backup=true; BACKUP="${1#*=}"; shift 1;;
    --out=*) out=true; OUTFILE="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --print=*) prnt=true; FILE="${1#*=}"; shift 1;;
    --extract=*) extract=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --update=*) update=true; FILE="${1#*=}"; shift 1;;
    --remove=*) remove=true; FILE="${1#*=}"; shift 1;;
    
    -*) echo -e "${RD}${BD}ERROR${RS}: unknown option $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done

if [ $backup ];then
  if ! [ -f $BACKUP ];then
    echo "${RD}${BD}ERROR${RS}: The --backup FILE you specified cannot be found"
    exit 1
  elif ! [[ $BACKUP == *.gpg ]];then
    echo "${RD}${BD}ERROR${RS}: Please specify a --backup FILE that ends in .gpg"
    exit 1
  fi
elif ! [ $backup ] && [[ $decrypt||$list||$prnt||$extract||$update||$edit||$remove ]];then
  echo "${RD}${BD}ERROR${RS}: Cannot complete this operation without --backup specified!"
  exit 1
fi

if [[ $add || $update ]] && [[ ! $FILE || ! -f $FILE ]];then
  echo "${RD}${BD}ERROR${RS}: The file targeted for add/update ($FILE) not found!"
  exit 1
fi

main() {
  if [[ $list||$prnt||$extract||$update||$edit||$remove ]] || [[ $add && $backup ]];then
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
  fi
  if [ $add ] && ! [ $backup ]; then # create new archive
    if ! [ $out ];then
      echo "${RD}${BD}ERROR${RS}: --add requires either --backup FILE or --out FILE specified," \
        "if you're trying to update an existing backup use -b/--backup, if you're trying to start" \
        "a new backup, use -o/--out to specify the output file's name and location.";exit 1
    else
      create_or_update_archive $FILE $OUTFILE
      encrypt_zip $OUTFILE
      secure_remove_file $OUTFILE
    fi
  elif [ $add ] && [ $backup ];then # update existing archive
    if [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
      secure_remove_file $BACKUP
      echo "${RD}${BD}ERROR${RS}: File $FILE already exists inside $BACKUP.gpg, if you want to" \
        "update the existing copy inside the archive, use --update.";exit 1
    fi
    create_or_update_archive $FILE $BACKUP
  elif [ $decrypt ];then
    decrypt_zip $BACKUP
    if [[ $? -eq 0 ]];then
      echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS}: You have just decrypted your backup archive" \
        "and it is exposed on the file system. Please be aware of the risks!"
    fi
  elif [ $update ];then
    if ! [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
      secure_remove_file $BACKUP
      echo "${RD}${BD}ERROR${RS}: $FILE not found in $BACKUP.gpg, can't --update. If you wanted" \
        "to add that file instead try: $(basename $0) --add $FILE --backup $BACKUP";exit 1
    fi
    create_or_update_archive $FILE $BACKUP
  elif [ $prnt ];then print_file_from_archive $FILE $BACKUP
  elif [ $list ];then list_archive_contents $BACKUP
  elif [ $extract ];then extract_file_from_archive $FILE $BACKUP
  elif [ $edit ];then edit_file_from_archive $FILE $BACKUP
  elif [ $remove ];then remove_file_from_archive $FILE $BACKUP
  fi
  if [[ $update||$edit||$remove ]] || [[ $add && $backup ]]; then encrypt_zip $BACKUP;fi
  if [[ $backup && -f $BACKUP && ! $decrypt ]];then secure_remove_file $BACKUP;fi
}

remove_file_from_archive() {
  [ $verbose ] && echo "${RD}REMOVE${RS}: Attempting to remove $FILE from $2"
  local unencrypted_zip=$2
  zip --delete $unencrypted_zip $FILE # this asked for overwrite
  if ! [[ $? -eq 0 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${RD}REMOVE ${BD}ERROR${RS}: File $FILE not found within $unencrypted_zip, aborting"
    exit 1
  else
    echo "${RD}REMOVE${RS}: ${GN}Success${RS}, $FILE removed from archive"
  fi
}

check_file_existence() {
  local unencrypted_zip=$2
  unzip -v $unencrypted_zip | grep $(basename $FILE) >/dev/null
  if [[ $? -eq 0 ]];then
    echo 0
  else
    echo 1
  fi
}

extract_file_from_archive() {
  [ $verbose ] && echo "${CY}EXTRACT${RS}: Attempting to extract $FILE from $2"
  local unencrypted_zip=$2
  unzip -j $unencrypted_zip $FILE
  if ! [[ $? -eq 0 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${CY}EXTRACT ${RD}${BD}ERROR${RS}: File $FILE not found within $unencrypted_zip, aborting"
    exit 1
  else
    echo "${CY}EXTRACT${RS}: ${GN}Success${RS}, $FILE recovered from archive $unencrypted_zip"
  fi
}

create_or_update_archive() {
  local unencrypted_zip=$2
  if [ $out ];then
    if [[ $OUTFILE == "" || -d $OUTFILE ]];then
      if [ -d $OUTFILE ] && ! [ $OUTFILE == */ ];then OUTFILE="$OUTFILE/";fi
      unencrypted_zip="${OUTFILE}${DATE}.zip"
      OUTFILE="${OUTFILE}${DATE}.zip"
    fi
    echo "${GN}${BD}ADD${RS}: --out was blank or resolves to a directory, defaulting to datestamp" \
      "for filename: $OUTFILE"
  fi
  if [ $OUTFILE ] && [ -f $OUTFILE ];then
    echo "${RD}${BD}ERROR${RS}: --out $OUTFILE would over-write an existing file! If you want to" \
      "update an existing backup, use --backup instead of --out. Otherwise, pick a different file" \
      "location/name or remove the blocking file manually and re-run. Oopsie prevention."
    exit 1
  fi
  zip -urj $unencrypted_zip $FILE # -rj abandon directory structure of files added
  if [[ $? -eq 0 ]];then
    [ $verbose ] && echo "${GN}${BD}ADD${RS}: ${GN}Success${RS}, archive creation/update complete"
  elif [[ $? -eq 12 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${GN}${BD}UPDATE ${YL}NO-OP${RS}: zip update failed 'nothing to do'?"
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${GN}${BD}UPDATE ${RD}ERROR${RS}: unknown zip creation or update error!"
  fi
}

print_file_from_archive() {
  [ $verbose ] && echo "${WH}${BD}PRINT${RS}: routing $FILE to STDOUT from ${BACKUP%????}"
  if ! [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
    echo "${RD}${BD}ERROR${RS}: $FILE not found in $BACKUP.gpg, can't --print!";exit 1
  fi
  echo "${WH}${BD}--- BEGIN OUTPUT ---${RS}"
  unzip -p ${BACKUP%????} $(basename $FILE)
  echo "${WH}${BD}---  END OUTPUT  ---${RS}"
}

list_archive_contents() {
  unzip -v $1
  if ! [[ $? -eq 0 ]];then
    echo "${RD}${BD}ERROR${RS}: unknown unzip error during --list!"
  fi
}

edit_file_from_archive() {
  local unencrypted_zip=$2
  if ! [[ $(check_file_existence $FILE $unencrypted_zip) ]];then
    echo "${RD}${BD}ERROR${RS}: --edit failed, $FILE doesn't exist in the archive!"
    exit 1
  fi
  extract_file_from_archive $FILE $unencrypted_zip
  if command -v $EDITOR >/dev/null;then
    [ $verbose ] && echo "${MG}${BD}EDIT${RS}: Attempting to launch editor: $EDITOR"
    $EDITOR $FILE
  else
    echo "${MG}${BD}EDIT${RS}: Couldn't find editor \"$EDITOR\", launching with nano"
    EDITOR=nano
    $EDITOR $FILE
  fi
  if [[ $? -eq 0 ]];then
    # check_file_changed() conditional ?
    create_or_update_archive $FILE $unencrypted_zip
  else
    echo "${RD}${BD}ERROR${RS}: Editor \"$EDITOR\" exited with a non-zero status ($?)! Cleaning up exposed files."
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    if [ -f $FILE ];then secure_remove_file $FILE;fi
    exit 1
  fi
  if [ -f $FILE ];then secure_remove_file $FILE;fi
}

get_file_modified_unix() {
  
}

decrypt_zip() {
  [ $verbose ] && echo "${CY}${BD}DECRYPT${RS}: Attempting gpg decrypt"
  local unencrypted_zip=${1%????}
  gpg -q --no-symkey-cache -o $unencrypted_zip --decrypt $1
  if [[ $? -eq 0 ]]; then
    echo "${CY}${BD}DECRYPT${RS}: ${GN}Success${RS}, $unencrypted_zip has been restored"
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${CY}${BD}DECRYPT ${RD}${BD}FAIL${RS}: gpg decryption error. Exiting."
    exit 1
  fi
}

encrypt_zip() {
  [ $verbose ] && echo "${BL}${BD}ENCRYPT${RS}: Attempting gpg encrypt"
  local unencrypted_zip=$1
  if [[ $add || $update || $remove || $edit ]];then
    # --yes during add/update, user is explicitly running a write command already
    gpg -q --yes --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  else # in other situations we may want to confirm over-writing if it crops up
    gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  fi
  if [[ $? -eq 0 ]];then
    echo "${BL}${BD}ENCRYPT${RS}: ${GN}Success${RS}, $unencrypted_zip.gpg protected by $ALGO"
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${BL}${BD}ENCRYPT ${RD}ERROR${RS}: gpg encryption error! Exiting."
    exit 1
  fi
}

secure_remove_file() {
  local secure_removal_cmd=""
  if command -v srm >/dev/null;then
    secure_removal_cmd="srm -zv $1"
  elif command -v shred >/dev/null;then
    secure_removal_cmd="shred -uz $1"
  fi
  if ! [[ secure_removal_cmd == "" ]];then
    $secure_removal_cmd
    if [[ $? -eq 0 ]];then echo "${YL}CLEANUP${RS}: ${GN}Success${RS}, $1 purged securely via: $secure_removal_cmd";fi
  else
    echo "${YL}CLEANUP${RS}: Secure file removal not found on system, resorting to using rm"
    unsecure_remove_file $1
  fi

}

unsecure_remove_file() {
  rm -f $1
  if [[ $? -eq 0 ]]; then
    echo "${YL}CLEANUP${RS}: rm of $1 complete - ${RD}${BD}WARNING${RS} decrypted" \
      "archive may still be recoverable!"
  else
    echo "${YL}CLEANUP ${RD}${BD}FAIL${RS}: File removal with rm failed!"
    exit 1
  fi
}

main
exit 0
