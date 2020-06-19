-- MIT License

-- Copyright (c) 2018 Enzojz

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- https://github.com/Enzojz/luadump
-- Last update: 2018/11/20

local tostring = tostring
local floor = math.floor
local debug = debug
local table = table
local insert = table.insert
local sort = table.sort

local function rawpairs(t)
    return next, t, nil
end

local function isSequenceKey(k, sequenceLength)
    return type(k) == 'number'
        and 1 <= k
        and k <= sequenceLength
        and floor(k) == k
end

local function getSequenceLength(t)
    local len = 1
    local v = rawget(t, len)
    while v ~= nil do
        len = len + 1
        v = rawget(t, len)
    end
    return len - 1
end

local function getNonSequentialKeys(t)
    local keys, keysLength = {}, 0
    local sequenceLength = getSequenceLength(t)
    for k, _ in rawpairs(t) do
        if not isSequenceKey(k, sequenceLength) then
            keysLength = keysLength + 1
            keys[keysLength] = k
        end
    end
    sort(keys, sortKeys)
    return keys, keysLength, sequenceLength
end

-- About from inspect.lua
local function getLocals(l)
    local i = 0
    local direction = 1
    return function()
        i = i + direction
        local k, v = debug.getlocal(l, i)
        if (direction == 1 and (k == nil or k.sub(k, 1, 1) == '(')) then
            i = -1
            direction = -1
            k, v = debug.getlocal(l, i)
        end
        return k, v
    end
end

local function dumpFn(f)
    local params = {}
    pcall(function()
        local oldhook
        local hook = function(event, line)
            for k, _ in getLocals(3) do
                if k == "(*vararg)" then
                    insert(params, "...")
                    break
                end
                insert(params, k)
            end
            debug.sethook(oldhook)
            error('aborting the call')
        end
        oldhook = debug.sethook(hook, "c")
        -- To test for vararg must pass a least one vararg parameter
        f(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)
    end)
    return "(" .. table.concat(params, ", ") .. ")"
end

--Above from
--https://stackoverflow.com/questions/142417/is-there-a-way-to-determine-the-signature-of-a-lua-function

local aIndent = "  "

local function isSimple(node)
    return type(node) == "number" or type(node) == "boolean"
end

local dumpKey = function(k)
    if (type(k) == "number") then
        return tostring(k):format("[%s]")
    elseif string.find(k, "^[_%a][_%w]*$") then
        return k
    else
        return '["' .. k .. '"]'
    end
end

