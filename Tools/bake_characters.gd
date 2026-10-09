extends SceneTree

## Bakes the fighter art into crisp stills and looping idle animations.
## Source art is res://Art/fighters/<id>.png and is never written to. The <id>_idle.png files are not read.
##
## Run from the project folder after editing any fighter art:
##   godot --headless --path . --script res://Tools/bake_characters.gd
##   godot --headless --path . --import
## Pass ids after "--" to bake only some fighters:
##   godot --headless --path . --script res://Tools/bake_characters.gd -- chef sion
##
## Writes:
##   Art/fighters/crisp/<id>.png       still pose used for portraits and hit boxes
##   Art/fighters/idle/<id>_sheet.png  idle frames side by side
##   Art/fighters/idle/<id>_idle.tres  SpriteFrames used by Scenes/characters/<id>.tscn
##
## Every fighter shares one breathing rhythm so the party moves as a set:
## the torso lifts one pixel, the head follows a frame later, then both settle.
## Personality comes from slow color effects and particles layered on top, never from bending the art.

const SIZE := 64
const FRAMES := 12
const FPS := 8.0
const SOURCE_DIR := "res://Art/fighters/"
const CRISP_DIR := "res://Art/fighters/crisp/"
const IDLE_DIR := "res://Art/fighters/idle/"
const CLEAR := Color(0, 0, 0, 0)
const INK := Color(0.04, 0.03, 0.07)
## Frames where the torso and head sit one pixel higher.
const TORSO_UP := [3, 4, 5, 6, 7, 8]
const HEAD_UP := [4, 5, 6, 7, 8, 9]

## neck and waist: rows where head and torso motion stop.
## head: columns of the head, so weapons and hands above the neck move with the torso.
## colors: palette size after cleanup.
const RIGS := {
	"champion": {"neck": 13, "waist": 34, "head": [24, 38], "colors": 32},
	"rogue": {"neck": 14, "waist": 38, "head": [20, 36], "colors": 32},
	"roeseph": {"neck": 17, "waist": 42, "head": [25, 38], "colors": 32},
	"randy": {"neck": 16, "waist": 38, "head": [26, 44], "colors": 32},
	"chef": {"neck": 18, "waist": 40, "head": [20, 34], "colors": 32},
	"okirik": {"neck": 16, "waist": 38, "head": [19, 33], "colors": 32},
	"wewe": {"neck": 14, "waist": 36, "head": [22, 38], "colors": 32},
	"sion": {"neck": 12, "waist": 42, "head": [24, 40], "colors": 40},
	"dual": {"neck": 15, "waist": 40, "head": [24, 38], "colors": 32},
	## Chefromancer's summon. Waist at the bottom edge so the whole spirit floats instead of breathing.
	"chicken": {"neck": 44, "waist": 64, "head": [29, 47], "colors": 32},
}


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	for dir in [CRISP_DIR, IDLE_DIR]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for id in RIGS:
		if only.is_empty() or only.has(id):
			_bake(id)
	quit()


func _bake(id: String) -> void:
	var rig: Dictionary = RIGS[id]
	var src := Image.load_from_file(ProjectSettings.globalize_path(SOURCE_DIR + id + ".png"))
	if src == null or src.is_empty():
		push_error("missing fighter art for %s" % id)
		return
	src.convert(Image.FORMAT_RGBA8)
	var clean := _quantize(src, int(rig.colors))
	_outline(clean).save_png(ProjectSettings.globalize_path(CRISP_DIR + id + ".png"))
	if id == "chef":
		clean = _erase_specks(clean, Rect2i(34, 0, 30, 16))
	var sheet := Image.create_empty(SIZE * FRAMES, SIZE, false, Image.FORMAT_RGBA8)
	for f in FRAMES:
		var t := float(f) / FRAMES
		var torso := -1 if TORSO_UP.has(f) else 0
		var head := -1 if HEAD_UP.has(f) else 0
		var frame := _breathe(clean, rig, torso, head)
		_glow(id, frame, t)
		frame = _outline(frame)
		_fx(id, frame, t, torso)
		sheet.blit_rect(frame, Rect2i(0, 0, SIZE, SIZE), Vector2i(f * SIZE, 0))
	sheet.save_png(ProjectSettings.globalize_path(IDLE_DIR + id + "_sheet.png"))
	_write_frames(id, FRAMES, FPS)
	print("baked %s" % id)


## Shifts the head block and the torso block straight up by whole pixels. Legs stay planted.
func _breathe(src: Image, rig: Dictionary, torso: int, head: int) -> Image:
	var neck := int(rig.neck)
	var waist := int(rig.waist)
	var head_x: Array = rig.head
	var out := _blank()
	for y in SIZE:
		for x in SIZE:
			var dy := 0
			if y < neck and x >= int(head_x[0]) and x <= int(head_x[1]):
				dy = head
			elif y < waist:
				dy = torso
			out.set_pixel(x, y, _px(src, x, y - dy))
	return out


