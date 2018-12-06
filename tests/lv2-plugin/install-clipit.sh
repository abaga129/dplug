#!/bin/bash
dub --root=../../examples/clipit -c LV2 --combined
sudo rm -rf /usr/lib/lv2/clipit
sudo mkdir /usr/lib/lv2/clipit
sudo cp ../../examples/clipit/libclipit.so /usr/lib/lv2/clipit/libclipit.so
sudo cp manifest-clipit.ttl /usr/lib/lv2/clipit/manifest.ttl
sudo cp clipit.ttl /usr/lib/lv2/clipit/clipit.ttl