local function dump(printFn)
    local function printLua(node, indent)
        local indent = indent or 0
        local sindent = aIndent:rep(indent + 1)
        local callback = {
            number = function() return tostring(node) end,
            boolean = function() return node and "true" or "false" end,
            string = function() return '"' .. node .. '"' end,
            table = function()
                local nonSequentialKeys, nonSequentialKeysLength, sequenceLength = getNonSequentialKeys(node)
                
                local simpleChildrenSeq = true
                local simpleChildrenNSeq = true
                
                local seqIndex = {}
                local seqFnIndex = {}
                for i = 1, sequenceLength do
                    if (type(node[i]) == "function") then
                        if (printFn) then
                            insert(seqIndex, i)
                        else
                            simpleChildrenSeq = false
                        end
                    else
                        insert(seqIndex, i)
                        simpleChildrenSeq = simpleChildrenSeq and isSimple(node[i])
                    end
                end
                
                local nSeqStr = {}
                local nSeqFnStr = {}
                local nSeqKeyMax = 0
                local nSeqFnKeyMax = 0
                for i = 1, nonSequentialKeysLength do
                    local k = nonSequentialKeys[i]
                    if (type(node[k]) == "function") then
                        if (printFn) then
                            local key = dumpKey(k)
                            insert(nSeqFnStr, {k = key, t = printLua(node[k], indent + 1)})
                            nSeqFnKeyMax = nSeqFnKeyMax > key:len() and nSeqFnKeyMax or key:len()
                        end
                    else
                        local key = dumpKey(k)
                        insert(nSeqStr, {k = key, t = printLua(node[k], indent + 1)})
                        simpleChildrenNSeq = simpleChildrenNSeq and isSimple(node[k])
                        nSeqKeyMax = nSeqKeyMax > key:len() and nSeqKeyMax or key:len()
                    end
                end
                
                local strSeq = ""
                local strNSeq = ""
                local strNSeqFn = ""
                if (#seqIndex == sequenceLength) then
                    if (simpleChildrenSeq) then
                        for i = 1, #seqIndex do
                            strSeq = string.format("%s%s%s",
                                strSeq,
                                printLua(node[seqIndex[i]], indent + 1),
                                i == #seqIndex and (#nSeqStr == 0 and #nSeqFnStr == 0 and "" or ",\n") or ", "
                        )
                        end
                    else
                        for i = 1, #seqIndex do
                            strSeq = string.format("%s%s%s%s",
                                strSeq,
                                sindent,
                                printLua(node[seqIndex[i]], indent + 1),
                                i == #seqIndex and #nSeqStr == 0 and #nSeqFnStr == 0 and "" or ",\n"
                        )
                        end
                    end
                else
                    for i = 1, #seqIndex do
                        strSeq = string.format("%s%s[%d] = %s%s",
                            strSeq,
                            sindent,
                            seqIndex[i],
                            printLua(node[seqIndex[i]], indent + 1),
                            i == #seqIndex and #nSeqStr == 0 and #nSeqFnStr == 0 and "" or ",\n"
                    )
                    end
                end
                
                if (simpleChildrenNSeq) then
                    local totalLength = 0
                    for i = 1, #nSeqStr do
                        totalLength = totalLength + #nSeqStr[i].t + #nSeqStr[i].k
                    end
                    if (totalLength < 120) then
                        for i = 1, #nSeqStr do
                            strNSeq = string.format("%s%s = %s%s", strNSeq, nSeqStr[i].k, nSeqStr[i].t, i == #nSeqStr and (#nSeqFnStr == 0 and "" or ",\n") or ", ")
                        end
                    else
                        simpleChildrenNSeq = false
                        for i = 1, #nSeqStr do
                            strNSeq = string.format("%s%s%s%s = %s%s",
                                strNSeq,
                                sindent,
                                nSeqStr[i].k,
                                string.rep(" ", nSeqKeyMax - #nSeqStr[i].k),
                                nSeqStr[i].t,
                                i == #nSeqStr and #nSeqFnStr == 0 and "" or ",\n"
                        )
                        end
                    end
                else
                    for i = 1, #nSeqStr do
                        strNSeq = string.format("%s%s%s = %s%s",
                            strNSeq,
                            sindent,
                            nSeqStr[i].k,
                            nSeqStr[i].t,
                            i == #nSeqStr and #nSeqFnStr and "" or ",\n"
                    )
                    end
                end
                
                for i = 1, #nSeqFnStr do
                    strNSeqFn = string.format("%s%s%s = %s%s", strNSeqFn, sindent, nSeqFnStr[i].k, nSeqFnStr[i].t, i == #nSeqFnStr and "" or ",\n")
                end
                
                if (simpleChildrenSeq and simpleChildrenNSeq) then
                    if (strSeq:len() == 0 or strNSeq:len() == 0) and strNSeqFn:len() == 0 then
                        return string.format("{ %s%s }", strSeq, strNSeq)
                    else
                        return string.format("{\n%s%s%s\n%s}",
                            strSeq:len() > 0 and sindent .. strSeq or strSeq,
                            strNSeq:len() > 0 and sindent .. strNSeq or strNSeq,
                            strNSeqFn,
                            aIndent:rep(indent))
                    end
                else
                    return string.format("{\n%s%s%s\n%s}",
                        simpleChildrenSeq and strSeq:len() > 0 and sindent .. strSeq or strSeq,
                        simpleChildrenNSeq and strNSeq:len() > 0 and sindent .. strNSeq or strNSeq,
                        strNSeqFn,
                        aIndent:rep(indent))
                end
            end,
            ["function"] = function() return dumpFn(node) end,
            ["userdata"] = function() 
                local mt = getmetatable(node)
                local pr, v = pcall(function() return mt.pairs end)
                local pr2, members = pcall(function() return mt.__members end)
                local t = {}
                if mt and pr and v then 
                    for k,v in pairs(node) do
                        t[k] = v
                    end
                    return printLua(t, indent)
                elseif mt and pr2 and members then
                    local strSeq = ""
                    for i = 1, #members do
                        local k = members[i]
                        local l, v = pcall(function() return node[k] end)
                        if l then
                            strSeq = string.format("%s%s%s = %s%s",
                                strSeq,
                                sindent,
                                k,
                                printLua(v, indent + 1),
                                i == #members and "" or ",\n"
                            )
                        end
                    end
                    return #members > 1
                        and string.format("{\n%s\n%s}", strSeq, aIndent:rep(indent))
                        or string.format("{ %s }", strSeq)
                else
                    return tostring(node)
                end
            end,
            ["thread"] = function() return "" end
        }        
        if callback[type(node)] then
            return callback[type(node)](node)
        else
            return "<unknown type>"
        end        
    end
    return printLua
end

return function(printFn)
    return function(...)
        local args = {...}
        for i = 1, #args do
            print(dump(printFn or false)(args[i]))
        end
        return ...
    end
end