# Slow color effects. Every one eases in and out over the loop so nothing pops.

func _glow(id: String, img: Image, t: float) -> void:
	var swell := _wave(t)
	match id:
		"champion":
			_tint(img, func(x: int, y: int, c: Color) -> bool:
				return x >= 27 and x <= 35 and y >= 2 and y <= 10 and c.v < 0.3,
				Color(0.45, 0.95, 1.0), func(_x: int, _y: int) -> float: return 0.25 + 0.45 * swell)
			var glint := (t - 0.5) / 0.35
			_tint(img, func(x: int, y: int, c: Color) -> bool: return _blade_dist(x, y) <= 2.2 and c.s < 0.25 and c.v > 0.45,
				Color.WHITE, func(x: int, y: int) -> float: return _band(_blade_u(x, y), glint, 0.07) * 0.8)
		"rogue":
			var shine := (t - 0.55) / 0.3
			_tint(img, func(_x: int, _y: int, c: Color) -> bool: return _is_red(c),
				Color(1, 0.95, 0.88), func(x: int, y: int) -> float:
					var across := (x + y - 52.0) / 46.0
					return _band(across, shine, 0.04) * 0.85)
		"roeseph":
			_tint(img, func(_x: int, _y: int, c: Color) -> bool: return _is_yellow(c),
				Color.WHITE, func(x: int, _y: int) -> float: return _band(x / 64.0, fposmod(t * 1.2, 1.2) - 0.1, 0.1) * 0.75)
		"randy":
			_tint(img, func(_x: int, y: int, c: Color) -> bool: return y < 40 and _is_skin(c),
				Color(1.0, 0.72, 0.55), func(_x: int, _y: int) -> float: return 0.12 * swell)
		"chef":
			_tint(img, func(x: int, y: int, c: Color) -> bool:
				return x >= 41 and x <= 55 and y >= 13 and y <= 25 and _is_purple(c),
				Color(0.95, 0.78, 1.0), func(_x: int, _y: int) -> float: return 0.1 + 0.45 * swell)
		"okirik":
			_tint(img, func(x: int, y: int, c: Color) -> bool:
				return x >= 32 and x <= 48 and y <= 16 and _is_gold(c),
				Color(1, 0.97, 0.8), func(_x: int, _y: int) -> float: return 0.1 + 0.5 * swell)
		"wewe":
			_tint(img, func(x: int, y: int, c: Color) -> bool:
				return x >= 40 and x <= 48 and y >= 5 and y <= 18 and _is_skin(c),
				Color(0.72, 0.9, 1.0), func(_x: int, _y: int) -> float: return 0.4 * swell)
		"sion":
			_tint(img, func(_x: int, _y: int, c: Color) -> bool: return _is_purple(c),
				Color(0.8, 0.5, 1.0), func(_x: int, _y: int) -> float: return 0.5 * swell)
		"chicken":
			_tint(img, func(_x: int, _y: int, c: Color) -> bool: return c.h > 0.4 and c.h < 0.55 and c.s < 0.5,
				Color(0.92, 1.0, 0.97), func(_x: int, y: int) -> float: return _band(y, lerpf(64.0, 26.0, t), 4.0) * 0.45)
			_tint(img, func(x: int, y: int, c: Color) -> bool: return x >= 36 and x <= 39 and y >= 36 and y <= 41 and _is_purple(c),
				Color(0.95, 0.85, 1.0), func(_x: int, _y: int) -> float: return 0.6 * swell)
		"dual":
			var run := (t - 0.2) / 0.5
			_tint(img, func(x: int, _y: int, c: Color) -> bool: return x >= 33 and _is_yellow(c),
				Color.WHITE, func(x: int, _y: int) -> float: return _band((x - 34) / 22.0, run, 0.12) * 0.8)


# Particles drawn after the outline so they glow. Each rises in a straight line at a steady pace.

