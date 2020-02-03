#!/bin/bash

# TODO: Trap CTRL-C to attempt cleanups there as well
# TODO: (?) Perhaps offer option to bail out of rm'ing and let them handle secure deletion manually?
# TODO: What happens when when --print or edit a non-ASCII file? :) Can we detect that early?
# TODO: Expand --examples, new flags etc

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

err_echo() { echo "[${RD}${BD}!!!${RS}] ${RD}${BD}ERROR${RS} [${RD}${BD}!!!${RS}] - $*"; }

if [ "$#" -lt 1 ] || [ "$#" -gt 5 ]; then
  err_echo "Incorrect number of args, see --help:"
  display_usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) display_usage; exit 0;;
    -ex|--examples) display_examples; exit 0;;
    -v|--verbose) verbose=true; shift 1;; 

    -b|--backup) backup=true; if [ $# -gt 1 ];then BACKUP="$2";shift 2
              else err_echo "--backup missing FILE!";exit 1;fi;;
    -o|--out) out=true; if [ $# -gt 1 ];then OUTFILE="$2";shift 2
              else err_echo "--out missing FILE!";exit 1;fi;;

    -l|--list) list=true; shift 1;;
    -d|--decrypt) decrypt=true; shift 1;;

    -a|--add) add=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else err_echo "--add missing FILE!";exit 1;fi;;
    -p|--print) prnt=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else err_echo "--print missing FILE!";exit 1;fi;;
    -x|--extract) extract=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else err_echo "--extract missing FILE!";exit 1;fi;;
    -e|--edit) edit=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else err_echo "--edit missing FILE!";exit 1;fi;;
    -u|--update) update=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else err_echo "--update missing FILE!";exit 1;fi;;
    -r|--remove) remove=true; if [ $# -gt 1 ];then FILE="$2"; shift 2
              else err_echo "--remove missing FILE!";exit 1;fi;;

    --backup=*) backup=true; BACKUP="${1#*=}"; shift 1;;
    --out=*) out=true; OUTFILE="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --print=*) prnt=true; FILE="${1#*=}"; shift 1;;
    --extract=*) extract=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --update=*) update=true; FILE="${1#*=}"; shift 1;;
    --remove=*) remove=true; FILE="${1#*=}"; shift 1;;
    
    -*) err_echo "Unknown option $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done

if [ $backup ];then
  if ! [ -f $BACKUP ];then
    err_echo "The --backup FILE you specified cannot be found"
    exit 1
  elif ! [[ $BACKUP == *.gpg ]];then
    err_echo "Please specify a --backup FILE that ends in .gpg"
    exit 1
  fi
elif ! [ $backup ] && [[ $decrypt||$list||$prnt||$extract||$update||$edit||$remove ]];then
  err_echo "Cannot complete this operation without --backup specified!"
  exit 1
fi

if [[ $add || $update ]] && [[ ! $FILE || ! -f $FILE ]];then
  err_echo "The file targeted for add/update ($FILE) not found!"
  exit 1
fi

