-- ducat: interface to 2x sequins
-- 1.0.0 @lwakefield
--
-- an interface to two sequins
--
-- E1 select channel
-- E2 select step
-- E3 transpose step
-- K2 go to the parent sequin
-- K3 enter a child sequin
-- K1+K2 delete selected step
-- K1+K3 add a new step
-- K1+E2 change the step size
--
-- (crow is optional)
-- IN 1 clocks the first sequin
-- IN 2 clocks the second sequin
-- OUT 1 outputs the first sequin
-- OUT 2 outputs the second sequin

s = require 'sequins'
mu = require 'musicutil'
hnds = include('lib/hnds')
hs = include('awake/lib/halfsecond')

engine.name = 'PolyPerc'

idx, chn = 1, 1
seq_stacks = {
  {s{0, 2, 4, s{9, 16, s{12, 24}, s{11, 23}}}},
  {s{0, 12}}
}

function hnds.process()
  for i = 1, 4 do
    local target = hnds[i].lfo_targets[params:get(i .. "lfo_target")]
    local on     = params:get(i .. "lfo") == 2
    
    if on then
      if target == "ch1_cutoff" or target == "ch2_cutoff" then
        params:set(target, hnds.scale(hnds[i].slope, -1, 1, 0.0, 5000))
      elseif target == "ch1_amp" or target == "ch2_amp" then
        params:set(target, hnds.scale(hnds[i].slope, -1, 1, 0.0, 1.0))
      elseif target == "ch1_release" or target == "ch2_release" then
        params:set(target, hnds.scale(hnds[i].slope, -1, 1, 0.0, 10.0))
      elseif target == "ch1_pw" or target == "ch2_pw" then
        params:set(target, hnds.scale(hnds[i].slope, -1, 1, 0.0, 100.0))
      elseif target == "ch1_pan" or target == "ch2_pan" then
        params:set(target, hnds.scale(hnds[i].slope, -1, 1, -1.0, 1.0))
      end
    end
  end
end

function init()
  local dir = _path.data..'/'..debug.getinfo(1,'S').source:match("([^/]*).lua$")..'/'
  params.action_write = function(filename,name)
    os.execute("mkdir -p "..dir)
    tab.save({seq_stacks[1][1], seq_stacks[2][1]}, dir..'/'..name..'.data')
  end
  params.action_read = function(filename)
    -- pulled from https://monome.org/docs/norns/reference/params
    local loaded_file = io.open(filename, "r")
    if loaded_file then
      io.input(loaded_file)
      local pset_name = string.sub(io.read(), 4, -1)
      io.close(loaded_file)
      
      function load_sequins(v)
        local d = {}
        for i=1,#v do
          d[i] = type(v[i]) == 'table' and load_sequins(v[i]) or v[i]
        end
        return s(d):step(v.n)
      end
      
      ss = tab.load(dir..'/'..pset_name..'.data')
      seq_stacks = { { load_sequins(ss[1]) }, { load_sequins(ss[2]) } }
      idx = 1; chn = 1
    end
  end
  for i=1,2 do
    params:add{type="control", id="ch"..i.."_cutoff",      name="ch"..i.." cutoff",  controlspec=controlspec.new(50,5000,'exp',0,800,'hz')}
    params:add{type="control", id="ch"..i.."_amp",         name="ch"..i.." amp",     controlspec=controlspec.new(0,1,'lin',0,0.5,'')}
    params:add{type="control", id="ch"..i.."_release",     name="ch"..i.." release", controlspec=controlspec.new(0.1,10,'lin',0,1.2,'s')}
    params:add{type="control", id="ch"..i.."_pw",          name="ch"..i.." pw",      controlspec=controlspec.new(0,100,'lin',0,50,'%')}
    params:add{type="control", id="ch"..i.."_pan",         name="ch"..i.." pan",     controlspec=controlspec.new(-1,1, 'lin',0,0,'')}
    params:add{type="option",  id="ch"..i.."_step",   options={1/8, 1/7, 1/6, 1/5, 1/4, 1/3, 1/2, 1, 2, 3, 4, 5, 6, 7, 8}, default=5}
  end
  hnds[1].lfo_targets = {"none",
                         "ch1_cutoff", "ch1_amp", "ch1_release", "ch1_pw", "ch1_pan",
                         "ch2_cutoff", "ch2_amp", "ch2_release", "ch2_pw", "ch2_pan"}
  hnds[2].lfo_targets = hnds[1].lfo_targets
  hnds[3].lfo_targets = hnds[1].lfo_targets
  hnds[4].lfo_targets = hnds[1].lfo_targets
  hnds.init()
  hs.init()

  c1, c2 = clk(1), clk(2)
  if norns.crow.connected() then
    crow.input[1].change = c1
    crow.input[1].mode("change", 2, 0.25, "rising")
    crow.input[2].change = c2
    crow.input[2].mode("change", 2, 0.25, "rising")
  else
    clock.run(function ()
      while true do
        clock.sync(params:string('ch1_step'))
        c1()
      end
    end)
    clock.run(function ()
      while true do
        clock.sync(params:string('ch2_step'))
        c2()
      end
    end)
  end
  
  clock.run(function ()
    while true do
      clock.sleep(1/15)
      draw()
    end
  end)
