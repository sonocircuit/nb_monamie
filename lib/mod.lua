-- monami.e - an approximation of just friends synth mode v.1.0 @sonoCircuit
-- based on ImaginaryFriends @synthetivv
-- thank you for your amazing waveshaping implementation!

local fs = require 'fileselect'
local tx = require 'textentry'
local mu = require 'musicutil'
local md = require 'core/mods'
local vx = require 'voice'

local preset_path = "/home/we/dust/data/nb_monamie/monamie_patches"
local default_patch = "/home/we/dust/data/nb_monamie/monamie_patches/default.pam"
local current_patch = ""
local is_active = false

local NUM_VOICES = 6

local paramlist = {
  "level", "pan", "pan_drift", "send_a", "send_b", "pitchbend",
  "ramp", "curve", "fm_ratio", "fm_index", "env_mode", "env_slope", "env_time",
  "ramp_mod", "curve_mod", "fm_mod", "env_slope_mod", "env_time_mod", "send_a_mod", "send_b_mod"
}


---------------- osc msgs ----------------

local function init_nb_monamie()
  osc.send({ "localhost", 57120 }, "/nb_monamie/init")
end

local function alloc_busses()
  osc.send({ "localhost", 57120 }, "/nb_monamie/alloc_busses")
end

local function free_nb_monamie()
  osc.send({ "localhost", 57120 }, "/nb_monamie/free")
end

local function dont_panic()
  osc.send({ "localhost", 57120 }, "/nb_monamie/panic")
end

local function note_on(voice, freq, vel)
  osc.send({ "localhost", 57120 }, "/nb_monamie/note_on", {voice, freq, vel})
end

local function note_off(voice)
  osc.send({ "localhost", 57120 }, "/nb_monamie/note_off", {voice})
end

local function set_param(key, val)
  osc.send({ "localhost", 57120 }, "/nb_monamie/set_param", {key, val})
end


---------------- functions ----------------

local function save_synth_patch(txt)
  if txt then
    local patch = {}
    for _, v in ipairs(paramlist) do
      patch[v] = params:get("nb_monamie_"..v)
    end
    tab.save(patch, preset_path.."/"..txt..".pam")
    current_patch = txt
    print("saved monamie patch: "..txt)
  end
end

local function load_synth_patch(path)
  if path ~= "cancel" and path ~= "" then
    dont_panic()
    if path:match("^.+(%..+)$") == ".pam" then
      local patch = tab.load(path)
      if patch ~= nil then
        for k, v in pairs(patch) do
          params:set("nb_monamie_"..k, v)
        end
        local name = path:match("[^/]*$")
        current_patch = name:gsub(".pam", "")
        print("loaded monamie: "..current_patch)
      else
        print("error: could not find patch", path)
      end
    else
      print("error: not a monamie patch file")
    end
  end
end

local function round_form(param, quant, form)
  return(util.round(param, quant)..form)
end

local function pan_display(param)
  if param < -0.01 then
    return ("L < "..math.abs(util.round(param * 100, 1)))
  elseif param > 0.01 then
    return (math.abs(util.round(param * 100, 1)).." > R")
  else
    return "> <"
  end
end

local function ramp_display(val)
  local a = util.round(util.linlin(-1, 1, 0, 100, val), 1)
  local b = util.round(util.linlin(-1, 1, 100, 0, val), 1)
  return a.."/"..b
end

local function curve_display(val)
  local str = ""
  local pval = math.floor(math.abs(val) * 100)
  if val < -0.97 then
    str = "sqr"
  elseif val > -0.97 and val < -0.02 then
    local tri = pval
    local sqr = 100 - pval 
    str = "sqr:"..sqr.." tri:"..tri
  elseif val > -0.02 and val < 0.02 then
    str = "tri"
  elseif val > 0.02 and val < 0.998 then
    local saw = pval
    local tri = 100 - pval 
    str = "tri:"..tri.." sin:"..saw
  else
    str = "sin"
  end
  return str
end

local function fm_index_display(val)
  local str = ""
  local num = round_form(math.abs(val * 100), 1, "%")
  if val < -0.01 then
    str = "intone: "..num
  elseif val > 0.01 then
    str = "linear: "..num
  else
    str = "0%"
  end
  return str
