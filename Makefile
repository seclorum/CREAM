BUILD_ARCHITECTURE := $(shell uname -m)
CREAM_APP_TARGET = cream.${BUILD_ARCHITECTURE}
CREAM_DIST_INST_DIR = dist/aa-cream_1.0-1/opt/austrianAudio/bin/
LUA_SRC_FILES = ./main.lua ./config.lua ./cream.lua ./buildDate.lua ./mixer.lua ./devices.lua ./httpserver.lua ./util/geocalcs.lua ./util/time.lua ./util/tools.lua ./util/scantest.lua ./util/gpxmaker.lua ./util/lua_enumerable.lua ./util/average.lua ./util/filesystem.lua ./util/mobdebug.lua ./util/dateparse.lua ./util/debug.lua ./util/Logger.lua ./util/persistence.lua ./util/geocoords.lua ./util/noobhub.lua ./util/environment_debug.lua 


ifeq ($(BUILD_ARCHITECTURE), armv7l)
${CREAM_APP_TARGET}:
	dist/local/bin/luastatic ${LUA_SRC_FILES} /usr/lib/arm-linux-gnueabihf/libluajit-5.1.a /usr/lib/arm-linux-gnueabihf/liblua5.1-cjson.a -I/usr/include/lua5.1  "-o ${CREAM_APP_TARGET}"
endif

ifeq ($(BUILD_ARCHITECTURE), armv6l)
${CREAM_APP_TARGET}:
	dist/local/bin/luastatic ${LUA_SRC_FILES} /usr/lib/arm-linux-gnueabihf/libluajit-5.1.a /usr/lib/arm-linux-gnueabihf/liblua5.1-cjson.a -I/usr/include/lua5.1  "-o ${CREAM_APP_TARGET}"
endif

ifeq ($(BUILD_ARCHITECTURE), x86_64)
${CREAM_APP_TARGET}:
	dist/local/bin/luastatic ${LUA_SRC_FILES} /usr/lib/x86_64-linux-gnu/libluajit-5.1.a /usr/lib/x86_64-linux-gnu/liblua5.1-cjson.a -I/usr/include/lua5.1  "-o ${CREAM_APP_TARGET}"
endif

builddate:
	echo "return \"`date`\"" > buildDate.lua

run:
	luajit main.lua

#test:
#	luajit test.lua
#

wait:
	while inotifywait -e close_write  .; do pkill luajit ; luajit main.lua &  done

reqs:
	sudo apt-get install -y luajit luarocks git build-essential libssl-dev libluajit-5.1-dev lua-cjson-dev sysv-rc-conf meson libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

reqs-turbo:
	PREFIX=`pwd`/dist/aa-cream_1.0-1/opt/austrianAudio/ make -C third/turbo install

reqs-lua:
	#luarocks install turbo 
	#luarocks install ffi --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	#luarocks install cffi --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	luarocks install ljsyscall --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	luarocks install cffi-lua --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	luarocks install lgi --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	luarocks install luajit-ffi-loader --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	luarocks install luaposix --tree=dist/aa-cream_1.0-1/opt/austrianAudio/
	luarocks install luastatic --tree=dist/local
	luarocks path --tree=dist/aa-cream_1.0-1/opt/austrianAudio/

trace:	./cream.armv7l
	strace -r -s 1024 -o /opt/austrianAudio/var/CREAM/`date +"%Y%m%d-%H%M%S"`-app_strace.log.txt ./cream.armv7l

distro:
	cp -rfvp ${CREAM_APP_TARGET} ${CREAM_DIST_INST_DIR}
	make -C dist/
	ls -alF dist/*.deb

clean:
	make -C dist/ clean
	rm -rf *.luastatic.c cream ${CREAM_APP_TARGET} ${CREAM_DIST_INST_DIR}/${CREAM_APP_TARGET}
 
