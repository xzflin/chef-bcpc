#!/bin/bash

# power off and unregister VMs
for i in bcpc-{bootstrap,vm{1..3}} ; do
  $VBM controlvm $i poweroff
  $VBM unregistervm $i --delete
done 2>/dev/null

# magic sleep since VirtualBox tends to take a few seconds to release
# locks on VM files after shutdown and unregistration
sleep 10

if [[ ! -z $BCPC_VM_DIR ]]; then
  cd $BCPC_VM_DIR
  for i in bcpc-{bootstrap,vm{1..3}} ; do
    rm -rf $i
  done 2>/dev/null
fi
