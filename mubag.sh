#!/bin/bash

# TODO: Add --algo to forward options to gpg's --cipher-algo, use ALGO config for default
# TODO: What happens when when --print or edit a non-ASCII file? :) Can we detect that early?
# TODO: Should log be nested so we can track failures? ie, a wrapper zip containing unencrypted log?
# TODO: Add user to activity log

trap trap_cleanup SIGINT SIGTERM
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
  -s, --skip-logging            Disable updating of the archive log file

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

    $(basename $0) --add=secret.txt --out=backup.zip
    $(basename $0) -o backup.zip -a dirtypic.png

  List contents or print specific files from encrypted archive:

    $(basename $0) --backup=/home/user/backup.zip.gpg --list
    $(basename $0) -b /home/user/backup.zip.gpg --print ntt.log

  Add new or update existing file within encrypted archive:

    $(basename $0) -b /home/user/backup.zip.gpg --update latest.log
    $(basename $0) --backup /home/user/backup.zip.gpg --add=qr_code.jpg

  Extract or remove a file inside an encrypted archive:

    $(basename $0) -b /home/user/backup.zip.gpg --extract secrets.txt
    $(basename $0) --backup /home/user/backup.zip.gpg --remove recovery_key

  Edit existing file inside an encrypted archive:

    $(basename $0) --edit 2fa.bak -b /home/user/backup.zip.gpg
    $(basename $0) --backup=/home/user/backup.zip.gpg -e rosebud.conf

  [${YL}${BD}WARNING${RS}] Decrypt all contents:

    $(basename $0) -b /home/user/backup.zip.gpg --decrypt
"
}

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
      ! [ $skiplog ] && add_update_log "Attempting to update $FILE within $BACKUP"
      mv $FILE $FILE.temp
      unzip -j $BACKUP $FILE
      if [[ $(checksum $FILE) == $(checksum $FILE.temp) ]];then
        add_update_echo "The file $FILE in the archive is identical to the one you've targeted." \
          "No changes were made, cleaning up."
        ! [ $skiplog ] && add_update_log "[NO-OP] Update failed, no changes"
        secure_remove_file $FILE
        mv $FILE.temp $FILE
      else
        secure_remove_file $FILE
        mv $FILE.temp $FILE
        create_or_update_archive $FILE $BACKUP
      fi
    fi
  elif [ $prnt ];then print_file_from_archive $FILE $BACKUP
  elif [ $list ];then list_archive_contents $BACKUP
  elif [ $extract ];then extract_file_from_archive $FILE $BACKUP
  elif [ $edit ];then edit_file_from_archive $FILE $BACKUP
  elif [ $remove ];then remove_file_from_archive $FILE $BACKUP
  fi
  if [ $OUTFILE ];then BACKUP=$OUTFILE;fi
  if ! [ $preventencrypt ];then encrypt_zip $BACKUP;fi
  if [[ $backup || $out ]] && [[ -f $BACKUP && ! $decrypt ]];then secure_remove_file $BACKUP;fi
}

parse_and_setup(){
  if [ "$#" -lt 1 ] || [ "$#" -gt 9 ]; then
    err_echo "Incorrect number of args, see --help:"
    display_usage
    exit 1
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help) display_usage; exit 0;;
      -ex|--examples|--example) display_examples; exit 0;;
      -v|--verbose) verbose=true; shift 1;;
      -s|--skip-logging|--skip-log|--skip|--skiplog) skiplog=true; shift 1;;
      -l|--list) list=true; shift 1;;
      -d|--decrypt) decrypt=true; shift 1;;
      -ne|--no-encrypt) preventencrypt=true; shift 1;;

      -b|--backup) backup=true; if [ $# -gt 1 ];then BACKUP="$2";shift 2
                else err_echo "--backup missing FILE!";exit 1;fi;;
      -o|--out) out=true; if [ $# -gt 1 ];then OUTFILE="$2";shift 2
                else err_echo "--out missing FILE!";exit 1;fi;;
      -t|--test) test=true; if [ $# -gt 1 ];then testpass="$2"; shift 2
                else err_echo "--test requires a PASSPHRASE passed with it to automate!";exit 1;fi;;
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

      --test=*) test=true; testpass="${1#*=}"; shift 1;;
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
  LOG_DISABLED=false
}

