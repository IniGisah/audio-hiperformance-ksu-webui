#!/system/bin/sh
# Do NOT assume where your module will be located. ALWAYS use $MODDIR if you need to know where this script and module is placed.

# sleep 20 secs needed for settings commands to be effective in an orphan process

(((sleep 20; settings delete system volume_steps_music) 0<&- &>"/dev/null" &) &)

