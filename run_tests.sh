#!/bin/bash

TESTDIR="test_temp"
TESTPASS="gogo"
source config.sh

main() {
  setup
  do_test "test_create_new_archive"
  do_test "test_add_files_to_archive"
  do_test "test_list_files_in_archive"
  do_test "test_print_file_from_archive"
  do_test "test_extract_file_from_archive"
  do_test "test_edit_file_within_archive"
  do_test "test_failure_updating_unchanged_file"
  do_test "test_update_file_within_archive"
  do_test "test_remove_file_from_archive"
  do_test "test_failure_to_find_file_in_archive"
  shutdown
}

setup() {
  setup_echo "Setting up test environment... "
  if ! [ -d $TESTDIR ];then mkdir $TESTDIR;fi
  pushd $TESTDIR > /dev/null
  for c in {A..C};do
    local size=$(( 4096 + RANDOM % 4096 ))
    generate_text_file "$c.txt" $size
    if ! [[ $? -eq 0 ]];then err_echo "Unable to generate test files, aborting.";shutdown;exit 1;fi
  done
  ok_echo
  popd > /dev/null
  setup_echo "Running tests... \\n"
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
  if [[ $ret == "0" ]];then
    ok_echo
  else
    fail_echo
  fi
  sleep 0.1
}

test_create_new_archive() {
  local match="archive creation/update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -o $TESTDIR/test.zip -a $TESTDIR/A.txt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_add_files_to_archive() {
  local passing=false
  local match="archive creation/update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -a $TESTDIR/B.txt)
  if [[ $out =~ $match ]];then passing=true;else echo "1";fi
  local out=$(./mubag.sh -v --test $TESTPASS --backup=$TESTDIR/test.zip.gpg --add=$TESTDIR/C.txt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_list_files_in_archive() {
  local match="CRC-32"
  local out=$(./mubag.sh -v --test $TESTPASS --backup $TESTDIR/test.zip.gpg --list)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_print_file_from_archive() {
  local match="END OUTPUT"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -p A.txt 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_extract_file_from_archive() {
  local match="recovered from archive"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x B.txt 2>&1)
  if [ -f B.txt ];then rm B.txt;fi
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_edit_file_within_archive() {
  local match="archive creation/update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -e C.txt)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_failure_updating_unchanged_file() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x A.txt >/dev/null
  local match="The file A.txt in the archive is identical"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -u A.txt 2>&1)
  if [ -f A.txt ];then rm A.txt;fi
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_update_file_within_archive() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x A.txt >/dev/null
  echo "Ch-ch-ch-ch-changes" >> A.txt
  local match="archive creation/update complete"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -u A.txt 2>&1)
  if [ -f A.txt ];then rm A.txt;fi
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_remove_file_from_archive() {
  local match="B.txt removed from archive"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -r B.txt 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_failure_to_find_file_in_archive() {
  local match="DNE.void not found in"
  local out=$(./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -p DNE.void 2>&1)
  if [[ $out =~ $match ]];then echo "0";else echo "1";fi
}

test_echo()     { echo -ne "[${YL}TEST${RS}] Running $1 ... "; }
setup_echo()    { echo -ne "$*"; }
shutdown_echo() { echo "$*"; }
warn_echo()     { echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS} [${YL}${BD}!!!${RS}] - $*";    }
err_echo()      { echo "[${RD}${BD}!!!${RS}] ${RD}${BD}ERROR${RS} [${RD}${BD}!!!${RS}] - $*"; }
ok_echo()       { echo "${GN}OK${RS}"; }
fail_echo()     { echo "${RD}${BD}FAIL${RS}"; }

main
exit 0;

