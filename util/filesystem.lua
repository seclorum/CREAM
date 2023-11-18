function scandirForWAV(directory)
	local pfile = assert(io.popen(("find '%s' -maxdepth 1 -name '*.wav' -print0"):format(directory), 'r'))
	local list = pfile:read('*a')
    pfile:close()

    local files = {}

    --for filename in string.gmatch(list, '([^/][%_%-%w]*[%.]wav)') do
    for filename in string.gmatch(list, '([^/]*[%.]wav)') do
        table.insert(files, filename)
		print(" file:" .. filename)
    end

    return files
end

function scandir(directory)
--local pfile = assert(io.popen(("find '%s' -name '*.*csv' | rev | cut -d '/' -f1 | rev"):format(directory), 'r'))
local pfile = assert(io.popen(("find '%s' -maxdepth 1 -name '*.*' -print0"):format(directory), 'r'))
    
local list = pfile:read('*a')
    pfile:close()

    local files = {}

    for filename in string.gmatch(list, '([^/][%_%-%w]*[%.][a-z]+)') do
        table.insert(files, filename)
		print(" file:" .. filename)
    end

    return files
end

