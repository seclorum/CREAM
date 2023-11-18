BUILD_ARCHITECTURE := $(shell uname -m)
CREAM_APP_TARGET = cream.${BUILD_ARCHITECTURE}
CREAM_DIST_INST_DIR = dist/aa-cream_1.0-1/opt/austrianAudio/bin/
LUA_SRC_FILES = ./main.lua ./config.lua ./cream.lua ./buildDate.lua ./mixer.lua ./devices.lua ./httpserver.lua ./util/geocalcs.lua ./util/time.lua ./util/tools.lua ./util/scantest.lua ./util/gpxmaker.lua ./util/lua_enumerable.lua ./util/average.lua ./util/filesystem.lua ./util/mobdebug.lua ./util/dateparse.lua ./util/debug.lua ./util/Logger.lua ./util/persistence.lua ./util/geocoords.lua ./util/noobhub.lua ./util/environment_debug.lua 


ifeq ($(BUILD_ARCHITECTURE), armv7l)
${CREAM_APP_TARGET}:
	~/.luarocks/bin/luastatic ${LUA_SRC_FILES} /usr/lib/arm-linux-gnueabihf/libluajit-5.1.a /usr/lib/arm-linux-gnueabihf/liblua5.1-cjson.a -I/usr/include/lua5.1  "-o ${CREAM_APP_TARGET}"
else
${CREAM_APP_TARGET}:
	~/.luarocks/bin/luastatic ${LUA_SRC_FILES} /usr/lib/x86_64-linux-gnu/libluajit-5.1.a /usr/lib/x86_64-linux-gnu/liblua5.1-cjson.a -I/usr/include/lua5.1  "-o ${CREAM_APP_TARGET}"
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
	sudo apt-get install -y luajit luarocks git build-essential libssl-dev libluajit-5.1-dev lua-cjson-dev
	echo "Luarocks dependencies:"

reqs-luarock:
	#luarocks install turbo --local
	luarocks install ljsyscall --local
	luarocks install ffi --local
	luarocks install cffi --local
	luarocks install cffi-lua --local
	luarocks install penlight-ffi --local
	luarocks install lgi --local
	luarocks install libtffi --local
	luarocks install luajit-ffi-loader --local
	luarocks install luaposix --local
	luarocks install lua-atomic --local
	luarocks install luastatic --local
	luarocks path

trace:	./cream.armv7l
	strace -r -s 1024 -o /opt/austrianAudio/var/CREAM/`date +"%Y%m%d-%H%M%S"`-app_strace.log.txt ./cream.armv7l

dist:	${CREAM_APP_TARGET}
	cp -rfvp ${CREAM_APP_TARGET} ${CREAM_DIST_INST_DIR}
	make -C dist/
	ls -alF dist/*.deb

clean:
	rm -rf *.luastatic.c cream ${CREAM_APP_TARGET} ${CREAM_DIST_INST_DIR}/${CREAM_APP_TARGET}
 
