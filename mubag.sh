#!/bin/bash

# TODO: Complete --edit/-e functionality using extract functionality
# TODO: --remove
# TODO: --print needs to check presence before failure
# TODO: Trap CTRL-C to attempt cleanups there as well
# TODO: (?) Perhaps offer option to bail out of rm'ing and let them handle secure deletion manually?
# TODO: What happens when when --print or edit a non-ASCII file? :) Can we detect that early?
# TODO: Experiment: pretty sure I have some redundant RST's on the color tags, prob works like NM

source config.sh

display_usage() {
  echo -e "
Usage: $(basename $0) [OPTION] [FILE] ( -o [OUTFILE NAME] || -b [EXISTING BACKUP ARCHIVE] )

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

if [ "$#" -lt 1 ]; then
  echo "${RD}${BD}ERROR${RS}: incorrect number of args"
  display_usage
  exit 1
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) display_usage; exit 0;;
    -ex|--examples) display_examples; exit 0;;
    -v|--verbose) verbose=true; shift 1;; 

    -b|--backup) backup=true;BACKUP="$2"; shift 2;;
    -o|--out) out=true; OUTFILE="$2"; shift 2;;

    -l|--list) list=true; shift 1;;
    -d|--decrypt) decrypt=true; shift 1;;

    -a|--add) add=true; FILE="$2"; shift 2;;
    -p|--print) prnt=true; FILE="$2"; shift 2;;
    -x|--extract) extract=true; FILE="$2"; shift 2;;
    -e|--edit) edit=true; FILE="$2"; shift 2;;
    -u|--update) update=true; FILE="$2"; shift 2;;

    --backup=*) BACKUP="${1#*=}"; shift 1;;
    --out=*) out=true; OUTFILE="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --print=*) prnt=true; FILE="${1#*=}"; shift 1;;
    --extract=*) extract=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    --update=*) update=true; FILE="${1#*=}"; shift 1;;
    
    -*) echo -e "${RD}${BD}ERROR${RS}: unknown option $1" >&2; display_usage; exit 1;;
    *) handle_argument "$1"; shift 1;;
  esac
done

if [ $backup ];then
  if ! [ -f $BACKUP ];then
    echo "${RD}${BD}ERROR${RS}: the --backup FILE you specified cannot be found";exit 1
  elif ! [[ $BACKUP == *.gpg ]];then
    echo "${RD}${BD}ERROR${RS}: please specify a --backup FILE that ends in .gpg";exit 1
  fi
fi

main() {
  if [ $add ] && ! [ $backup ]; then # create new archive
    if ! [ $out ];then
      echo "${RD}${BD}ERROR${RS}: --add requires either --backup FILE or --out FILE specified," \
        "if you're trying to update an existing backup use -b/--backup, if you're trying to start" \
        "a new backup, use -o/--out to specify the output file's name and location."
      exit 1
    else
      if ! [ -f $FILE ];then echo "${RD}${BD}ERROR${RS}: --add FILE $FILE not found!";exit 1;fi
      create_or_update_archive $FILE $OUTFILE
      encrypt_zip $OUTFILE
      secure_remove_file $OUTFILE
    fi
  elif [ $add ] && [ $backup ];then # update existing archive
    if ! [ -f $FILE ];then echo "${RD}${BD}ERROR${RS}: --add FILE $FILE not found!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    local ret=$(check_file_existence $FILE $BACKUP)
    if [[ $ret == "0" ]];then
      secure_remove_file $BACKUP
      echo "${RD}${BD}ERROR${RS}: file $FILE already exists inside $BACKUP.gpg, if you want to" \
        "update the existing copy inside the archive, use --update."
      exit 1
    fi
    create_or_update_archive $FILE $BACKUP
    encrypt_zip $BACKUP
    secure_remove_file $BACKUP
  elif [ $decrypt ];then # decrypt an existing archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to edit within!";exit 1;fi
    decrypt_zip $BACKUP
    if [[ $? -eq 0 ]];then
      echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS}: You have just decrypted your backup archive" \
        "and it is exposed on the file system. Please be aware of the risks!"
    fi
  elif [ $list ];then # list contents of existing archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to list from!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    list_archive_contents $BACKUP
    secure_remove_file $BACKUP
  elif [ $prnt ];then # print contents of file within existing archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to print from!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    print_file_from_archive $FILE $BACKUP
    secure_remove_file $BACKUP
  elif [ $extract ];then # extract a specific file from the archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to extract from!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    extract_file_from_archive $FILE $BACKUP
    secure_remove_file $BACKUP
  elif [ $update ];then
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to update files!";exit 1;fi
    if ! [ -f $FILE ];then echo "${RD}${BD}ERROR${RS}: --update FILE $FILE not found!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    local ret=$(check_file_existence $FILE $BACKUP)
    if ! [[ $ret == "0" ]];then
      secure_remove_file $BACKUP
      echo "${RD}${BD}ERROR${RS}: $FILE not found in $BACKUP.gpg, can't --update. If you wanted to " \
        "add that file instead try: $(basename $0) --add $FILE --backup $BACKUP"
      exit 1
    fi
    create_or_update_archive $FILE $BACKUP
    encrypt_zip $BACKUP
    secure_remove_file $BACKUP
  elif [ $edit ];then # edit contents of text file within existing archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to edit within!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    edit_file_from_archive $FILE $BACKUP
    encrypt_zip $BACKUP
    secure_remove_file $BACKUP
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
  [ $verbose ] && echo "${MG}${BD}EXTRACT${RS} BEGIN: attempting to extract $FILE from $2"
  local unencrypted_zip=$2
  unzip -j $unencrypted_zip $FILE
  if ! [[ $? -eq 0 ]];then
    if ! [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip;fi
    echo "${MG}${BD}EXTRACT ${RD}ERROR${RS}: file $FILE not found within $unencrypted_zip, aborting"
    exit 1
  else
    echo "${MG}${BD}EXTRACT${RS}: success, $FILE recovered from archive"
  fi
}

