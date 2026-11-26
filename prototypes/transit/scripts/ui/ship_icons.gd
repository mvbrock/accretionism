class_name ShipIcons
extends RefCounted
## Each ship's icon: a square for a cycler, a triangle for a transport, in a
## color no other ship shares. The diagram draws the shapes; the side panel
## shows them as textures.

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


## `ship`'s color, from its place among the fleet's cyclers then transports.
static func color_of(fleet: Fleet, ship: Variant) -> Color:
	var index := (fleet.cyclers + fleet.transports).find(ship)
	var hue := fposmod(index * HUE_STEP, 1.0)
	return Color.from_ok_hsl(hue, SATURATION, LIGHTNESSES[index % LIGHTNESSES.size()])


## The square a cycler's icon fills, centered on `pos`.
static func square_rect(pos: Vector2, size := SQUARE_SIZE) -> Rect2:
	return Rect2(pos - Vector2.ONE * size / 2.0, Vector2.ONE * size)


## A triangle `length` px long, centered on `pos`, its tip pointing along `angle`.
static func triangle_points(pos: Vector2, angle: float, length := TRIANGLE_SIZE) -> PackedVector2Array:
	var ahead := Vector2.from_angle(angle)
	var side := ahead.orthogonal()
	var back := pos - ahead * length * 0.4
	return PackedVector2Array([pos + ahead * length * 0.6, back + side * length * 0.45, back - side * length * 0.45])


## `ship`'s icon as a texture SQUARE_SIZE logical px across; a transport's points up.
static func texture(fleet: Fleet, ship: Variant) -> ImageTexture:
	var side := ceili(SQUARE_SIZE * TEXTURE_SCALE)
	var color := color_of(fleet, ship)
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	if ship is Cycler:
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
