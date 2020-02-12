#!/bin/bash

# TODO: Add user to activity log
# TODO: (?) Should log be nested so we can track failures? ie, a wrapper zip containing unencrypted log?
# TODO: (?) What happens when when --print or edit a non-ASCII file? :) Can we detect that early?

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

  -h,  --help                       This screen
  -ex, --examples                   Print examples of usage
  -v,  --verbose                    Increase output to assist in debugging
  -s,  --skip-logging               Disable updating of the archive log file
  -n,  --new                        Treat --backup as new archive creation
  --ciphers, --show-ciphers         List the available gpg options for --algo

  -b FILE, --backup FILE            Specify existing encrypted archive to use
  --algo ALGO, --cipher-algo ALGO   Set the encryption algorithm for gpg
                                      (currently defaulting to: $ALGO)

  -l, --list                        List contents of existing backup archive
  -d, --decrypt                     Decrypt existing backup archive

  -a FILE, --add FILE               Add FILE to archive (or create a new one)
  -p FILE, --print FILE             Print contents of FILE in archive to STDOUT
  -e FILE, --edit FILE              Open FILE in $EDITOR for modification
  -x FILE, --extract FILE           Extract FILE from existing archive
  -r FILE, --remove FILE            Remove FILE from existing archive
  -u FILE, --update FILE            Update/replace FILE within existing archive
                                    (ie, overwrite keys.txt with a new version)
"
}

display_examples() {
  echo "
EXAMPLES:

  Create a new encrypted archive, use any file:

    $(basename $0) --new --add=secret.txt --backup=newbackup.zip
    $(basename $0) --new -a dirtypic.png

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

parse_and_setup(){
  if [ "$#" -lt 1 ] || [ "$#" -gt 12 ]; then
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
      -n|--new) create=true; shift 1;;
      --ciphers|--show-ciphers) gpg_get_available_ciphers; exit 0;;

      -al|--algo|--cipher-algo) algo=true; if [ $# -gt 1 ];then ALGO="$2"; shift 2
                else err_echo "--algo missing ALGO option!";exit 1;fi;;

      -b|--backup) backup=true; if [ $# -gt 1 ];then BACKUP="$2";shift 2
                else err_echo "--backup missing FILE!";exit 1;fi;;
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
      --algo=*|--cipher-algo=*) algo=true; ALGO="${1#*=}"; shift 1;;
      --backup=*) backup=true; BACKUP="${1#*=}"; shift 1;;
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

sanity_check_args() {
  if [[ $algo && ! $create ]];then
    err_echo "Setting the encryption --algo algorithm currently only supported for --new archives"
    exit 1
  elif ! [[ $(gpg_get_available_ciphers | grep "\b$ALGO\b") ]];then
    err_echo "The --algo/--cipher-algo $ALGO is not supported by the installed version of gpg."
      echo "The supported ciphers are: $(gpg_get_available_ciphers)"
    exit 1
  fi
  if [[ $create && ! $add ]];then
    err_echo "If you're using --new you must specify a file to --add/-a, too!"
    display_usage
    exit 1
  elif [[ $create && $add ]] || [[ $add && ! $backup ]] || [[ $add && ! $BACKUP ]];then
    if [[ $BACKUP = "" || -d $BACKUP ]];then
      if [ -d $BACKUP ] && ! [[ $BACKUP == */ ]];then BACKUP="$BACKUP/";fi
      BACKUP="${BACKUP}${DATE}.zip"
      backup=true
      create_echo "--backup was blank or resolves to a directory, defaulting to datestamp" \
        "for filename: $BACKUP"
    fi
  fi
  if [ $backup ];then
    if ! [[ $add || $prnt || $extract || $edit || $update || $remove || $list || $decrypt ]];then
      err_echo "Do what with --backup $BACKUP? You must select an operation to perform."
      display_usage
      exit 1
    elif ! [ -f $BACKUP ] && ! [ $create ];then
      err_echo "The --backup FILE you specified cannot be found"
      exit 1
    elif [[ -f $BACKUP && ! $BACKUP == *.gpg ]];then
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
  if [[ $BACKUP == *.gpg ]];then BACKUP=${BACKUP%????};fi # chop off .gpg
}