sanity_checks() {
  if [ $backup ];then
    if ! [ -f $BACKUP ];then
      err_echo "The --backup FILE you specified cannot be found"
      exit 1
    elif ! [[ $BACKUP == *.gpg ]];then
      err_echo "Please specify a --backup FILE that ends in .gpg"
      exit 1
    elif ! [[ $add || $prnt || $extract || $edit || $update || $remove || $list || $decrypt ]];then
      err_echo "Do what with --backup $BACKUP? You must select an operation to perform, see --help."
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
}

remove_file_from_archive() {
  local unencrypted_zip=$2
  [ $verbose ] && remove_echo "Attempting to remove $FILE from $unencrypted_zip"
  zip --delete $unencrypted_zip $FILE
  if ! [[ $? -eq 0 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    ! [ $skiplog ] && remove_log "Removal of $FILE failed, does not exist in $unencrypted_zip"
    err_echo "File $FILE not found within $unencrypted_zip, aborting"
    err_exit
  else
    ! [ $skiplog ] && remove_log "Removal of $FILE from $unencrypted_zip was successful"
    remove_echo "Success, $FILE removed from archive"
  fi
}

check_file_existence() {
  local file=$1
  local unencrypted_zip=$2
  unzip -v $unencrypted_zip | grep $(basename $file) >/dev/null
  if [[ $? -eq 0 ]];then
    echo 0
  else
    echo 1
  fi
}

extract_logfile() {
  local unencrypted_zip=$2
  [ $verbose ] && log_echo "Attempting to extract activity.log from $unencrypted_zip"
  if [[ $(check_file_existence $LOG $unencrypted_zip) -eq 0 ]];then
    unzip -j $unencrypted_zip $LOG
  else
    [ $verbose ] && log_echo "No activity.log present in this archive, one will be created"
  fi
  
}

extract_file_from_archive() {
  local file=$1
  local unencrypted_zip=$2
  [ $verbose ] && extract_echo "Attempting to extract $file from $unencrypted_zip"
  unzip -j $unencrypted_zip $file
  if ! [[ $? -eq 0 ]];then
    ! [ $skiplog ] && extract_log "Extraction of $file failed, does not exist in $unencrypted_zip"
    err_echo "File $file not found within $unencrypted_zip, aborting"
    err_exit
  else
    ! [ $skiplog ] && extract_log "Extraction of $file from $unencrypted_zip was successful"
    extract_echo "Success, $file recovered from archive $unencrypted_zip"
  fi
}

create_or_update_archive() {
  local file=$1
  local unencrypted_zip=$2
  if [ $out ] && [[ $OUTFILE == "" || -d $OUTFILE ]];then
    if [ -d $OUTFILE ] && ! [ $OUTFILE == */ ];then OUTFILE="$OUTFILE/";fi
    unencrypted_zip="${OUTFILE}${DATE}.zip"
    OUTFILE="${OUTFILE}${DATE}.zip"
    add_update_echo "--out was blank or resolves to a directory, defaulting to datestamp" \
      "for filename: $OUTFILE"
  fi
  if [ $OUTFILE ] && [ -f $OUTFILE ];then
    err_echo "Doing --out $OUTFILE would over-write an existing file! If you want to" \
      "update an existing backup, use --backup instead of --out. Otherwise, pick a different file" \
      "location/name or remove the blocking file manually and re-run. Oopsie prevention."
    exit 1
  fi
  zip -urj $unencrypted_zip $file # -rj abandon directory structure of files added
  if [[ $? -eq 0 ]];then
    if ! [ $skiplog ];then # && ! [[ "$file" == "$LOG" ]];then 
      add_update_log "File $file was added or updated within $unencrypted_zip"
    fi
    add_update_echo "Success, archive creation/update complete"
  elif [[ $? -eq 12 ]];then
    add_update_echo "[${YL}NO-OP${RS}] zip update failed 'nothing to do'?"
    err_exit
  else
    err_echo "Unknown zip creation or update error!"
    err_exit
  fi
}

print_file_from_archive() {
  local file=$1
  local unencrypted_zip=$2
  [ $verbose ] && print_echo "Attempting to route $file to STDOUT from $unencrypted_zip"
  if ! [[ $(check_file_existence $file $BACKUP) -eq 0 ]];then
    err_echo "$file not found in $BACKUP.gpg, can't --print!"
    err_exit
  fi
  echo "${WH}${BD}--- BEGIN OUTPUT ---${RS}"
  unzip -p $unencrypted_zip $(basename $file)
  echo "${WH}${BD}---  END OUTPUT  ---${RS}"
  ! [ $skiplog ] && print_log "$file was successfully routed to STDOUT from $unencrypted_zip"
}

list_archive_contents() {
  local unencrypted_zip=$1
  unzip -v $unencrypted_zip
  if ! [[ $? -eq 0 ]];then err_echo "Unknown unzip error during --list!";fi
  ! [ $skiplog ] && list_log "The contents of $unencrypted_zip were displayed via --list"
}

edit_file_from_archive() {
  local file=$1
  local unencrypted_zip=$2
  if ! [[ $(check_file_existence $file $unencrypted_zip) ]];then
    err_echo "Operation --edit failed, $file not found in the archive!"
    exit 1
  fi
  extract_file_from_archive $file $unencrypted_zip
  filehash_orig=$(checksum $file)
  if [ $test ];then # skip the whole interactive bit, just modify the file
    echo "Ch-ch-ch-ch-changes" >> $file
  else
    if command -v $EDITOR >/dev/null;then
      [ $verbose ] && edit_echo "Attempting to launch editor: $EDITOR"
      $EDITOR $file
    else
      edit_echo "Couldn't find editor \"$EDITOR\", launching with nano"
      EDITOR=nano
      $EDITOR $file
    fi
  fi
  if [[ $? -eq 0 ]];then
    filehash_new=$(checksum $file)
    if [[ filehash_orig == filehash_new ]];then
      ! [ $skiplog ] && edit_log "$file was opened in an editor but no changes were made"
      edit_echo "$file was left unchanged, archive will remain unchanged, cleaning up"
    else
      ! [ $skiplog ] && edit_log "$file was opened in an editor and successfully modified"
      create_or_update_archive $file $unencrypted_zip
    fi
  else
    err_echo "Editor \"$EDITOR\" exited with a non-zero status! ($?) Cleaning up exposed files."
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    if [ -f $file ];then secure_remove_file $file;fi
    exit 1
  fi
  if [ -f $file ];then secure_remove_file $file;fi
}

decrypt_zip() {
  [ $verbose ] && decrypt_echo "Attempting gpg decrypt"
  local unencrypted_zip=${1%????}
  local exit_msg
  if [[ $test ]];then
    exit_msg="$(gpg -q --batch --yes --passphrase $testpass -o $unencrypted_zip --decrypt $1 2>&1)"
  else
    exit_msg="$(gpg -q --no-symkey-cache -o $unencrypted_zip --decrypt $1 2>&1)"
  fi
  if [[ $? -eq 0 ]]; then
    decrypt_echo "Success, $unencrypted_zip has been restored"
    if ! [ $skiplog ];then
      extract_logfile $LOG $unencrypted_zip && decrypt_log "Archive $unencrypted_zip.gpg" \
        "successfully decrypted"
      if ! [[ $? -eq 0 ]];then
        err_echo "Failed to extract and update $LOG from $unencrypted_zip!"
        exit 1
      fi
    fi
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
  if ! [ $skiplog ];then
    encrypt_log "Encrypting $unencrypted_zip"
    local msg=$(zip -urj $unencrypted_zip $LOG)
    if [[ $? -eq 0 ]];then
      sleep 0.1
      log_echo "Archive log successfully updated within $unencrypted_zip"
      if [ -f $LOG ];then secure_remove_file $LOG;fi
    else
      warn_echo "Archive log exited $?, message: $msg"
      if [ -f $LOG ];then secure_remove_file $LOG;fi
      if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
      exit 1
    fi
  fi
  if [[ $test ]];then
    gpg -q --batch --yes --passphrase $testpass --cipher-algo $ALGO --symmetric $unencrypted_zip
  elif [[ $add || $update || $remove || $edit ]];then
    # --yes during add/update, user is explicitly running a write command already
    gpg -q --yes --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  else # in other situations we may want to confirm over-writing if it crops up
    gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  fi
  if [[ $? -eq 0 ]];then
    encrypt_echo "Success, $unencrypted_zip.gpg protected by $ALGO"
    LOG_DISABLED=true
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    err_echo "GPG encryption error! Exiting."
    exit 1
  fi
}

secure_remove_file() {
  local cmd=""
  if command -v srm >/dev/null;then
    cmd="srm -zv $1"
  elif command -v shred >/dev/null;then
    cmd="shred -uz $1"
  fi
  if ! [[ cmd == "" ]];then
    $cmd # execute the removal
    if [[ $? -eq 0 ]];then
      if ! [ $skiplog ] && ! [[ $1 == $LOG || $LOG_DISABLED ]];then
        cleanup_log "$1 securely erased with: $cmd"
      fi
      cleanup_echo "Success, $1 purged securely via: $cmd"
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
    ! [ $skiplog ] && ! [[ $1 == $LOG ]] && cleanup_log "No secure removal found, $1" \
      "removed via: $cmd"
    cleanup_echo "Success, rm of $1 complete"
  else
    err_echo "File removal with rm failed! (Somehow?? You figure this one out.)"
    exit 1
  fi
}

checksum() {
  echo $(sha256sum $1 | cut -f1 -d ' ')
}

trap_cleanup() {
  if [[ $backup && -f ${BACKUP%????} && ! $decrypt ]];then secure_remove_file ${BACKUP%????};fi
  if [[ $prnt || $edit ]] && [[ -f $FILE ]];then secure_remove_file $FILE;fi
  exit 1
}

append_to_activity_log() {
  datestamp=$(date "+%Y-%m-%d %H:%M:%S")
  if ! [[ $skiplog ]];then
    echo "$datestamp $1" >> activity.log
  else
    [ $verbose ] && log_echo "Skipping log update due to --skip-logging"
  fi
}

err_exit() {
  if [ $OUTFILE ];then BACKUP=$OUTFILE;fi
  if ! [ $preventencrypt ];then encrypt_zip $BACKUP;fi
  if [[ $backup || $out ]] && [[ -f $BACKUP && ! $decrypt ]];then secure_remove_file $BACKUP;fi
  exit 1
}

add_update_log()  { append_to_activity_log "ADD/UPDATE   $*"; }
remove_log()      { append_to_activity_log "REMOVE       $*"; }
edit_log()        { append_to_activity_log "EDIT         $*"; }
extract_log()     { append_to_activity_log "EXTRACT      $*"; }
print_log()       { append_to_activity_log "PRINT        $*"; }
list_log()        { append_to_activity_log "LIST         $*"; }
encrypt_log()     { append_to_activity_log "ENCRYPT      $*"; }
decrypt_log()     { append_to_activity_log "DECRYPT      $*"; }
cleanup_log()     { append_to_activity_log "CLEANUP      $*"; }

add_update_echo() { echo "[${GN}${BD}!${RS}] ${GN}${BD}ADD${RS}${BD}/${GN}UPDATE${RS}: $*"; }
remove_echo()     { echo "[${RD}${BD}!${RS}] ${RD}REMOVE${RS}: $*"; }
edit_echo()       { echo "    ${MG}EDIT${RS}: $*";       }
extract_echo()    { echo "    ${CY}EXTRACT${RS}: $*";    }
print_echo()      { echo "    ${WH}${BD}PRINT${RS}: $*"; }
encrypt_echo()    { echo "[${CY}${BD}!${RS}] ${BL}${BD}ENCRYPT${RS}: $*"; }
decrypt_echo()    { echo "[${CY}${BD}!${RS}] ${CY}${BD}DECRYPT${RS}: $*"; }
cleanup_echo()    { echo "[${YL}${BD}!${RS}] ${YL}${BD}CLEANUP${RS}: $*"; }
warn_echo()       { echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS} [${YL}${BD}!!!${RS}] - $*";    }
err_echo()        { echo "[${RD}${BD}!!!${RS}] ${RD}${BD}ERROR${RS} [${RD}${BD}!!!${RS}] - $*"; }
log_echo()        { echo "${BD}LOGGING${RS}: $*"; }

parse_and_setup $*
sanity_checks
main
exit 0