func _fx(id: String, img: Image, t: float, torso: int) -> void:
	match id:
		"chef":
			for i in 4:
				var ph := fposmod(t + i / 4.0, 1.0)
				var x: int = 46 + [0, 3, 1, 4][i]
				var y := 15 + torso - roundi(ph * 15.0)
				_put(img, x, y, Color(0.97, 0.86, 1.0).lerp(Color(0.55, 0.3, 0.8), ph))
		"okirik":
			for i in 3:
				var ph := fposmod(t + i / 3.0, 1.0)
				var x: int = 37 + [0, 5, 2][i]
				var y := 12 + torso - roundi(ph * 12.0)
				_put(img, x, y, Color(1, 0.97, 0.82).lerp(Color(0.92, 0.72, 0.3), ph))
		"wewe":
			var spark := _wave(t)
			if spark > 0.35:
				var tip := Vector2i(45, 7 + torso)
				var c := Color(0.92, 0.97, 1.0)
				_put(img, tip.x, tip.y, c)
				if spark > 0.75:
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
						_put(img, tip.x + d.x, tip.y + d.y, Color(0.5, 0.75, 1.0))
		"chicken":
			for i in 3:
				var ph := fposmod(t + i / 3.0, 1.0)
				var x: int = [20, 25, 23][i]
				var y: int = 46 + torso - roundi(ph * 14.0)
				_put(img, x, y, Color(0.9, 1.0, 0.96).lerp(Color(0.45, 0.75, 0.72), ph))
		"sion":
			for i in 5:
				var ph := fposmod(t + i / 5.0, 1.0)
				var x: int = [12, 22, 34, 44, 54][i]
				var y: int = 52 - [0, 8, 14, 6, 10][i] - roundi(ph * 18.0)
				_put(img, x, y, Color(0.9, 0.5, 1.0).lerp(Color(0.35, 0.12, 0.45), ph))


# Building blocks.

func _tint(img: Image, mask: Callable, color: Color, amount: Callable) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			if c.a == 0.0 or not mask.call(x, y, c):
				continue
			var k := clampf(amount.call(x, y), 0.0, 1.0)
			if k > 0.0:
				var mixed := c.lerp(color, k)
				mixed.a = 1.0
				img.set_pixel(x, y, mixed)


## Removes loose specks inside rect so animated particles can replace them.
func _erase_specks(img: Image, rect: Rect2i) -> Image:
	var out := img.duplicate() as Image
	var big := _big_parts(img, 8)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if x < SIZE and y < SIZE and not big[y * SIZE + x]:
				out.set_pixel(x, y, CLEAR)
	return out


## Dark selective outline around the silhouette. Loose specks and sparkles are left without one.
func _outline(img: Image) -> Image:
	var out := img.duplicate() as Image
	var big := _big_parts(img, 10)
	for y in SIZE:
		for x in SIZE:
			if img.get_pixel(x, y).a > 0.0:
				continue
			var best := CLEAR
			var best_l := 9.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE or not big[ny * SIZE + nx]:
					continue
				var n := img.get_pixel(nx, ny)
				if n.get_luminance() < best_l:
					best_l = n.get_luminance()
					best = n
			if best.a > 0.0:
				var ink := best.lerp(INK, 0.78)
				ink.a = 1.0
				out.set_pixel(x, y, ink)
	return out


## Marks pixels that belong to a connected shape of at least min_size pixels.
func _big_parts(img: Image, min_size: int) -> PackedByteArray:
	var big := PackedByteArray()
	big.resize(SIZE * SIZE)
	var seen := PackedByteArray()
	seen.resize(SIZE * SIZE)
	for start in SIZE * SIZE:
		if seen[start] or img.get_pixel(start % SIZE, start / SIZE).a == 0.0:
			continue
		var group: Array[int] = [start]
		seen[start] = 1
		var i := 0
		while i < group.size():
			var at := group[i]
			i += 1
			var cx := at % SIZE
			var cy := at / SIZE
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := cx + dx
					var ny := cy + dy
					if nx < 0 or ny < 0 or nx >= SIZE or ny >= SIZE:
						continue
					var n := ny * SIZE + nx
					if not seen[n] and img.get_pixel(nx, ny).a > 0.0:
						seen[n] = 1
						group.append(n)
		if group.size() >= min_size:
			for at in group:
				big[at] = 1
	return big


