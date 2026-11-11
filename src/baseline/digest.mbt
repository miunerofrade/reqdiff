// FIPS 180-4 SHA-256, implemented in-tree so request fingerprints need no
// third-party crypto dependency. Verified against the official NIST vectors.

///|
let sha256_k : Array[UInt32] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
]

///|
fn rotr32(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
fn sha256_state(data : Bytes) -> FixedArray[UInt32] {
  let state : FixedArray[UInt32] = FixedArray::from_array([
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ])
  let total = data.length()
  let padded_len = (total + 1 + 8 + 63) / 64 * 64
  let buffer : FixedArray[Byte] = FixedArray::make(padded_len, b'\x00')
  for i in 0..<total {
    buffer[i] = data[i]
  }
  buffer[total] = b'\x80'
  let bits : UInt64 = total.to_uint64() << 3
  for j in 0..<8 {
    buffer[padded_len - 8 + j] = ((bits >> ((7 - j) * 8)) & 0xFFUL)
      .to_uint()
      .to_byte()
  }
  let w : FixedArray[UInt32] = FixedArray::make(64, 0U)
  let h : FixedArray[UInt32] = FixedArray::make(8, 0U)
  let mut base = 0
  while base < padded_len {
    // Working variables start from the current chaining state (FIPS 180-4).
    for i in 0..<8 {
      h[i] = state[i]
    }
    for t in 0..<16 {
      w[t] = (buffer[base + t * 4].to_uint() << 24) |
        (buffer[base + t * 4 + 1].to_uint() << 16) |
        (buffer[base + t * 4 + 2].to_uint() << 8) |
        buffer[base + t * 4 + 3].to_uint()
    }
    for t in 16..<64 {
      let s0 = rotr32(w[t - 15], 7) ^ rotr32(w[t - 15], 18) ^ (w[t - 15] >> 3)
      let s1 = rotr32(w[t - 2], 17) ^ rotr32(w[t - 2], 19) ^ (w[t - 2] >> 10)
      w[t] = w[t - 16] + s0 + w[t - 7] + s1
    }
    for t in 0..<64 {
      let s1 = rotr32(h[4], 6) ^ rotr32(h[4], 11) ^ rotr32(h[4], 25)
      let ch = (h[4] & h[5]) ^ ((h[4] ^ 0xFFFFFFFFU) & h[6])
      let temp1 = h[7] + s1 + ch + sha256_k[t] + w[t]
      let s0 = rotr32(h[0], 2) ^ rotr32(h[0], 13) ^ rotr32(h[0], 22)
      let maj = (h[0] & h[1]) ^ (h[0] & h[2]) ^ (h[1] & h[2])
      let temp2 = s0 + maj
      h[7] = h[6]
      h[6] = h[5]
      h[5] = h[4]
      h[4] = h[3] + temp1
      h[3] = h[2]
      h[2] = h[1]
      h[1] = h[0]
      h[0] = temp1 + temp2
    }
    // Fold the compressed block into the running chaining state.
    for i in 0..<8 {
      state[i] = state[i] + h[i]
    }
    base += 64
  }
  state
}

///|
/// Lowercase hexadecimal SHA-256 digest of `data`.
pub fn sha256_hex(data : Bytes) -> String {
  let state = sha256_state(data)
  let builder = StringBuilder()
  for word in state {
    let hex = word.to_string(radix=16)
    builder.write_string("0".repeat(8 - hex.length()))
    builder.write_string(hex)
  }
  builder.to_string()
}
