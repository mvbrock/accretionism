class_name ShipIcons
extends RefCounted
## Each ship's icon: a square for a cycler, a triangle for a transport, in a
## color no other ship shares. The diagram draws the shapes; the side panel
## shows them as textures. Main builds one for the fleet it loads.

const SQUARE_SIZE := 14.4
const TRIANGLE_SIZE := 12.0

## Consecutive ships step round the hue circle by the golden ratio, so no two
## ships share a hue and neighbors in the fleet list are far apart.
const HUE_STEP := 0.618034
const SATURATION := 0.9
## Alternate ships are lighter, to separate hues that land close together.
const LIGHTNESSES := [0.68, 0.8]

## Textures are drawn at this many pixels per logical pixel and shown at
## logical size, so they stay sharp on a HiDPI display.
const TEXTURE_SCALE := 4
## Samples per pixel along each axis, for smooth edges.
const SUPERSAMPLE := 4


## Ship -> Color, from each ship's place in Fleet.ships().
var _colors := {}
## Ship -> ImageTexture, drawn the first time it is asked for.
var _textures := {}


func _init(fleet: Fleet) -> void:
	var ships := fleet.ships()
	for index in ships.size():
		var hue := fposmod(index * HUE_STEP, 1.0)
		_colors[ships[index]] = Color.from_ok_hsl(hue, SATURATION, LIGHTNESSES[index % LIGHTNESSES.size()])


func color_of(ship: Variant) -> Color:
	return _colors[ship]


## `ship`'s icon as a texture about SQUARE_SIZE logical px across; a transport's points up.
func texture(ship: Variant) -> ImageTexture:
	if not _textures.has(ship):
		_textures[ship] = _draw_texture(ship is Cycler, color_of(ship))
	return _textures[ship]


## The square a cycler's icon fills, centered on `pos`.
static func square_rect(pos: Vector2, size := SQUARE_SIZE) -> Rect2:
	return Rect2(pos - Vector2.ONE * size / 2.0, Vector2.ONE * size)


## A triangle `length` px long, centered on `pos`, its tip pointing along `angle`.
static func triangle_points(pos: Vector2, angle: float, length := TRIANGLE_SIZE) -> PackedVector2Array:
	var ahead := Vector2.from_angle(angle)
	var side := ahead.orthogonal()
	var back := pos - ahead * length * 0.4
	return PackedVector2Array([pos + ahead * length * 0.6, back + side * length * 0.45, back - side * length * 0.45])


static func _draw_texture(is_square: bool, color: Color) -> ImageTexture:
	var side := ceili(SQUARE_SIZE * TEXTURE_SCALE)
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	if is_square:
		image.fill(color)
		return ImageTexture.create_from_image(image)
	var length := TRIANGLE_SIZE * TEXTURE_SCALE
	# Its tip is 0.6 of its length ahead of its center; this centers it vertically.
	var triangle := triangle_points(Vector2(side / 2.0, length * 0.6 + (side - length) / 2.0), -PI / 2.0, length)
	for y in side:
		for x in side:
			var inside := 0
			for sy in SUPERSAMPLE:
				for sx in SUPERSAMPLE:
					var sample := Vector2(x + (sx + 0.5) / SUPERSAMPLE, y + (sy + 0.5) / SUPERSAMPLE)
					if Geometry2D.is_point_in_polygon(sample, triangle):
						inside += 1
			image.set_pixel(x, y, Color(color, float(inside) / (SUPERSAMPLE * SUPERSAMPLE)))
	return ImageTexture.create_from_image(image)
