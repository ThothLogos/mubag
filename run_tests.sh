#!/bin/bash

TESTDIR="test_temp"



source config.sh

display_usage() { echo "Usage: $(basename $0)"; }

main() {
  setup



  #shutdown
}

setup() {
  setup_echo "Setting up test environment... "
  if ! [ -d $TESTDIR ];then mkdir $TESTDIR;fi
  pushd $TESTDIR > /dev/null
  for c in {a..c};do
    local size=$(( 4096 + RANDOM % 60000 ))
    generate_text_file "$c.txt" $size
    if ! [[ $? -eq 0 ]];then err_echo "Unable to generate test files, aborting.";fi
  done
  ok_echo
  popd > /dev/null
  setup_echo "Running tests... \\n"
  
  do_test "test_create_new_archive"
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
  $testname
  if [[ $? -eq 0 ]];then
    ok_echo
  else
    fail_echo
  fi
}

test_create_new_archive() {
  ./mubag.sh --test thisisonlyatest -o $TESTDIR/test.zip -a $TESTDIR/a.txt
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




