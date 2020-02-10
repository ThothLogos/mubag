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
  #shutdown
}

setup() {
  setup_echo "Setting up test environment... "
  if ! [ -d $TESTDIR ];then mkdir $TESTDIR;fi
  pushd $TESTDIR > /dev/null
  for c in {A..C};do
    local size=$(( 4096 + RANDOM % 4096 ))
    generate_text_file "$c.txt" $size
    if ! [[ $? -eq 0 ]];then err_echo "Unable to generate test files, aborting.";fi
  done
  ok_echo
  popd > /dev/null
  setup_echo "Running tests... \\n"
}

shutdown() {
  rm ./$TESTDIR/*
  rmdir $TESTDIR
  rm activity.log
}

generate_text_file() {
  filename=$1
  size_bytes=$2
  echo $(base64 /dev/urandom | head -c $size_bytes) > $filename
}

do_test() {
  local testname=$1
  test_echo $testname
  $testname
  if [[ $? -eq 0 ]];then
    ok_echo
  else
    fail_echo
  fi
  sleep 0.1
}

test_create_new_archive() {
  ./mubag.sh -v --test $TESTPASS -o $TESTDIR/test.zip -a $TESTDIR/A.txt #>/dev/null
}

test_add_files_to_archive() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -a $TESTDIR/B.txt #>/dev/null
  ./mubag.sh -v --test $TESTPASS --backup=$TESTDIR/test.zip.gpg --add=$TESTDIR/C.txt #>/dev/null
}

test_list_files_in_archive() {
  ./mubag.sh -v --test $TESTPASS --backup $TESTDIR/test.zip.gpg --list #>/dev/null
}

test_print_file_from_archive() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -p A.txt
}

test_extract_file_from_archive() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -x B.txt
  rm B.txt
}

test_edit_file_within_archive() {
  ./mubag.sh -v --test $TESTPASS -b $TESTDIR/test.zip.gpg -e C.txt
}



test_echo()     { echo -ne "[${YL}TEST${RS}] Running \"$1\" ... "; }
setup_echo()    { echo -ne "$*"; }
shutdown_echo() { echo "$*"; }
warn_echo()     { echo "[${YL}${BD}!!!${RS}] ${BD}WARNING${RS} [${YL}${BD}!!!${RS}] - $*";    }
err_echo()      { echo "[${RD}${BD}!!!${RS}] ${RD}${BD}ERROR${RS} [${RD}${BD}!!!${RS}] - $*"; }
ok_echo()       { echo "${GN}OK${RS}"; }
fail_echo()     { echo "${RD}${BD}FAIL${RS}"; }

main
exit 0




