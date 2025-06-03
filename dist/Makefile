
all:	wavesurfer-deps-local
	dpkg-deb --build aa-cream_1.0-1
	mv aa-cream_1.0-1.deb aa-cream_1.0-1-`uname -m`-`uname -s`-`uname -n`.deb

wavesurfer-deps-npm:
	npm install --save wavesurfer.js 

wavesurfer-deps-local:
	wget https://unpkg.com/wavesurfer.js@7/dist/wavesurfer.min.js -O /opt/austrianAudio/var/static/wavesurfer.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/regions.min.js -O /opt/austrianAudio/var/static/regions.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/envelope.min.js -O /opt/austrianAudio/var/static/envelope.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/hover.min.js -O /opt/austrianAudio/var/static/hover.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/minimap.min.js -O /opt/austrianAudio/var/static/minimap.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/spectrogram.min.js -O /opt/austrianAudio/var/static/spectrogram.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/timeline.min.js -O /opt/austrianAudio/var/static/timelline.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/zoom.min.js -O /opt/austrianAudio/var/static/zoom.min.js
 
wavesurfer-deps-wget-deb:
	wget https://unpkg.com/wavesurfer.js@7/dist/wavesurfer.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/wavesurfer.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/regions.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/regions.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/envelope.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/envelope.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/hover.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/hover.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/minimap.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/minimap.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/spectrogram.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/spectrogram.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/timeline.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/timeline.min.js
	wget https://unpkg.com/wavesurfer.js@7/dist/plugins/zoom.min.js -O aa-cream_1.0-1/opt/austrianAudio/var/static/zoom.min.js

clean:
	 rm -rf *.deb 
