extends RefCounted
## Passwortschutz ohne Klartext: Der Host speichert nur Salt + abgeleiteten Schlüssel
## (PBKDF2-HMAC-SHA256). Beim Beitritt beweist der Client die Kenntnis des Passworts
## per Challenge-Response (HMAC über Host-Nonce + Client-Nonce). Das Passwort selbst
## wird nie übertragen.

const ITERATIONS := 2500

static func random_bytes(n: int) -> PackedByteArray:
	return Crypto.new().generate_random_bytes(n)

static func derive(password: String, salt: PackedByteArray) -> PackedByteArray:
	var crypto := Crypto.new()
	var key := password.to_utf8_buffer()
	if key.is_empty():
		key = PackedByteArray([0])
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := crypto.hmac_digest(HashingContext.HASH_SHA256, key, block)
	var t := u.duplicate()
	for i in ITERATIONS - 1:
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, key, u)
		for k in t.size():
			t[k] = t[k] ^ u[k]
	return t

static func proof(key: PackedByteArray, host_nonce: PackedByteArray, client_nonce: PackedByteArray) -> PackedByteArray:
	var msg := host_nonce.duplicate()
	msg.append_array(client_nonce)
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, msg)

static func verify(key: PackedByteArray, host_nonce: PackedByteArray, client_nonce: PackedByteArray, given: PackedByteArray) -> bool:
	if given.size() != 32 or client_nonce.size() < 16:
		return false
	return Crypto.new().constant_time_compare(proof(key, host_nonce, client_nonce), given)
