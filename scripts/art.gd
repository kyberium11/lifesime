class_name Art
extends RefCounted
## Placeholder pixel art drawn in code. Replace with real sprite sheets later:
## keep the TILES name -> index mapping and swap the image in World._ready().

const S := 16
const TILES := {
	"grass": 0, "grass2": 1, "dirt": 2, "water": 3, "tree": 4, "rock": 5,
	"bush": 6, "bush_empty": 7, "campfire": 8, "shelter": 9, "garden": 10,
	"garden_empty": 11, "sign": 12,
}


static func tileset_image() -> Image:
	var img := Image.create(S * TILES.size(), S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_grass(img, 0, false)
	_grass(img, 1, true)
	_dirt(img, 2)
	_water(img, 3)
	_tree(img, 4)
	_rock(img, 5)
	_bush(img, 6, true)
	_bush(img, 7, false)
	_campfire(img, 8)
	_shelter(img, 9)
	_garden(img, 10, true)
	_garden(img, 11, false)
	_sign(img, 12)
	return img


static func pet_texture() -> ImageTexture:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 0, 3, 1, 3, 4, Color("d9863a"))
	_rect(img, 0, 10, 1, 3, 4, Color("d9863a"))
	_disc(img, 0, 8, 9, 6.0, Color("f2a65a"))
	_disc(img, 0, 8, 11, 3.5, Color("fbd9a6"))
	_rect(img, 0, 5, 8, 2, 2, Color("2b2b2b"))
	_rect(img, 0, 9, 8, 2, 2, Color("2b2b2b"))
	_px(img, 0, 4, 10, Color("f28b82"))
	_px(img, 0, 11, 10, Color("f28b82"))
	_px(img, 0, 8, 10, Color("8a4b2a"))
	return ImageTexture.create_from_image(img)


static func player_texture() -> ImageTexture:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_rect(img, 0, 4, 7, 1, 4, Color("f1c27d"))
	_rect(img, 0, 11, 7, 1, 4, Color("f1c27d"))
	_rect(img, 0, 5, 7, 6, 5, Color("3b82f6"))
	_rect(img, 0, 5, 12, 2, 3, Color("334155"))
	_rect(img, 0, 9, 12, 2, 3, Color("334155"))
	_disc(img, 0, 8, 4, 3.2, Color("f1c27d"))
	_rect(img, 0, 5, 0, 6, 3, Color("4a3426"))
	_px(img, 0, 6, 4, Color("222222"))
	_px(img, 0, 9, 4, Color("222222"))
	return ImageTexture.create_from_image(img)


# --- drawing helpers -------------------------------------------------------

static func _px(img: Image, tx: int, x: int, y: int, c: Color) -> void:
	if x >= 0 and x < S and y >= 0 and y < S:
		img.set_pixel(tx * S + x, y, c)


static func _rect(img: Image, tx: int, x: int, y: int, w: int, h: int, c: Color) -> void:
	for j in range(h):
		for i in range(w):
			_px(img, tx, x + i, y + j, c)


static func _disc(img: Image, tx: int, cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(S):
		for x in range(S):
			if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy)) <= r:
				_px(img, tx, x, y, c)


static func _ellipse(img: Image, tx: int, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(S):
		for x in range(S):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, tx, x, y, c)


# --- tiles -----------------------------------------------------------------

