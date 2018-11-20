local tostring = tostring

local function rawpairs(t)
    return next, t, nil
end

local function isSequenceKey(k, sequenceLength)
    return type(k) == 'number'
        and 1 <= k
        and k <= sequenceLength
        and math.floor(k) == k
end

-- For implementation reasons, the behavior of rawlen & # is "undefined" when
-- tables aren't pure sequences. So we implement our own # operator.
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
    table.sort(keys, sortKeys)
    return keys, keysLength, sequenceLength
end

-- About from inspect.lua

local function getlocals(l)
  local i = 0
  local direction = 1
  return function ()
    i = i + direction
    local k,v = debug.getlocal(l,i)
    if (direction == 1 and (k == nil or k.sub(k,1,1) == '(')) then 
      i = -1 
      direction = -1 
      k,v = debug.getlocal(l,i) 
    end
    return k,v
  end
end

local function dumpsig(f)
  assert(type(f) == 'function', 
    "bad argument #1 to 'dumpsig' (function expected)")
  local p = {}
  pcall (function() 
    local oldhook
    local hook = function(event, line)
      for k,v in getlocals(3) do 
        if k == "(*vararg)" then 
          table.insert(p,"...") 
          break
        end 
        table.insert(p,k) end
      debug.sethook(oldhook)
      error('aborting the call')
    end
    oldhook = debug.sethook(hook, "c")
    -- To test for vararg must pass a least one vararg parameter
    f(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20)
  end)
  return "function("..table.concat(p,",")..")"  
end

--Above from
--https://stackoverflow.com/questions/142417/is-there-a-way-to-determine-the-signature-of-a-lua-function

local aIndent = "  "

local function isSimple(node)
    return type(node) == "number" or type(node) == "boolean"
end

local dumpKey = function(k)
    if (type(k) == "number") then
        tostring(k):format("[%s]")
    elseif string.find(k, "^[_%a][_%w]*$") then
        return k
    else
        return '["' .. k .. '"]'
    end
end

local function dump(isFnMute, fnSig)
  local function printLua(node, indent)
      local indent = indent or 0
      local sindent = aIndent:rep(indent)
      local callback = {
          number = function() return tostring(node) end,
          boolean = function() return node and "true" or "false" end,
          string = function() return '"' .. node:format("%q") .. '"' end,
          table = function()
              local nonSequentialKeys, nonSequentialKeysLength, sequenceLength = getNonSequentialKeys(node)
              
              local simpleChildrenSeq = true
              local simpleChildrenNSeq = true
              
              local fnList = {}
              local seqStr = {}
              for i = 1, sequenceLength do
                  if (type(node[i]) == "function") then
                      fnList[#fnList + 1] = i
                  else
                      seqStr[#seqStr + 1] = printLua(node[i], indent + 1)
                      simpleChildrenSeq = simpleChildrenSeq and isSimple(node[i])
                  end
              end
              
              local nSeqStr = {}
              local nSeqKeyMax = 0
              for i = 1, nonSequentialKeysLength do
                  local k = nonSequentialKeys[i]
                  if (type(node[k]) == "function") then
                      fnList[#fnList + 1] = k
                  else
                      local key = dumpKey(k)
                      nSeqStr[#nSeqStr + 1] = {k = key, t = printLua(node[k], indent + 1)}
                      simpleChildrenNSeq = simpleChildrenNSeq and isSimple(node[k])
                      nSeqKeyMax = nSeqKeyMax > key:len() and nSeqKeyMax or key:len()
                  end
              end
              
              local str = ""
              if (simpleChildrenSeq) then
                  for i = 1, #seqStr do
                      str = str .. seqStr[i] .. (i == #seqStr and "" or ", ")
                  end
              else
                  for i = 1, #seqStr do
                      str = str .. sindent .. seqStr[i] .. (i == #seqStr and "" or ",\n")
                  end
              end
              
              if (simpleChildrenNSeq) then
                  local totalLength = 0
                  for i = 1, #nSeqStr do
                      totalLength = totalLength + #nSeqStr[i].t + #nSeqStr[i].k
                  end
                  if (totalLength < 120) then
                      for i = 1, #nSeqStr do
                          str = string.format("%s%s = %s%s", str, nSeqStr[i].k, nSeqStr[i].t, i == #nSeqStr and "" or ", ")
                      end
                  else
                      simpleChildrenNSeq = false
                      for i = 1, #nSeqStr do
                          str = string.format("%s%s%s%s = %s%s", str, sindent,
                              nSeqStr[i].k,
                              string.rep(" ", nSeqKeyMax - #nSeqStr[i].k),
                              nSeqStr[i].t,
                              i == #nSeqStr and "" or ",\n"
                      )
                      end
                  end
              else
                  for i = 1, #nSeqStr do
                      str = string.format("%s%s%s = %s%s", str, sindent,
                          nSeqStr[i].k,
                          nSeqStr[i].t,
                          i == #nSeqStr and "" or ",\n"
                  )
                  end
              end
              
              return (simpleChildrenSeq and simpleChildrenNSeq) and string.format("{ %s }", str) or string.format("{\n%s\n%s}", str, aIndent:rep(indent - 1))
          end,
          ["function"] = function() return "" end,
          ["userdata"] = function() return "" end,
          ["thread"] = function() return "" end,
          ["nil"] = function() return "" end
      }
      return callback[type(node)](node)
  end
  return printLua
end

return function(isFnMute, fnSig)
  return function(...)
      local args = {...}
      for i = 1, #args do
        print(dump(isFnMute or true, fnSig or false)(args[i]))
      end
      return ...
  end
end