main() {
  if [[ $list||$prnt||$extract||$update||$edit||$remove ]]||[[ $add && $backup && ! $create ]];then
    decrypt_zip $BACKUP
  fi
  if [[ $create && $add ]] || [[ $add && ! $backup ]];then create_new_archive $FILE $BACKUP
  elif [[ $add && $backup ]];then # add file to existing archive
    if [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
      err_echo "File $FILE already exists inside $BACKUP.gpg, if you want to update the existing" \
        "copy inside the archive, use --update."
      err_exit
    fi
    update_archive $FILE $BACKUP
  elif [ $decrypt ];then
    decrypt_zip $BACKUP
    if [[ $? -eq 0 ]];then
      warn_echo "You have just decrypted the $BACKUP archive. It is exposed on the file system." \
        "Please be aware of the risks and clean up sensitive files manually if necessary."
    fi
  elif [ $update ];then
    if ! [[ $(check_file_existence $FILE $BACKUP) -eq 0 ]];then
      err_echo "$FILE not found in $BACKUP.gpg, can't --update. If you want to add that" \
        "file instead try: $(basename $0) --add $FILE --backup $BACKUP"
      err_exit
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
        update_archive $FILE $BACKUP
      fi
    fi
  elif [ $prnt ];then print_file_from_archive $FILE $BACKUP
  elif [ $list ];then list_archive_contents $BACKUP
  elif [ $extract ];then extract_file_from_archive $FILE $BACKUP
  elif [ $edit ];then edit_file_from_archive $FILE $BACKUP
  elif [ $remove ];then remove_file_from_archive $FILE $BACKUP
  fi
  if ! [ $preventencrypt ];then encrypt_zip $BACKUP;fi
  if [[ $backup ]] && [[ -f $BACKUP && ! $decrypt ]];then secure_remove_file $BACKUP;fi
  gpg_clear_cache
}

remove_file_from_archive() {
  local unenc_zip=$2
  [ $verbose ] && remove_echo "Attempting to remove $FILE from $unenc_zip"
  zip --delete $unenc_zip $FILE
  if ! [[ $? -eq 0 ]];then
    if [ -f $unenc_zip ];then secure_remove_file $unenc_zip;fi
    ! [ $skiplog ] && remove_log "Removal of $FILE failed, does not exist in $unenc_zip"
    err_echo "File $FILE not found within $unenc_zip, aborting"
    err_exit
  else
    ! [ $skiplog ] && remove_log "Removal of $FILE from $unenc_zip was successful"
    remove_echo "Success, $FILE removed from archive"
  fi
}

check_file_existence() {
  local file=$1
  local unenc_zip=$2
  unzip -v $unenc_zip | grep $(basename $file) >/dev/null
  if [[ $? -eq 0 ]];then
    echo 0
  else
    echo 1
  fi
}

extract_logfile() {
  local unenc_zip=$2
  [ $verbose ] && log_echo "Attempting to extract activity.log from $unenc_zip"
  if [[ $(check_file_existence $LOG $unenc_zip) -eq 0 ]];then
    unzip -j $unenc_zip $LOG
  else
    [ $verbose ] && log_echo "No activity.log present in this archive, one will be created"
  fi
  
}

extract_file_from_archive() {
  local file=$1
  local unenc_zip=$2
  [ $verbose ] && extract_echo "Attempting to extract $file from $unenc_zip"
  if [[ $(check_file_existence $file $unenc_zip ) -eq 0 ]];then
    unzip -j $unenc_zip $file
    if [[ $? -eq 0 ]];then
      extract_echo "Success, $file recovered from archive $unenc_zip"
      ! [ $skiplog ] && extract_log "Extraction of $file from $unenc_zip was successful"
    else
      err_echo "Unzip failed during extraction with code $?"
      err_exit
    fi
  else
    ! [ $skiplog ] && extract_log "Extraction of $file failed, does not exist in $unenc_zip"
    err_echo "File $file not found within $unenc_zip, aborting"
    err_exit
  fi
}

create_new_archive() {
  local file=$1
  local unenc_zip=$2
  if [ $BACKUP ] && [ -f $BACKUP ];then
    err_echo "--backup $BACKUP would over-write an existing file! If you are trying to modify that" \
      "archive, don't use --new/-n. Select a different file name and try again."
    err_exit
  fi
  zip -rj $unenc_zip $file # -rj abandon directory structure of files added
  if [[ $? -eq 0 ]];then
    if ! [ $skiplog ];then create_log "File $file was added or updated within $unenc_zip";fi
    create_echo "Success, archive creation complete $unenc_zip"
    ! [ $skiplog ] && create_log "New archive $unenc_zip created"
  elif [[ $? -eq 12 ]];then
    create_echo "[${YL}NO-OP${RS}] zip update failed 'nothing to do'?"
    err_exit
  else
    err_echo "Zip failed during archive creation with code $?"
    err_exit
  fi
}

update_archive() {
  local file=$1
  local unenc_zip=$2
  zip -urj $unenc_zip $file # -rj abandon directory structure of files added
  if [[ $? -eq 0 ]];then
    if ! [ $skiplog ];then # && ! [[ "$file" == "$LOG" ]];then 
      add_update_log "File $file was updated within $unenc_zip"
    fi
    add_update_echo "Success, archive update complete $unenc_zip"
  elif [[ $? -eq 12 ]];then
    add_update_echo "[${YL}NO-OP${RS}] zip update failed 'nothing to do'?"
    err_exit
  else
    err_echo "Zip failed during archive update with code $?"
    err_exit
  fi
}

print_file_from_archive() {
  local file=$1
  local unenc_zip=$2
  [ $verbose ] && print_echo "Attempting to route $file to STDOUT from $unenc_zip"
  if ! [[ $(check_file_existence $file $BACKUP) -eq 0 ]];then
    err_echo "$file not found in $BACKUP.gpg, can't --print!"
    err_exit
  fi
  echo "${WH}${BD}--- BEGIN OUTPUT ---${RS}"
  unzip -p $unenc_zip $(basename $file)
  echo "${WH}${BD}---  END OUTPUT  ---${RS}"
  ! [ $skiplog ] && print_log "$file was successfully routed to STDOUT from $unenc_zip"
}

list_archive_contents() {
  local unenc_zip=$1
  unzip -v $unenc_zip
  if ! [[ $? -eq 0 ]];then err_echo "Unknown unzip error during --list!";fi
  ! [ $skiplog ] && list_log "The contents of $unenc_zip were displayed via --list"
}

edit_file_from_archive() {
  local file=$1
  local unenc_zip=$2
  if ! [[ $(check_file_existence $file $unenc_zip) ]];then
    err_echo "Edit failed - $file not found in the archive!"
    err_exit
  fi
  extract_file_from_archive $file $unenc_zip
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
      update_archive $file $unenc_zip
    fi
  else
    err_echo "Editor \"$EDITOR\" exited with a non-zero status! ($?) Cleaning up exposed files."
    if [ -f $unenc_zip ];then secure_remove_file $unenc_zip;fi
    if [ -f $file ];then secure_remove_file $file;fi
    exit 1
  fi
  if [ -f $file ];then secure_remove_file $file;fi
}

decrypt_zip() {
  [ $verbose ] && decrypt_echo "Attempting gpg decrypt"
  local unenc_zip=$1
  local exit_msg
  if [[ $test ]];then
    gpg -q --batch --yes --passphrase $testpass -o $unenc_zip --decrypt $unenc_zip.gpg 2>&1
  else
    gpg -q -o $unenc_zip --decrypt $unenc_zip.gpg 2>&1
  fi
  if [[ $? -eq 0 ]]; then
    decrypt_echo "Success, $unenc_zip has been restored"
    if ! [ $skiplog ];then
      extract_logfile $LOG $unenc_zip && decrypt_log "Archive $unenc_zip.gpg" \
        "successfully decrypted"
      if ! [[ $? -eq 0 ]];then
        err_echo "Failed to extract and update $LOG from $unenc_zip!"
        exit 1
      fi
    fi
  elif [[ $(echo "$exit_msg" | grep "Bad session key") ]];then
    err_echo "GPG decryption failed due to incorrect passphrase! Exiting."
    if [ -f $unenc_zip ];then secure_remove_file $unenc_zip;fi
    exit 1
  else
    err_echo "GPG decryption error! Exiting."
    if [ -f $unenc_zip ];then secure_remove_file $unenc_zip;fi
    exit 1
  fi
}

encrypt_zip() {
  [ $verbose ] && encrypt_echo "Attempting gpg encrypt"
  local unenc_zip=$1
  if ! [ $skiplog ];then
    encrypt_log "Encrypting $unenc_zip"
    local msg=$(zip -urj $unenc_zip $LOG)
    if [[ $? -eq 0 ]];then
      log_echo "Archive log successfully updated within $unenc_zip"
      if [ -f $LOG ];then secure_remove_file $LOG;fi
    else
      warn_echo "Archive log exited $?, message: $msg"
      if [ -f $LOG ];then secure_remove_file $LOG;fi
      if [ -f $unenc_zip ];then secure_remove_file $unenc_zip;fi
      exit 1
    fi
  fi
  if [[ $test ]];then
    gpg -q --batch --yes --passphrase $testpass --cipher-algo $ALGO --symmetric $unenc_zip
  elif [[ $add || $update || $remove || $edit || $list || $prnt ]];then
    # --yes during read-only (activity.log updates) and during user explicit writes
    gpg -q --yes --cipher-algo $ALGO --symmetric $unenc_zip
  else # in other situations we may want to confirm over-writing if it crops up
    gpg -q --cipher-algo $ALGO --symmetric $unenc_zip
  fi
  if [[ $? -eq 0 ]];then
    encrypt_echo "Success, $unenc_zip.gpg protected by $ALGO"
    LOG_DISABLED=true
  else
    if [ -f $unenc_zip ];then secure_remove_file $unenc_zip;fi
    err_echo "GPG encryption error! Exiting."
    exit 1
  fi
}

secure_remove_file() {
  if [ $test ] && ! [ $skiplog ] && ! [[ $1 == $LOG || $LOG_DISABLED ]];then
    unsecure_remove_file $1 # Avoid unnecessary SSD wear during tests
  else
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

gpg_clear_cache() {
  gpg-connect-agent reloadagent /bye >/dev/null
  if [[ $? -eq 0 ]];then
    [ $verbose ] && cleanup_echo "GPG agent reloaded to flush cached symkey"
  else
    warn_echo "GPG agent reload has failed! Cached symkeys may still be present. You can try to" \
      "run 'gpg-connectagent reloadagent /bye' to try again, or kill the agent process manually. "
  fi
}

gpg_get_available_ciphers() {
  local ciphers=$(gpg --version | grep -A1 Cipher | sed 's/Cipher://g' | tr '\n' ' ')
  IFS=', ' read -r -a ciphers <<< "$ciphers"
  echo ${ciphers[@]}
}

append_to_activity_log() {
  datestamp=$(date "+%Y-%m-%d %H:%M:%S")
  if ! [ $skiplog ];then echo "$datestamp $1" >> activity.log;fi
}

checksum() {
  echo $(sha256sum $1 | cut -f1 -d ' ')
}

trap_cleanup() {
  if [[ $BACKUP == *.gpg ]];then BACKUP=${BACKUP%????};fi # chop off .gpg
  if [[ $BACKUP && $BACKUP == *.zip && -f $BACKUP ]];then secure_remove_file $BACKUP;fi
  if [[ $prnt || $edit ]] && [[ -f $FILE ]];then secure_remove_file $FILE;fi
  gpg_clear_cache
  exit 1
}

err_exit() {
  if ! [ $preventencrypt ];then encrypt_zip $BACKUP;fi
  if [[ $backup ]] && [[ -f $BACKUP && ! $decrypt ]];then secure_remove_file $BACKUP;fi
  gpg_clear_cache
  exit 1
}

create_log()      { append_to_activity_log "CREATE       $*"; }
add_update_log()  { append_to_activity_log "ADD/UPDATE   $*"; }
remove_log()      { append_to_activity_log "REMOVE       $*"; }
edit_log()        { append_to_activity_log "EDIT         $*"; }
extract_log()     { append_to_activity_log "EXTRACT      $*"; }
print_log()       { append_to_activity_log "PRINT        $*"; }
list_log()        { append_to_activity_log "LIST         $*"; }
encrypt_log()     { append_to_activity_log "ENCRYPT      $*"; }
decrypt_log()     { append_to_activity_log "DECRYPT      $*"; }
cleanup_log()     { append_to_activity_log "CLEANUP      $*"; }

create_echo()     { echo "[${GN}${BD}!${RS}] ${GN}${BD}CREATE${RS}: $*"; }
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
sanity_check_args
main
exit 0
