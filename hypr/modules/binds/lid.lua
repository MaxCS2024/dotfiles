-- Closing the lid locks the screen. It used to suspend, and hypridle's
-- before_sleep_cmd locked on the way down; with suspend gone
-- (modules/autostart.lua holds logind's lid switch), this keeps the lock.
--
-- loginctl lock-session rather than hyprlock directly, so it goes through
-- hypridle's lock_cmd and can't start a second hyprlock over a first.
-- `locked` so it still fires while the lock screen is up.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("loginctl lock-session"), { locked = true })
