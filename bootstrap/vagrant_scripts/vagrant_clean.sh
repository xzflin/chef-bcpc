#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

cd $REPO_ROOT/bootstrap/vagrant_scripts && vagrant destroy -f