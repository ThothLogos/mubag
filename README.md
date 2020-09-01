# MuBAG

A simple wrapper around `gpg --symmetric` encryption functionality and `zip` to assist in managing encrypted archives of arbitrary files. Adds some sanity/safety checks, paranoia-inspired functionality and logging. The acronym behind the original name was rendered irrelevant courtesy of scope creep.

## About

During a personal account migration and backup-makeover I was maintaining an encrypted backup of various important bits. The encrypted backup was being updated as I completed each piece of the migration process for various services over a course of several days. The tedium of managing these backups began to wear on me; not only running the commands themselves but keeping track of what was done and when. The need for some automation and logging presented itself.

Traditionally avoiding developing in Bash when possible, this time it seemed most appropriate for initial goals. Those goals expanded and a quick script turned into a bit of Bash spaghetti. Next thing I know I'm hacking together half-ass unit tests manually in a language I never particularly liked. The real prize is the zero friends I made along the way.

## Test Script

This repo includes a partner script `run_tests.sh` which is primarily used as a development tool for `mubag.sh`'s functionality, but can serve as a good confirmation that this script will run successfully on your system (success may vary based on older versions of Bash or GPG installs).

## How to Use

Detailed instructions coming soon? For now check the `--help` and `--examples` options. Please note that this tool was built for *personal* backup purposes, I use it to keep redundant copies of important files that are only relevant to my own life without worrying about them being easily accesible. Do not assume this tool is in any way sufficient or robust enough for
anything more. It's probably as safe as `gpg` is but it was designed with convenience in mind and I cannot guarantee it is perfectly reliable.




