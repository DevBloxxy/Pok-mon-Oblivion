#===============================================================================#
# Whether the options menu shows the speed up settings (true by default)
#===============================================================================#
module Settings
  SPEED_OPTIONS = false # Disabled since speed is now automatic
end
#===============================================================================#
# Speed-up config
#===============================================================================#
SPEEDUP_MULTIPLIER = 2.5
$TabHeld = false
$SpeedupToggle = false
#===============================================================================#
# Handle Tab key press/release and Shift+Tab toggle
#===============================================================================#
module Input
  class << self
    alias_method :original_update, :update unless method_defined?(:original_update)
  end

  def self.update
    original_update

    # Use Win32API to check for Tab key (VK_TAB = 0x09)
    @get_key_state ||= Win32API.new('user32', 'GetAsyncKeyState', 'i', 'i')
    tab_pressed = @get_key_state.call(0x09) & 0x8000 != 0
    shift_pressed = @get_key_state.call(0x10) & 0x8000 != 0

    # Check for Shift+Tab toggle
    if shift_pressed && tab_pressed && !@last_shift_tab
      $SpeedupToggle = !$SpeedupToggle
    end
    @last_shift_tab = shift_pressed && tab_pressed

    # Check if Tab is currently held down (only if toggle is off)
    if $SpeedupToggle
      $TabHeld = true
    else
      $TabHeld = tab_pressed
    end
  end
end
#===============================================================================#
# Return System.Uptime with a multiplier when Tab is held
#===============================================================================#
module System
  class << self
    alias_method :unscaled_uptime, :uptime unless method_defined?(:unscaled_uptime)
  end

  def self.uptime
    return $TabHeld ? SPEEDUP_MULTIPLIER * unscaled_uptime : unscaled_uptime
  end
end
#===============================================================================#
# Speed up audio playback when Tab is held
#===============================================================================#
module Audio
  class << self
    # Store original methods
    alias_method :original_se_play, :se_play unless method_defined?(:original_se_play)
    alias_method :original_me_play, :me_play unless method_defined?(:original_me_play)
    alias_method :original_bgm_play, :bgm_play unless method_defined?(:original_bgm_play)
    alias_method :original_bgs_play, :bgs_play unless method_defined?(:original_bgs_play)
  end

  def self.se_play(filename, volume = 100, pitch = 100, *args)
    adjusted_pitch = $TabHeld ? (pitch * SPEEDUP_MULTIPLIER).to_i : pitch
    adjusted_pitch = [adjusted_pitch, 150].min # Cap at 150 to prevent distortion
    original_se_play(filename, volume, adjusted_pitch, *args)
  end

  def self.me_play(filename, volume = 100, pitch = 100, *args)
    adjusted_pitch = $TabHeld ? (pitch * SPEEDUP_MULTIPLIER).to_i : pitch
    adjusted_pitch = [adjusted_pitch, 150].min
    original_me_play(filename, volume, adjusted_pitch, *args)
  end

  def self.bgm_play(filename, volume = 100, pitch = 100, *args)
    adjusted_pitch = $TabHeld ? (pitch * SPEEDUP_MULTIPLIER).to_i : pitch
    adjusted_pitch = [adjusted_pitch, 150].min
    original_bgm_play(filename, volume, adjusted_pitch, *args)
  end

  def self.bgs_play(filename, volume = 100, pitch = 100, *args)
    adjusted_pitch = $TabHeld ? (pitch * SPEEDUP_MULTIPLIER).to_i : pitch
    adjusted_pitch = [adjusted_pitch, 150].min
    original_bgs_play(filename, volume, adjusted_pitch, *args)
  end
end
#===============================================================================#
# Fix for consecutive battle soft-lock glitch
#===============================================================================#
alias :original_pbBattleOnStepTaken :pbBattleOnStepTaken
def pbBattleOnStepTaken(repel_active)
  return if $game_temp.in_battle
  original_pbBattleOnStepTaken(repel_active)
end

class Game_Event < Game_Character
  def pbGetInterpreter
    return @interpreter
  end

  def pbResetInterpreterWaitCount
    @interpreter.pbRefreshWaitCount if @interpreter && @trigger == 4
  end
end

class Interpreter
  def pbRefreshWaitCount
    @wait_count = 0
    @wait_start = System.uptime
  end
end

class Window_AdvancedTextPokemon < SpriteWindow_Base
  def pbResetWaitCounter
    @wait_timer_start = nil
    @waitcount = 0
    @display_last_updated = nil
  end
end

$CurrentMsgWindow = nil
def pbMessage(message, commands = nil, cmdIfCancel = 0, skin = nil, defaultCmd = 0, &block)
  ret = 0
  msgwindow = pbCreateMessageWindow(nil, skin)
  $CurrentMsgWindow = msgwindow

  if commands
    ret = pbMessageDisplay(msgwindow, message, true,
                           proc { |msgwndw|
                                  next Kernel.pbShowCommands(msgwndw, commands, cmdIfCancel, defaultCmd, &block)
                                }, &block)
  else
    pbMessageDisplay(msgwindow, message, &block)
  end
  pbDisposeMessageWindow(msgwindow)
  $CurrentMsgWindow = nil
  Input.update
  return ret
end

#===============================================================================#
# Fix for scrolling fog speed
#===============================================================================#
class Game_Map
  alias_method :original_update, :update unless method_defined?(:original_update)

  def update
    temp_timer = @fog_scroll_last_update_timer
    @fog_scroll_last_update_timer = System.uptime # Don't scroll in the original update method
    original_update
    @fog_scroll_last_update_timer = temp_timer
    update_fog
  end

  def update_fog
    uptime_now = System.unscaled_uptime
    @fog_scroll_last_update_timer = uptime_now unless @fog_scroll_last_update_timer
    speedup_mult = $TabHeld ? SPEEDUP_MULTIPLIER : 1
    scroll_mult = (uptime_now - @fog_scroll_last_update_timer) * 5 * speedup_mult
    @fog_ox -= @fog_sx * scroll_mult
    @fog_oy -= @fog_sy * scroll_mult
    @fog_scroll_last_update_timer = uptime_now
  end
end
#===============================================================================#
# Fix for animation index crash
#===============================================================================#
class SpriteAnimation
  def update_animation
    new_index = ((System.uptime - @_animation_timer_start) / @_animation_time_per_frame).to_i
    if new_index >= @_animation_duration
      dispose_animation
      return
    end
    quick_update = (@_animation_index == new_index)
    @_animation_index = new_index
    frame_index = @_animation_index
    current_frame = @_animation.frames[frame_index]
    unless current_frame
      dispose_animation
      return
    end
    cell_data   = current_frame.cell_data
    position    = @_animation.position
    animation_set_sprites(@_animation_sprites, cell_data, position, quick_update)
    return if quick_update
    @_animation.timings.each do |timing|
      next if timing.frame != frame_index
      animation_process_timing(timing, @_animation_hit)
    end
  end
end