main() {
  if [[ $list||$prnt||$extract||$update||$edit||$remove ]] || [[ $add && $backup ]];then
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
  fi
  if [ $add ] && ! [ $backup ]; then # create new archive
    if ! [ $out ];then
      err_echo "The --add option requires --backup FILE or --out FILE to be paired with it. If" \
        "you're trying to update an existing backup use -b/--backup. If you're trying to start" \
        "a new backup, use -o/--out.";exit 1
    else
      create_or_update_archive $FILE $OUTFILE
      encrypt_zip $OUTFILE
      secure_remove_file $OUTFILE
    fi
  elif [ $add ] && [ $backup ];then # update existing archive
    if [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
      secure_remove_file $BACKUP
      err_echo "File $FILE already exists inside $BACKUP.gpg, if you want to update the existing" \
        "copy inside the archive, use --update.";exit 1
    fi
    create_or_update_archive $FILE $BACKUP
  elif [ $decrypt ];then
    decrypt_zip $BACKUP
    if [[ $? -eq 0 ]];then
      warn_echo "You have just decrypted the $BACKUP archive. It is exposed on the file system." \
        "Please be aware of the risks and clean up sensitive files manually if necessary."
    fi
  elif [ $update ];then
    if ! [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
      secure_remove_file $BACKUP
      err_echo "$FILE not found in $BACKUP.gpg, can't --update. If you want to add that" \
        "file instead try: $(basename $0) --add $FILE --backup $BACKUP";exit 1
    else
      mv $FILE $FILE.temp
      unzip -j $BACKUP $FILE
      if [[ $(checksum $FILE) == $(checksum $FILE.temp) ]];then
        add_update_echo "The file $FILE in the archive is identical to the one you've targeted." \
          "No changes were made, cleaning up."
        secure_remove_file $FILE
        mv $FILE.temp $FILE
        secure_remove_file $BACKUP
        exit 1
      fi
      secure_remove_file $FILE
      mv $FILE.temp $FILE
      create_or_update_archive $FILE $BACKUP
    fi
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
  [ $verbose ] && remove_echo "Attempting to remove $FILE from $2"
  local unencrypted_zip=$2
  zip --delete $unencrypted_zip $FILE # this asked for overwrite
  if ! [[ $? -eq 0 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    err_echo "File $FILE not found within $unencrypted_zip, aborting"
    exit 1
  else
    remove_echo "Success, $FILE removed from archive"
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
  [ $verbose ] && extract_echo "Attempting to extract $FILE from $2"
  local unencrypted_zip=$2
  unzip -j $unencrypted_zip $FILE
  if ! [[ $? -eq 0 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    err_echo "File $FILE not found within $unencrypted_zip, aborting"
    exit 1
  else
    extract_echo "Success, $FILE recovered from archive $unencrypted_zip"
  fi
}

create_or_update_archive() {
  local unencrypted_zip=$2
  if [ $out ] && [[ $OUTFILE == "" || -d $OUTFILE ]];then
    if [ -d $OUTFILE ] && ! [ $OUTFILE == */ ];then OUTFILE="$OUTFILE/";fi
    unencrypted_zip="${OUTFILE}${DATE}.zip"
    OUTFILE="${OUTFILE}${DATE}.zip"
    add_update_echo "--out was blank or resolves to a directory, defaulting to datestamp" \
      "for filename: $OUTFILE"
    fi
  fi
  if [ $OUTFILE ] && [ -f $OUTFILE ];then
    err_echo "Doing --out $OUTFILE would over-write an existing file! If you want to" \
      "update an existing backup, use --backup instead of --out. Otherwise, pick a different file" \
      "location/name or remove the blocking file manually and re-run. Oopsie prevention."
    exit 1
  fi
  zip -urj $unencrypted_zip $FILE # -rj abandon directory structure of files added
  if [[ $? -eq 0 ]];then
    add_update_echo "Success, archive creation/update complete"
  elif [[ $? -eq 12 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    add_update_echo "[${YL}NO-OP${RS}] zip update failed 'nothing to do'?"
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    err_echo "Unknown zip creation or update error!"
  fi
}

print_file_from_archive() {
  local unencrypted_zip=$2
  [ $verbose ] && print_echo "Attempting to route $FILE to STDOUT from ${BACKUP%????}"
  if ! [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    err_echo "$FILE not found in $BACKUP.gpg, can't --print!"
    exit 1
  fi
  echo "${WH}${BD}--- BEGIN OUTPUT ---${RS}"
  unzip -p ${BACKUP%????} $(basename $FILE)
  echo "${WH}${BD}---  END OUTPUT  ---${RS}"
}

list_archive_contents() {
  unzip -v $1
  if ! [[ $? -eq 0 ]];then err_echo "Unknown unzip error during --list!";fi
}

edit_file_from_archive() {
  local unencrypted_zip=$2
  if ! [[ $(check_file_existence $FILE $unencrypted_zip) ]];then
    err_echo "Operation --edit failed, $FILE not found in the archive!"
    exit 1
  fi
  extract_file_from_archive $FILE $unencrypted_zip
  if command -v $EDITOR >/dev/null;then
    [ $verbose ] && edit_echo "Attempting to launch editor: $EDITOR"
    $EDITOR $FILE
  else
    edit_echo "Couldn't find editor \"$EDITOR\", launching with nano"
    EDITOR=nano
    $EDITOR $FILE
  fi
  if [[ $? -eq 0 ]];then
    create_or_update_archive $FILE $unencrypted_zip
  else
    err_echo "Editor \"$EDITOR\" exited with a non-zero status! ($?) Cleaning up exposed files."
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    if [ -f $FILE ];then secure_remove_file $FILE;fi
    exit 1
  fi
  if [ -f $FILE ];then secure_remove_file $FILE;fi # cleanup the file we edited, we're done with it
}

decrypt_zip() {
  [ $verbose ] && decrypt_echo "Attempting gpg decrypt"
  local unencrypted_zip=${1%????}
  local exit_msg
  exit_msg="$(gpg -q --no-symkey-cache -o $unencrypted_zip --decrypt $1 2>&1)"
  if [[ $? -eq 0 ]]; then
    decrypt_echo "Success, $unencrypted_zip has been restored"
  elif [[ $(echo "$exit_msg" | grep "Bad session key") ]];then
    err_echo "GPG decryption failed due to incorrect passphrase! Exiting."
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    exit 1
  else
    err_echo "GPG decryption error! Exiting."
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    exit 1
  fi
}

encrypt_zip() {
  [ $verbose ] && encrypt_echo "Attempting gpg encrypt"
  local unencrypted_zip=$1
  if [[ $add || $update || $remove || $edit ]];then
    # --yes during add/update, user is explicitly running a write command already
    gpg -q --yes --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  else # in other situations we may want to confirm over-writing if it crops up
    gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  fi
  if [[ $? -eq 0 ]];then
    encrypt_echo "Success, $unencrypted_zip.gpg protected by $ALGO"
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    err_echo "GPG encryption error! Exiting."
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
    if [[ $? -eq 0 ]];then
      cleanup_echo "Success, $1 purged securely via: $secure_removal_cmd"
    else
      cleanup_echo "${RD}FALLBACK${RS}: Secure file removal failed! Resorting to using rm"
      unsecure_remove_file $1
    fi
  else
    cleanup_echo "Secure file removal not found on system, resorting to using rm"
    unsecure_remove_file $1
  fi
}

unsecure_remove_file() {
  rm -f $1
  if [[ $? -eq 0 ]]; then
    cleanup_echo "Success, rm of $1 complete"
  else
    err_echo "File removal with rm failed! (Somehow?? You figure this one out.)"
    exit 1
  fi
}

checksum() {
  echo $(sha256sum $1 | cut -f1 -d ' ')
}

add_update_echo() { echo "[${GN}${BD}!${RS}] ${GN}${BD}ADD${RS}${BD}/${GN}UPDATE${RS}: $*"; }
remove_echo()     { echo "[${RD}${BD}!${RS}] ${RD}REMOVE${RS}: $*"; }
edit_echo()       { echo "    ${MG}EDIT${RS}: $*"; }
extract_echo()    { echo "    ${CY}EXTRACT${RS}: $*"; }
print_echo()      { echo "    ${WH}${BD}PRINT${RS}: $*"; }
encrypt_echo()    { echo "[${CY}${BD}!${RS}] ${BL}${BD}ENCRYPT${RS}: $*"; }
decrypt_echo()    { echo "[${CY}${BD}!${RS}] ${CY}${BD}DECRYPT${RS}: $*"; }
cleanup_echo()    { echo "[${YL}${BD}!${RS}] ${YL}${BD}CLEANUP${RS}: $*"; }
warn_echo()       { echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS} [${YL}${BD}!!!${RS}] - $*"; }

main
exit 0
