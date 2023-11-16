#!/bin/bash

source env.sh

echo "{message:\"Press Ctrl-C to stop recording...\"}"
arecord -f cd -t wav $CREAM_ARCHIVE_DIRECTORY/`date +%Y-%m-%d@%H:%M:%S.%N.wav` -d 0