edit_file_from_archive() {
  local unencrypted_zip=$2
}

create_or_update_archive() {
  local unencrypted_zip=$2
  if [ $out ] && [[ $OUTFILE == "" ]];then
    unencrypted_zip=$DATE.zip
    OUTFILE=$DATE.zip
    echo "${GN}${BD}ADD${RS}: --out was blank! using timestamp as default: $OUTFILE"
  fi
  if [ $OUTFILE ] && [ -f $OUTFILE ];then
    echo "${RD}${BD}ERROR${RS}: --out $OUTFILE would over-write an existing file! If you want" \
      "to update an existing backup, use --backup instead of --out. Otherwise, pick a different" \
      "file location/name or remove the blocking file manually and re-run. Oopsie prevention."
    exit 1
  fi
  zip -urj $unencrypted_zip $FILE # -rj abandon directory structure of files added
  if [[ $? -eq 0 ]];then
    [ $verbose ] && echo "${GN}${BD}UPDATE${RS}: archive creation or update successful"
  elif [[ $? -eq 12 ]];then
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip; fi
    echo "${GN}${BD}UPDATE${RS} ${YL}${BD}NO-OP${RS}: zip update failed 'nothing to do'?"
    exit 1
  else
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip; fi
    echo "${GN}${BD}UPDATE${RS} ${RD}${BD}ERROR${RS}: unknown zip creation or update error!"
    exit 1
  fi
}

print_file_from_archive() {
  [ $verbose ] && echo "${WH}${BD}PRINT${RS}: routing $FILE to STDOUT from ${BACKUP%????}"
  echo "${WH}${BD}--- BEGIN OUTPUT ---${RS}"
  unzip -p ${BACKUP%????} $(basename $FILE)
  echo "${WH}${BD}---  END OUTPUT  ---${RS}"
}

list_archive_contents() {
  unzip -v $1
  if ! [[ $? -eq 0 ]];then
    echo "${RD}${BD}ERROR${RS}: unknown unzip error when attempting --list!"
  fi
}

decrypt_zip() {
  [ $verbose ] && echo "${CY}${BD}DECRYPT${RS} BEGIN: attempting gpg decrypt"
  local unencrypted_zip=${1%????}
  gpg -q --no-symkey-cache -o $unencrypted_zip --decrypt $1
  if [[ $? -eq 0 ]]; then
    echo "${CY}${BD}DECRYPT${RS}: success, $unencrypted_zip has been restored"
  else
    if [[ -f $unencrypted_zip ]]; then secure_remove_file $unencrypted_zip; fi
    echo "${CY}${BD}DECRYPT${RS} ${RD}${BD}FAIL${RS}: gpg decryption error. Exiting,"
    exit 1
  fi
}

encrypt_zip() {
  [ $verbose ] && echo "${BL}${BD}ENCRYPT${RS} BEGIN: attempting gpg encrypt"
  local unencrypted_zip=$1
  if [[ $add || $update ]];then
    # --yes during add/update, user is explicitly running a write command already
    gpg -q --yes --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  else # in other situations we may want to confirm over-writing if it crops up
    gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  fi
  if [[ $? -eq 0 ]]; then
    echo "${BL}${BD}ENCRYPT${RS}: success, $unencrypted_zip.gpg protected by $ALGO"
  else
    if [[ -f $unencrypted_zip ]]; then secure_remove_file $unencrypted_zip; fi
    echo "${BL}${BD}ENCRYPT${RS} ${RD}${BD}ERROR${RS}: gpg encryption error! Exiting."
    exit 1
  fi
}

secure_remove_file() {
  if command -v srm >/dev/null; then
    [[ $verbose ]] && echo "${YL}${BD}CLEANUP${RS}: srm exists on system, target $1"
    srm -zv $1 # -z zero-out, -v verbose (srm can be slow, shows progress)
    if [[ $? -eq 0 ]]; then
      echo "${YL}${BD}CLEANUP${RS}: success, srm of $1 complete - decrypted archive is securely purged"
    else
      echo "${YL}${BD}CLEANUP${RS} ${RD}${BD}FAIL${RS}: srm failed!"
      unsecure_remove_file $1
      exit 1
    fi
  elif command -v shred >/dev/null; then # prioritize secure removal over simple rm, if avail
    [[ $verbose ]] && echo "${YL}${BD}CLEANUP${RS}: shred exists on system, shredding $1"
    shred -uz $1 # -u delete file, -z zero-out
    if [[ $? -eq 0 ]]; then
      echo "${YL}${BD}CLEANUP${RS}: success, shred of $1 complete - decrypted archive is securely purged"
    else
      echo "${YL}${BD}CLEANUP${RS} ${RD}${BD}FAIL${RS}: shred failed!"
      unsecure_remove_file $1
      exit 1
    fi
  else # resort to rm'ing
    echo "${YL}${BD}CLEANUP${RS} ${RD}FALLBACK${RS}: secure file erasure not found, resorting to rm"
    unsecure_remove_file $1
  fi
}

unsecure_remove_file() {
  rm -f $1
  if [[ $? -eq 0 ]]; then
    echo "${YL}${BD}CLEANUP${RS}: rm of $1 complete - ${RD}${BD}WARNING${RS} decrypted" \
      "archive may still be recoverable!"
  else
    echo "${YL}${BD}CLEANUP${RS} ${RD}${BD}FAIL${RS}: rm failed!"
    # TODO: what else can be done, just warn harder? why might this fail?
    exit 1
  fi
}

main
exit 0