## Merges near-identical shades into a small palette so color ramps read as clean bands.
## Each palette entry is a real color from the art, which keeps highlights and shadows at full strength.
func _quantize(img: Image, count: int) -> Image:
	var weights := {}
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				weights[c] = weights.get(c, 0) + 1
	var colors: Array = weights.keys()
	if colors.size() <= count:
		return img
	var labs: Array[Vector3] = []
	for c in colors:
		labs.append(_oklab(c))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var centers: Array[Vector3] = [labs[rng.randi_range(0, labs.size() - 1)]]
	var near := PackedFloat32Array()
	near.resize(labs.size())
	near.fill(INF)
	while centers.size() < count:
		var total := 0.0
		for i in labs.size():
			near[i] = minf(near[i], labs[i].distance_squared_to(centers[-1]))
			total += near[i] * weights[colors[i]]
		var pick := rng.randf() * total
		var chosen := labs.size() - 1
		for i in labs.size():
			pick -= near[i] * weights[colors[i]]
			if pick <= 0.0:
				chosen = i
				break
		centers.append(labs[chosen])
	var owner := PackedInt32Array()
	owner.resize(labs.size())
	for _round in 12:
		for i in labs.size():
			owner[i] = _closest(centers, labs[i])
		var sums: Array[Vector3] = []
		var mass := PackedFloat32Array()
		sums.resize(count)
		sums.fill(Vector3.ZERO)
		mass.resize(count)
		for i in labs.size():
			var w: float = weights[colors[i]]
			sums[owner[i]] += labs[i] * w
			mass[owner[i]] += w
		for k in count:
			if mass[k] > 0.0:
				centers[k] = sums[k] / mass[k]
	var palette: Array[Color] = []
	var palette_lab: Array[Vector3] = []
	for k in count:
		var best := -1
		var best_d := INF
		for i in labs.size():
			var d := labs[i].distance_squared_to(centers[k])
			if owner[i] == k and d < best_d:
				best_d = d
				best = i
		palette.append(colors[best] if best >= 0 else Color.BLACK)
		palette_lab.append(labs[best] if best >= 0 else Vector3(INF, INF, INF))
	var lookup := {}
	for i in colors.size():
		lookup[colors[i]] = palette[_closest(palette_lab, labs[i])]
	var out := img.duplicate() as Image
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				var mapped: Color = lookup[c]
				mapped.a = 1.0
				out.set_pixel(x, y, mapped)
	return out


func _closest(points: Array[Vector3], p: Vector3) -> int:
	var best := 0
	var best_d := INF
	for k in points.size():
		var d := points[k].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = k
	return best


func _oklab(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	var l := pow(0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b, 1.0 / 3.0)
	var m := pow(0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b, 1.0 / 3.0)
	var s := pow(0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	)


func _write_frames(id: String, count: int, fps: float) -> void:
	var lines := PackedStringArray()
	lines.append('[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (count + 2))
	lines.append("")
	lines.append('[ext_resource type="Texture2D" path="%s%s_sheet.png" id="1_sheet"]' % [IDLE_DIR, id])
	var refs := PackedStringArray()
	for f in count:
		lines.append("")
		lines.append('[sub_resource type="AtlasTexture" id="frame_%d"]' % f)
		lines.append('atlas = ExtResource("1_sheet")')
		lines.append("region = Rect2(%d, 0, %d, %d)" % [f * SIZE, SIZE, SIZE])
		refs.append('{"duration": 1.0, "texture": SubResource("frame_%d")}' % f)
	lines.append("")
	lines.append("[resource]")
	lines.append('animations = [{"frames": [%s], "loop": true, "name": &"idle", "speed": %.1f}]' % [", ".join(refs), fps])
	var file := FileAccess.open(ProjectSettings.globalize_path("%s%s_idle.tres" % [IDLE_DIR, id]), FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")


# Small helpers.

func _blank() -> Image:
	return Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)


func _px(img: Image, x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return CLEAR
	return img.get_pixel(x, y)


func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		img.set_pixel(x, y, c)


## 0 at t=0, 1 at t=0.5, back to 0 at t=1.
func _wave(t: float) -> float:
	return 0.5 - 0.5 * cos(TAU * t)


## 1 where value is at center, fading to 0 at width away. Used for shines that travel across a shape.
func _band(value: float, center: float, width: float) -> float:
	return maxf(0.0, 1.0 - absf(value - center) / width)


## Champion's greatsword runs from the pommel at (12, 30) to the tip at (52, 54).
func _blade_u(x: int, y: int) -> float:
	var d := Vector2(40, 24)
	return (Vector2(x - 12, y - 30)).dot(d) / d.length_squared()


func _blade_dist(x: int, y: int) -> float:
	var u := _blade_u(x, y)
	if u < 0.0 or u > 1.0:
		return INF
	return Vector2(x, y).distance_to(Vector2(12, 30) + Vector2(40, 24) * u)


func _is_yellow(c: Color) -> bool:
	return c.h >= 0.11 and c.h <= 0.2 and c.s > 0.45 and c.v > 0.7


func _is_gold(c: Color) -> bool:
	return c.h >= 0.07 and c.h <= 0.16 and c.s > 0.35 and c.v > 0.5


func _is_red(c: Color) -> bool:
	return (c.h < 0.03 or c.h > 0.95) and c.s > 0.5 and c.v > 0.3


func _is_skin(c: Color) -> bool:
	return c.h >= 0.02 and c.h <= 0.12 and c.s > 0.15 and c.s < 0.65 and c.v > 0.55


func _is_purple(c: Color) -> bool:
	return c.h >= 0.72 and c.h <= 0.95 and c.s > 0.3 and c.v > 0.25
