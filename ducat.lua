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
polyperc = require 'polyperc'

engine.name = 'PolyPerc'

idx, chn = 1, 1
seq_stacks = {
  {s{0, 2, 4, s{9, 16, s{12, 24}, s{11, 23}}}},
  {s{0, 12}}
}

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
  params:add{type = "number", id = "ch1_step_div", name = "ch1 division", min = 1, max = 16, default = 4}
  params:add{type = "number", id = "ch2_step_div", name = "ch2 division", min = 1, max = 16, default = 2}
  params:add_group("synth",6)
  polyperc.params()

  c1, c2 = clk(1), clk(2)
  if norns.crow.connected() then
    crow.input[1].change = c1
    crow.input[1].mode("change", 2, 0.25, "rising")
    crow.input[2].change = c2
    crow.input[2].mode("change", 2, 0.25, "rising")
  else
    clock.run(function ()
      while true do
        clock.sync(1/params:get('ch1_step_div'))
        c1()
      end
    end)
    clock.run(function ()
      while true do
        clock.sync(1/params:get('ch2_step_div'))
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
    crow.output[c].volts = s / 12
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
      peek(seq_stack)[idx] = peek(seq_stack)[idx] + z
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
      if s.is_sequins(seq[i]) then
        screen.text(sequins_peek(seq[i])..".")
      else
        screen.text(seq[i])
      end
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