static func _grass(img: Image, tx: int, flowers: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + tx
	for y in range(S):
		for x in range(S):
			var r := rng.randf()
			var c := Color("5aa845")
			if r < 0.12:
				c = Color("4c9439")
			elif r < 0.2:
				c = Color("6bb853")
			_px(img, tx, x, y, c)
	if flowers:
		_px(img, tx, 3, 4, Color("ffffff"))
		_px(img, tx, 11, 9, Color("ffd23f"))
		_px(img, tx, 6, 12, Color("f28bb4"))


static func _dirt(img: Image, tx: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	for y in range(S):
		for x in range(S):
			var r := rng.randf()
			var c := Color("8a6a48")
			if r < 0.15:
				c = Color("7a5c3e")
			elif r < 0.25:
				c = Color("9a7a56")
			_px(img, tx, x, y, c)


static func _water(img: Image, tx: int) -> void:
	_rect(img, tx, 0, 0, S, S, Color("3b7fd0"))
	for x in range(2, 7):
		_px(img, tx, x, 4, Color("5a9be6"))
	for x in range(9, 14):
		_px(img, tx, x, 11, Color("5a9be6"))
	for x in range(1, 4):
		_px(img, tx, x, 13, Color("2f6bb8"))
	for x in range(10, 13):
		_px(img, tx, x, 7, Color("2f6bb8"))


static func _tree(img: Image, tx: int) -> void:
	_rect(img, tx, 7, 10, 2, 5, Color("6b4423"))
	_disc(img, tx, 8, 6, 6.0, Color("2f7d32"))
	_disc(img, tx, 6, 5, 3.0, Color("3f9a3f"))
	_disc(img, tx, 10.5, 4, 1.6, Color("52b052"))


static func _rock(img: Image, tx: int) -> void:
	_ellipse(img, tx, 8, 10, 6.0, 4.5, Color("8a8d93"))
	_ellipse(img, tx, 6.5, 8.5, 3.0, 2.0, Color("a9acb2"))
	_rect(img, tx, 4, 14, 8, 1, Color("6c6f75"))


static func _bush(img: Image, tx: int, berries: bool) -> void:
	_disc(img, tx, 8, 9, 5.5, Color("2e8b3a"))
	_disc(img, tx, 6, 8, 3.0, Color("3da34a"))
	if berries:
		for p in [Vector2i(5, 8), Vector2i(9, 7), Vector2i(10, 11), Vector2i(7, 11), Vector2i(11, 9)]:
			_rect(img, tx, p.x, p.y, 2, 2, Color("d9344a"))


static func _campfire(img: Image, tx: int) -> void:
	_rect(img, tx, 3, 12, 10, 2, Color("5a3a1e"))
	_rect(img, tx, 5, 10, 6, 2, Color("6b4423"))
	_disc(img, tx, 8, 8, 3.0, Color("ff8c1a"))
	_disc(img, tx, 8, 8.5, 1.8, Color("ffd23f"))
	_px(img, tx, 8, 4, Color("ff8c1a"))
	_px(img, tx, 8, 5, Color("ff8c1a"))
	_px(img, tx, 2, 13, Color("8a8d93"))
	_px(img, tx, 13, 13, Color("8a8d93"))


static func _shelter(img: Image, tx: int) -> void:
	_rect(img, tx, 2, 7, 12, 8, Color("b5834f"))
	for y in range(1, 8):
		var hw := int(y * 1.4) + 1
		_rect(img, tx, 8 - hw, y, hw * 2, 1, Color("c0392b"))
	_rect(img, tx, 7, 10, 3, 5, Color("4a2c17"))
	_rect(img, tx, 4, 9, 2, 2, Color("ffe9a0"))


static func _garden(img: Image, tx: int, ripe: bool) -> void:
	_rect(img, tx, 1, 4, 14, 10, Color("6b4a2b"))
	for y in [6, 9, 12]:
		_rect(img, tx, 1, y, 14, 1, Color("55391f"))
	for p in [Vector2i(3, 5), Vector2i(7, 5), Vector2i(11, 5), Vector2i(3, 8), Vector2i(7, 8), Vector2i(11, 8), Vector2i(5, 11), Vector2i(9, 11)]:
		_rect(img, tx, p.x, p.y, 1, 2, Color("49a84f"))
		if ripe:
			_px(img, tx, p.x + 1, p.y, Color("d9344a"))


static func _sign(img: Image, tx: int) -> void:
	_rect(img, tx, 7, 6, 2, 9, Color("6b4423"))
	_rect(img, tx, 3, 3, 10, 4, Color("c89b5a"))
	_rect(img, tx, 8, 3, 1, 4, Color("6b4423"))
	_px(img, tx, 3, 7, Color("c89b5a"))
