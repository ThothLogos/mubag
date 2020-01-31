#!/bin/bash

# TODO: Complete --decrypt
# TODO: Complete --extract
# TODO: Complete --edit/-e functionality using extract functionality
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

    --backup=*) BACKUP="${1#*=}"; shift 1;;
    --out=*) out=true; OUTFILE="${1#*=}"; shift 1;;
    --add=*) add=true; FILE="${1#*=}"; shift 1;;
    --print=*) prnt=true; FILE="${1#*=}"; shift 1;;
    --extract=*) extract=true; FILE="${1#*=}"; shift 1;;
    --edit=*) edit=true; FILE="${1#*=}"; shift 1;;
    
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
      if ! [ -f $FILE ];then echo "${RD}${BD}ERROR${RS}: -add FILE $FILE not found!";exit 1;fi
      create_or_update_archive $FILE $OUTFILE
      encrypt_zip $OUTFILE
      secure_remove_file $OUTFILE
    fi
  elif [ $add ] && [ $backup ];then # update existing archive
    if ! [ -f $FILE ];then echo "${RD}${BD}ERROR${RS}: -add FILE $FILE not found!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    create_or_update_archive $FILE $BACKUP
    encrypt_zip $BACKUP
    secure_remove_file $BACKUP
  elif [ $decrypt ];then # decrypt an existing archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to edit within!";exit 1;fi
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
  elif [ $edit ];then # edit contents of text file within existing archive
    if ! [ $backup ];then echo "${RD}${BD}ERROR${RS}: must set --backup to edit within!";exit 1;fi
    decrypt_zip $BACKUP
    BACKUP=${BACKUP%????} # chop off .gpg
    edit_file_from_archive $FILE $BACKUP
    encrypt_zip $BACKUP
    secure_remove_file $BACKUP

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
    [ $verbose ] && echo "${GN}${BD}ADD${RS}: archive creation successful"
  elif [[ $? -eq 12 ]];then
    echo "${GN}${BD}ADD${RS} ${YL}${BD}NO-OP${RS}: zip update failed 'nothing to do'?"
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip; fi
    exit 1
  else
    echo "${GN}${BD}ADD${RS} ${RD}${BD}ERROR${RS}: unknown zip creation or update error!"
    if [ -f $unencrypted_zip ];then secure_remove_file $unencrypted_zip; fi
    exit 1
  fi
}

print_file_from_archive() {
  [ $verbose ] && echo "${MG}${BD}PRINT${RS}: routing $FILE to STDOUT from ${BACKUP%????}"
  echo "${WH}${BD}--- BEGIN OUTPUT ---${RS}"
  unzip -p ${BACKUP%????} $(basename $FILE)
  echo "${WH}${BD}---  END OUTPUT  ---${RS}"
}

list_archive_contents() {
  unzip -l $1
  if ! [[ $? -eq 0 ]];then
    echo "${RD}${BD}ERROR${RS}: unknown unzip error when attempting --list!"
  fi
}

decrypt_zip() {
  [ $verbose ] && echo "${CY}${BD}DECRYPT${RS} BEGIN: attempting gpg decrypt"
  local unencrypted_zip=${1%????}
  gpg -q --no-symkey-cache -o $unencrypted_zip --decrypt $1
  if [[ $? -eq 0 ]]; then
    echo "${CY}${BD}DECRYPT${RS}: successful"
  else
    echo "${CY}${BD}DECRYPT${RS} ${RD}${BD}FAIL${RS}: gpg decryption error. Exiting,"
    if [[ -f $unencrypted_zip ]]; then secure_remove_file $unencrypted_zip; fi
    exit 1
  fi
}

encrypt_zip() {
  [ $verbose ] && echo "${BL}${BD}ENCRYPT${RS} BEGIN: attempting gpg encrypt with $ALGO"
  local unencrypted_zip=$1
  gpg -q --no-symkey-cache --cipher-algo $ALGO --symmetric $unencrypted_zip
  if [[ $? -eq 0 ]]; then
    echo "${BL}${BD}ENCRYPT${RS}: successful"
  else
    echo "${BL}${BD}ENCRYPT${RS} ${RD}${BD}ERROR${RS}: gpg encryption error. Exiting,"
    if [[ -f $unencrypted_zip ]]; then secure_remove_file $unencrypted_zip; fi
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
