class_name LZString

## Port of lz-string decompressFromEncodedURIComponent (the encoding Last Epoch Tools uses for ids).
## Reference: standard lz-string `_decompress(length, 32, getNextValue)`.

const ALPHABET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"
const RESET_VALUE: int = 32


## Bit reader over 6-bit input codes (most significant bit of each code first).
class _Reader:
	var codes: PackedInt32Array = PackedInt32Array()
	var val: int = 0
	var position: int = RESET_VALUE
	var index: int = 1
	var length: int = 0

	func _init(input_codes: PackedInt32Array) -> void:
		codes = input_codes
		length = input_codes.size()
		val = _code(0)

	func _code(i: int) -> int:
		return codes[i] if i < length else 0

	## Reads `count` bits, least significant first (as lz-string does).
	func bits(count: int) -> int:
		var result: int = 0
		var power: int = 1
		var max_power: int = 1 << count
		while power != max_power:
			var resb: int = val & position
			position >>= 1
			if position == 0:
				position = RESET_VALUE
				val = _code(index)
				index += 1
			if resb > 0:
				result |= power
			power <<= 1
		return result


## Decodes an lz-string "encoded URI component" string; "" on empty or malformed input.
static func decompress_from_encoded_uri(input: String) -> String:
	if input == "":
		return ""
	var text: String = input.replace(" ", "+")
	var codes := PackedInt32Array()
	for i in range(text.length()):
		var code: int = ALPHABET.find(text[i])
		if code < 0:
			return ""
		codes.append(code)
	return _decompress(codes)


static func _decompress(codes: PackedInt32Array) -> String:
	var reader := _Reader.new(codes)
	var dictionary: Dictionary = {0: "0", 1: "1", 2: "2"}
	var enlarge_in: int = 4
	var dict_size: int = 4
	var num_bits: int = 3
	var result: String = ""

	var first: int = reader.bits(2)
	var c: String
	match first:
		0:
			c = char(reader.bits(8))
		1:
			c = char(reader.bits(16))
		_:
			return ""
	dictionary[3] = c
	var w: String = c
	result += c

	while true:
		if reader.index > reader.length:
			return ""
		var code: int = reader.bits(num_bits)
		match code:
			0:
				dictionary[dict_size] = char(reader.bits(8))
				dict_size += 1
				code = dict_size - 1
				enlarge_in -= 1
			1:
				dictionary[dict_size] = char(reader.bits(16))
				dict_size += 1
				code = dict_size - 1
				enlarge_in -= 1
			2:
				return result
		if enlarge_in == 0:
			enlarge_in = 1 << num_bits
			num_bits += 1

		var entry: String
		if dictionary.has(code):
			entry = dictionary[code]
		elif code == dict_size and w != "":
			entry = w + w[0]
		else:
			return ""
		result += entry

		dictionary[dict_size] = w + entry[0]
		dict_size += 1
		enlarge_in -= 1
		w = entry
		if enlarge_in == 0:
			enlarge_in = 1 << num_bits
			num_bits += 1
	return result
