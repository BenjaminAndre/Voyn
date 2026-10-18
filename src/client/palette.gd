class_name Palette
extends RefCounted
## Every colour the client uses, in one place (GDD R9.3, user's rule from playtest round 2):
## secondary colours belong to the terrain, primary colours to the Sides.
##   Terrain: purple = corruption (Corrupted lighter, Blighted darker), green = purity (Pure
##     lighter, Thriving darker), Neutral = plain stone. Orange is reserved for a future terrain layer.
##   Sides: blue = us, red = them, yellow = neutral (Arena interactables, later).
##   Fighters differ by shape, never by hue: the Side sets the colour.
##   Plan overlays: four shades of blue, light to dark: zone, path, predicted position, target + Area.

## Terrain by karma, Blighted (-2) to Thriving (+2).
const TERRAIN: Array[Color] = [
	Color(0.24, 0.10, 0.34),  # Blighted: dark purple
	Color(0.60, 0.42, 0.74),  # Corrupted: light purple
	Color(0.66, 0.67, 0.68),  # Neutral: plain stone
	Color(0.68, 0.86, 0.60),  # Pure: light green
	Color(0.14, 0.50, 0.27),  # Thriving: dark green
]
const PILLAR: Color = Color(0.36, 0.37, 0.41)

## Forecast markers and the Land meter use the terrain purple and green.
const CORRUPT: Color = Color(0.62, 0.32, 0.86)
const PURIFY: Color = Color(0.26, 0.84, 0.42)

## Sides.
const US: Color = Color(0.17, 0.42, 0.92)
const THEM: Color = Color(0.86, 0.17, 0.17)
const NEUTRAL_SIDE: Color = Color(0.95, 0.82, 0.14)

## The team colour for plan overlays, light to dark: 1 zone, 2 path, 3 predicted position, 4 target + Area.
const US_SHADES: Array[Color] = [
	Color(0.62, 0.78, 1.00, 0.34),
	Color(0.40, 0.62, 1.00, 0.52),
	Color(0.20, 0.42, 0.96, 0.62),
	Color(0.07, 0.20, 0.66, 0.74),
]
## Threat zones: red, because they are the Monsters'.
const THREAT: Color = Color(0.86, 0.14, 0.14, 0.30)

## Text and chrome: neutral, never a Side or terrain colour.
const TEXT_DAMAGE: Color = Color(1.0, 0.32, 0.32)
const TEXT_PLAIN: Color = Color(0.95, 0.96, 0.98)
const TEXT_MUTED: Color = Color(0.72, 0.74, 0.78)
const CAST_FLASH: Color = Color(1.0, 1.0, 1.0, 0.5)
const METER_NOW: Color = Color(1.0, 1.0, 1.0)
const METER_AFTER: Color = Color(0.72, 0.74, 0.8)


## Perceived brightness, 0 (black) to 1 (white).
static func luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
