#!/bin/bash

TESTDIR="test_temp"
TESTPASS="gogo"
source config.sh

display_usage() {
  echo -e "
    Usage: run_tests.sh [OPTIONS]

  -d, --debug                       Dump test failure output to STDOUT
  -f, --fail-early                  Stop after the first failure

  -h, --help                        This screen
  "
}

err_echo()      { echo "[${RD}${BD}!!!${RS}] ${RD}${BD}ERROR${RS} [${RD}${BD}!!!${RS}] - $*"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) display_usage; exit 0;;
    -d|--debug) debug=true; shift 1;;
    -f|--fail-early) failearly=true; shift 1;;
    *) err_echo "Unknown command: $1" >&2; exit 1;;
  esac
done

main() {
  setup
  do_test "fail_create_new_archive_with_invalid_cipher_algo"
  do_test "test_create_new_archive_default_name_when_backup_missing"
  do_test "test_create_new_archive_default_when_backup_is_a_directory"
  do_test "test_create_new_archive"
  do_test "fail_decrypt_wrong_passphrase"
  do_test "test_decrypt_and_warn"
  do_test "fail_add_existing_file_in_archive"
  do_test "test_add_files_to_archive"
  do_test "test_list_files_in_archive"
  do_test "test_print_file_from_archive"
  do_test "fail_extract_file_not_found_in_archive"
  do_test "test_extract_file_from_archive"
  do_test "fail_edit_file_not_found_in_archive"
  do_test "test_edit_file_within_archive"
  do_test "fail_update_unchanged_file"
  do_test "fail_update_file_not_found_in_archive"
  do_test "test_update_file_within_archive"
  do_test "test_remove_file_from_archive"
  do_test "fail_to_find_file_in_archive"
  report_results
  shutdown
  exit 0
}

setup() {
  setup_echo "\nSetting up test environment... "
  testcount=0; passes=0; fails=0;
  if ! [ -d $TESTDIR ];then mkdir $TESTDIR;fi
  pushd $TESTDIR > /dev/null
  for c in {A..C};do
    local size=$(( 4096 + RANDOM % 4096 ))
    generate_text_file "$c.txt" $size
    if ! [[ $? -eq 0 ]];then err_echo "Unable to generate test files, aborting.";shutdown;exit 1;fi
  done
  ok_echo
  popd > /dev/null
  setup_echo "\n\tRunning tests...\n\n"
}

