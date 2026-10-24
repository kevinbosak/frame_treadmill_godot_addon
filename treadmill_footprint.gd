class_name TreadmillFootprint
extends RefCounted
## Where the treadmill belt is, worked out from three touched points:
## the front-left corner, the front-right corner, and anywhere on the back edge.
## All positions are on the floor plane: Vector2(x, z) in headset space.

var center := Vector2.ZERO      # middle of the belt
var forward := Vector2(0, -1)   # direction you face when walking (towards the console)
var width := 0.0                # belt width (m)
var length := 0.0               # belt length (m)
var belt_height := 0.0          # height of the belt surface (m)

## Direction to your right while walking.
var right: Vector2:
	get:
		return Vector2(-forward.y, forward.x)


static func from_points(front_left: Vector3, front_right: Vector3, back: Vector3) -> TreadmillFootprint:
	var f := TreadmillFootprint.new()
	var fl := Vector2(front_left.x, front_left.z)
	var fr := Vector2(front_right.x, front_right.z)
	var b := Vector2(back.x, back.z)
	var across := fr - fl
	f.width = across.length()
	if f.width < 0.01:
		f.width = 0.0
		return f
	var r := across / f.width
	f.forward = Vector2(r.y, -r.x)
	var front_mid := (fl + fr) / 2.0
	var depth := (front_mid - b).dot(f.forward)
	if depth < 0.0:
		# Corners were touched right-then-left; flip so forward still points at the front.
		f.forward = -f.forward
		depth = -depth
	f.length = depth
	f.center = front_mid - f.forward * depth / 2.0
	f.belt_height = (front_left.y + front_right.y + back.y) / 3.0
	return f


func is_valid() -> bool:
	return width > 0.0 and length > 0.0


## Empty if the measurements look like a real treadmill, otherwise what's wrong.
func problem() -> String:
	if width < 0.3 or width > 1.2:
		return "The belt measured %.2f m wide, which doesn't look right" % width
	if length < 0.8 or length > 2.6:
		return "The belt measured %.2f m long, which doesn't look right" % length
	return ""


## A floor position relative to the belt: x = metres to the right of centre,
## y = metres ahead of centre.
func to_local(p: Vector2) -> Vector2:
	var d := p - center
	return Vector2(d.dot(right), d.dot(forward))


func to_dict() -> Dictionary:
	return {"center": center, "forward": forward, "width": width,
			"length": length, "belt_height": belt_height}


static func from_dict(d: Dictionary) -> TreadmillFootprint:
	var f := TreadmillFootprint.new()
	f.center = d.get("center", Vector2.ZERO)
	f.forward = d.get("forward", Vector2(0, -1))
	f.width = d.get("width", 0.0)
	f.length = d.get("length", 0.0)
	f.belt_height = d.get("belt_height", 0.0)
	return f
