#!/bin/sh

while sleep 5
do
    cowsay "Sync'ing files from BIN: mix-j"
    rsync -azP --delete ibi@mix-j.local:"/opt/austrianAudio/var/CREAM/" ./
done