shutdown() {
  rm ./$TESTDIR/*
  rmdir $TESTDIR
}

generate_text_file() {
  filename=$1
  size_bytes=$2
  echo $(base64 /dev/urandom | head -c $size_bytes) > $filename
}

do_test() {
  local testname=$1
  test_echo $testname
  local ret=$($testname)
  testcount=$((testcount+1))
  if [[ $ret == "0" ]];then
    ok_echo
    passes=$((passes+1))
  else
    fail_echo
    [ $debug ] && echo -e "\tTest return: $ret\n\n"
    fails=$((fails+1))
    [ $failearly ] && report_results && exit 1
  fi
}

report_results() {
  if [[ $passes == $testcount ]];then
    echo -e "\n\t${GN}${BD}SUCCESS${RS} - All tests passed! $passes of $testcount\n"
  else
    echo -e "\n\t${RD}${BD}FAILURE${RS} - Some tests failed. $passes of $testcount pass," \
      "$fails failed\n"
  fi
}

fail_create_new_archive_with_invalid_cipher_algo() {
  local match="FAKECIPHER is not supported by the installed version of gpg"
  local out=$(./mubag.sh -v --test $TESTPASS --new -a $TESTDIR/A.txt --algo FAKECIPHER)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_create_new_archive_default_name_when_backup_missing() {
  local ma="defaulting to datestamp"
  local mb="Success, archive creation complete"
  local out=$(./mubag.sh -v --test $TESTPASS --new -a $TESTDIR/A.txt)
  local archive=$(echo "$out" | grep "$mb" | awk -F '/' '{print $NF}')
  [[ -f $archive.gpg ]] && rm $archive.gpg
  if [[ $out =~ $ma ]] && [[ $out =~ $mb ]];then
    echo "0"
  else
    echo "1"
    [ $debug ] && echo -e "$out"
  fi
}

test_create_new_archive_default_when_backup_is_a_directory() {
  local ma="defaulting to datestamp"
  local mb="Success, archive creation complete $TESTDIR"
  local out=$(./mubag.sh -v --test $TESTPASS --new -a $TESTDIR/A.txt -b $TESTDIR)
  local archive=$(echo "$out" | grep "$mb" | awk '{print $NF}')
  [[ -f $archive.gpg ]] && rm $archive.gpg
  if [[ $out =~ $ma ]] && [[ $out =~ $mb ]];then
    echo "0"
  else
    echo "1"
    [ $debug ] && echo -e "$out"
  fi
}

test_create_new_archive() {
  local match="Success, archive creation complete"
  local out=$(./mubag.sh -v --test $TESTPASS --new -b $TESTDIR/test.zip -a $TESTDIR/A.txt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_decrypt_wrong_passphrase() {
  local match="GPG decryption failed due to incorrect passphrase"
  local out=$(./mubag.sh -v --test WRONGPASS -b $TESTDIR/test.zip.gpg --decrypt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_decrypt_and_warn() {
  local match="You have just decrypted"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg --decrypt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_add_existing_file_in_archive() {
  local match="already exists inside"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -a $TESTDIR/A.txt)
  [ -f A.txt ] && rm A.txt
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_add_files_to_archive() {
  local passing=false
  local match="archive update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -a $TESTDIR/B.txt)
  if [[ $out =~ $match ]];then passing=true;else echo "1";[ $debug ] && echo -e "$out";fi
  local out=$(./mubag.sh -v --test $TESTPASS --backup=$TESTDIR/test.zip.gpg --add=$TESTDIR/C.txt)
  if [ $passing ] && [[ $out =~ $match ]];then
    echo "0"
  else
    echo "1"
    [ $debug ] && echo -e "$out"
  fi
}

test_list_files_in_archive() {
  local match="CRC-32"
  local out=$(./mubag.sh -v --test $TESTPASS --backup $TESTDIR/test.zip.gpg --list)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_print_file_from_archive() {
  local match="END OUTPUT"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -p A.txt 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_extract_file_not_found_in_archive() {
  local match="DNE.void not found within"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x DNE.void 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_extract_file_from_archive() {
  local match="recovered from archive"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x B.txt 2>&1)
  if [ -f B.txt ];then rm B.txt;fi
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_edit_file_not_found_in_archive() {
  local match="DNE.void not found"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -e DNE.void)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_edit_file_within_archive() {
  local match="archive update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -e C.txt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_update_unchanged_file() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x A.txt >/dev/null
  local match="The file A.txt in the archive is identical"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -u A.txt 2>&1)
  if [ -f A.txt ];then rm A.txt;fi
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_update_file_not_found_in_archive() {
  local match="DNE.void not found in"
  touch DNE.void
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -u DNE.void 2>&1)
  [ -f DNE.void ] && rm DNE.void
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_update_file_within_archive() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x A.txt >/dev/null
  echo "Ch-ch-ch-ch-changes" >> A.txt
  local match="archive update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -u A.txt 2>&1)
  if [ -f A.txt ];then rm A.txt;fi
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_remove_file_from_archive() {
  local match="B.txt removed from archive"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -r B.txt 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

fail_to_find_file_in_archive() {
  local match="DNE.void not found in"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -p DNE.void 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";[ $debug ] && echo -e "$out";fi
}

test_echo()     { echo -ne "[${YL}TEST${RS}] Running $1 ... "; }
setup_echo()    { echo -ne "$*"; }
shutdown_echo() { echo "$*"; }
warn_echo()     { echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS} [${YL}${BD}!!!${RS}] - $*";    }
ok_echo()       { echo "${GN}OK${RS}"; }
fail_echo()     { echo "${RD}${BD}FAIL${RS}"; }

main