end

function clk(c)
  return function ()
    local s = seq_stacks[c][1]()
    
    if s == -49 or s == 49 then return end
    
    crow.output[c].volts = s / 12
    
    engine.amp(params:get("ch"..c.."_amp"))
    engine.cutoff(params:get("ch"..c.."_cutoff"))
    engine.release(params:get("ch"..c.."_release"))
    engine.pw(params:get("ch"..c.."_pw") / 100)
    engine.pan(params:get("ch"..c.."_pan"))
    engine.hz(mu.note_num_to_freq(60 + s))
  end
end

function peek(stack)
  return stack[#stack]
end
function push(stack, v)
  stack[#stack+1] = v
end
function sequins_peek(v)
  while s.is_sequins(v) do v = v:peek() end
  return v
end

alt = false
function key(n,z)
  local seq_stack = seq_stacks[chn]
  local seq = peek(seq_stack)
  
  if n == 1 then alt = z == 1 end
  
  -- add a new note
  if alt and n == 3 and z == 1 then
    table.insert(seq.data, idx, sequins_peek(seq.data[idx]))
    s.setdata(seq, seq.data)
  end
  
  -- enter/create a subseq
  if not alt and n == 3 and z == 1 then
    if s.is_sequins(seq[idx]) == false then
      seq[idx] = s{seq[idx]}
    end
    push(seq_stack, seq[idx])
    idx = 1
  end
  
  -- remove a note
  if alt and n == 2 and z == 1 then
    if seq.length == 1 then return end
    
    table.remove(seq.data, idx)
    s.setdata(seq, seq.data)
    if idx > #seq.data then idx = #seq.data end
  end
  
  -- exit the subseq
  if not alt and n == 2 and z == 1 then
    if #seq_stack == 1 then return end
    
    local popped = table.remove(seq_stack)
    local k = tab.key(peek(seq_stack), popped)
    if popped.length == 1 then popped = popped[1] end
    peek(seq_stack)[k] = popped
    idx = k
  end
end

function enc(n,z)
  local seq_stack = seq_stacks[chn]
  
  if alt == true then
    -- change the step size
    if n == 2 then
      local seq = peek(seq_stacks[chn])
      seq:step(seq.n + z)
    end
  else
    -- change the selected channel
    if n == 1 then
      chn = chn == 1 and 2 or 1
      if idx > #seq_stacks[chn] then idx = #seq_stacks[chn] end
    end
    
    -- change the selected step
    if n == 2 then
      idx = util.wrap(idx + z, 1, peek(seq_stack).length)
    end
    
    -- transpose the selected step
    if n == 3 then
      -- we treat values -49 and 49 as a rest
      peek(seq_stack)[idx] = util.clamp(peek(seq_stack)[idx] + z, -49, 49)
    end
  end
  
end

function draw()
  if _menu.mode then return end
  
  screen.clear()
  
  -- draw the sequence
  for c=1, #seq_stacks do
    local seq = peek(seq_stacks[c])
    for i=1,seq.length do
      screen.level(seq.ix == i and 15 or 1)
      screen.move(16*(i-1), 22*c)
      local v = sequins_peek(seq[i])
      if v == -49 or v == 49 then v = '-' end
      if s.is_sequins(seq[i]) then v = v.."." end
      screen.text(v)
    end
  end
  
  if alt then
    screen.level(1)
    -- draw the step size
    screen.move(0, 32)
    screen.text(peek(seq_stacks[1]).n)
    screen.move(0, 56)
    screen.text(peek(seq_stacks[2]).n)
  end
  
  -- draw the selected step on the selected channel
  screen.level(15)
  screen.move(16*(idx-1), 22*chn + 2)
  screen.line_rel(8, 0)
  screen.stroke()
  
  screen.update()
end