end

local function slope_display(val)
  local str = ""
  local num = round_form(math.abs(val * 100), 1, "%")
  if val < -0.01 then
    str = "intone: "..num
  elseif val > 0.01 then
    str = "linear: "..num
  else
    str = "0"
  end
  return str
end

local function mix_display(val)
  local a = util.round(util.linlin(0, 1, 0, 100, val), 1)
  local b = util.round(util.linlin(0, 1, 100, 0, val), 1)
  return a.."/"..b
end

local function time_display(val)
  local param
  if val < 0.1 then
    param = round_form(val, 0.001, "s")
  else
    param = round_form(val, 0.01, "s")
  end
  return param
end

local function add_monamie_params()
  params:add_group("nb_monamie_group", "monami.e", 28)
  params:hide("nb_monamie_group")

  params:add_separator("nb_monamie_patches", "presets")

  params:add_trigger("nb_monamie_load", ">> load")
  params:set_action("nb_monamie_load", function() fs.enter(preset_path, load_synth_patch) end)
  
  params:add_trigger("nb_monamie_save", "<< save")
  params:set_action("nb_monamie_save", function() tx.enter(save_synth_patch, current_patch) end)

  params:add_separator("nb_monamie_levels", "levels")
  params:add_control("nb_monamie_level", "level", controlspec.new(0, 1, "lin", 0, 0.8), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_level", function(val) set_param('level', val) end)

  params:add_control("nb_monamie_pan", "pan", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return pan_display(param:get()) end)
  params:set_action("nb_monamie_pan", function(val) set_param('pan', val) end)

  params:add_control("nb_monamie_pan_drift", "pan drift", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_pan_drift", function(val) set_param('panDrift', val) end)

  params:add_control("nb_monamie_send_a", "send a", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_send_a", function(val) set_param('sendA', val) end)
  
  params:add_control("nb_monamie_send_b", "send b", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_send_b", function(val) set_param('sendB', val) end)

  params:add_separator("nb_monamie_sound", "sound")

  params:add_number("nb_monamie_pitchbend", "pitchbend", 1, 24, 7, function(param) return param:get().."st" end)
  params:set_action("nb_monamie_pitchbend", function(val) set_param('pitchBend', val) end)

  params:add_control("nb_monamie_ramp", "ramp", controlspec.new(-1, 1, "lin", 0, 0), function(param) return ramp_display(param:get()) end)
  params:set_action("nb_monamie_ramp", function(val) set_param('ramp', val) end)

  params:add_control("nb_monamie_curve", "curve", controlspec.new(-1, 1, "lin", 0, 0), function(param) return curve_display(param:get())  end)
  params:set_action("nb_monamie_curve", function(val) set_param('curve', val) end)

  params:add_control("nb_monamie_fm_ratio", "fm ratio", controlspec.new(0.5, 2, "lin", 0, 1, "", 1/150), function(param) return round_form(param:get(), 0.01, "*") end)
  params:set_action("nb_monamie_fm_ratio", function(val) set_param('fmRatio', val) end)

  params:add_control("nb_monamie_fm_index", "fm index", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return fm_index_display(param:get()) end)
  params:set_action("nb_monamie_fm_index", function(val) set_param('fmIndex', val) end)

  params:add_separator("nb_monamie_env", "envelope")

  params:add_option("nb_monamie_env_mode", "mode", {"AR", "ASR", "CYCLE"}, 1)
  params:set_action("nb_monamie_env_mode", function(val) set_param('envMode', val - 1) end)

  params:add_control("nb_monamie_env_slope", "slope [atk/rel]", controlspec.new(0, 1, "lin", 0, 0), function(param) return mix_display(param:get()) end)
  params:set_action("nb_monamie_env_slope", function(val) set_param('envRatio', val) end)

  params:add_control("nb_monamie_env_time", "time", controlspec.new(0.0026, 8, "exp", 0, 0, "", 1/500), function(param) return time_display(param:get()) end)
  params:set_action("nb_monamie_env_time", function(val) set_param('envDur', val) end)

  params:add_separator("nb_monamie_mod", "modulation")

  params:add_control("nb_monamie_morph_amt", "morph amt [map me]", controlspec.new(0, 1, "lin", 0, 0), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_morph_amt", function(val) set_param('modDepth', val) end)
  params:set_save("nb_monamie_morph_amt", false)

  params:add_control("nb_monamie_ramp_mod", "ramp", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_ramp_mod", function(val) set_param('rampMod', val) end)

  params:add_control("nb_monamie_curve_mod", "curve", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_curve_mod", function(val) set_param('curveMod', val) end)

  params:add_control("nb_monamie_fm_mod", "fm index", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_fm_mod", function(val) set_param('fmMod', val) end)

  params:add_control("nb_monamie_env_slope_mod", "slope", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_env_slope_mod", function(val) set_param('envRatioMod', val) end)

  params:add_control("nb_monamie_env_time_mod", "time", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_env_time_mod", function(val) set_param('envDurMod', val) end)

  params:add_control("nb_monamie_send_a_mod", "send a", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_send_a_mod", function(val) set_param('sendAMod', val) end)

  params:add_control("nb_monamie_send_b_mod", "send b", controlspec.new(-1, 1, "lin", 0, 0, "", 1/200), function(param) return round_form(param:get() * 100, 1, "%") end)
  params:set_action("nb_monamie_send_b_mod", function(val) set_param('sendBMod', val) end)

  clock.run(function()
    clock.sleep(0.1)
    load_synth_patch(default_patch)
  end)
end


---------------- nb player ----------------

function add_nb_monamie_player()
  local player = {
    alloc = vx.new(NUM_VOICES, 2),
    slot = {},
    is_active = false,
    init_clk = nil
  }

  function player:active()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if not self.is_active then
          self.is_active = true
          alloc_busses()
          params:show("nb_monamie_group")
          if md.is_loaded("fx") == false then
            if engine.name ~= "Nisho" then
              params:hide("nb_monamie_send_a")
              params:hide("nb_monamie_send_b")
              params:hide("nb_monamie_send_a_mod")
              params:hide("nb_monamie_send_b_mod")
            end
          end
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:inactive()
    if self.name ~= nil then
      if self.clk ~= nil then
        clock.cancel(self.clk)
      end
      self.clk = clock.run(function()
        clock.sleep(0.2)
        if self.is_active then
          self.is_active = false
          dont_panic()
          params:hide("nb_monamie_group")
          _menu.rebuild_params()
        end
      end)
    end
  end

  function player:stop_all()
    osc.send({ "localhost", 57120 }, "/nb_monamie/panic", {})
  end

  function player:modulate(val)
    params:set("nb_monamie_morph_amt", val)
  end

  function player:set_slew(s)
  end

  function player:describe()
    return {
      name = "monami.e",
      supports_bend = false,
      supports_slew = false
    }
  end

  function player:pitch_bend(note, val)
    set_param('bendDepth', val)
  end

  function player:modulate_note(note, key, value) 
  end

  function player:note_on(note, vel)
    local freq = mu.note_num_to_freq(note)
    local slot = self.slot[note]
    if slot == nil then
      slot = self.alloc:get()
      slot.count = 1
    end
    local voice = slot.id - 1 -- sc is zero indexed!
    slot.on_release = function()
      note_off(voice)
    end
    self.slot[note] = slot
    note_on(voice, freq, vel)
  end

  function player:note_off(note)
    local slot = self.slot[note]
    if slot ~= nil then
      self.alloc:release(slot)
    end
    self.slot[note] = nil
  end

  function player:add_params()
    add_monamie_params()
  end

  if note_players == nil then
    note_players = {}
  end
  note_players["monami.e"] = player
end


---------------- mod zone ----------------

local function post_system()
  if util.file_exists(preset_path) == false then
    util.make_dir(preset_path)
    os.execute('cp '.. '/home/we/dust/code/nb_monamie/data/monamie_patches/*.pam '.. preset_path)
  end
end

function pre_init()
  init_nb_monamie()
  add_nb_monamie_player()
end

md.hook.register("system_post_startup", "nb monami.e post startup", post_system)
md.hook.register("script_pre_init", "nb monami.e pre init", pre_init)
