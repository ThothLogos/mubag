# MuBAG

A simple wrapper around `gpg --symmetric` encryption functionality and `zip` to assist in managing encrypted backups of arbitrary files. Adds some extra sanity/safety checks, paranoia-inspired functionality and logging.

## About

During a personal account migration and backup-makeover I was maintaining an encrypted backup of various important bits, updating it as I completed each migration of various services. The tedium of managing these backups began to wear on me; not only running the commands themselves but keeping track of what was done and when. The need for some automation and logging presented itself.

Traditionally avoiding developing in Bash when possible, this time it seemed most appropriate for initial goals. Those goals expanded and a quick  script turned into a bit of Bash spaghetti. Next thing I know I'm hacking together half-ass unit tests manually in a language I never particularly liked. The real prize is the zero friends I made along the way.

## Test Script

This repo includes a partner script `run_tests.sh` which is primarily used as a development tool for `mubag.sh`'s functionality, but can serve as a good confirmation that this script will run successfully on your system (success may vary based on older versions of Bash or GPG installs).

## How to Use

WIP




