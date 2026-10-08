extends Node
## Autoload: in-game time. 1 real second = PER_SEC game minutes at 1x speed.

const PER_SEC := 2.0

var minutes: float = 7.0 * 60.0  # Day 1, 07:00
var speed: float = 1.0


func day() -> int:
	return int(minutes / 1440.0) + 1


func hour_f() -> float:
	return fmod(minutes, 1440.0) / 60.0


func time_string() -> String:
	var m := int(fmod(minutes, 1440.0))
	return "%02d:%02d" % [m / 60, m % 60]


func is_night() -> bool:
	var h := hour_f()
	return h >= 21.0 or h < 5.5


func period() -> String:
	var h := hour_f()
	if h < 5.5 or h >= 21.0:
		return "night"
	if h < 12.0:
		return "morning"
	if h < 17.0:
		return "afternoon"
	return "evening"


## Colour multiplier for the whole world, giving a day/night cycle.
func daylight() -> Color:
	var h := hour_f()
	var night := Color(0.30, 0.35, 0.62)
	var dawn := Color(0.95, 0.80, 0.75)
	var day := Color(1, 1, 1)
	var dusk := Color(1.0, 0.72, 0.58)
	if h < 5.0:
		return night
	if h < 7.0:
		return night.lerp(dawn, (h - 5.0) / 2.0)
	if h < 9.0:
		return dawn.lerp(day, (h - 7.0) / 2.0)
	if h < 17.0:
		return day
	if h < 19.0:
		return day.lerp(dusk, (h - 17.0) / 2.0)
	if h < 21.0:
		return dusk.lerp(night, (h - 19.0) / 2.0)
	return night
