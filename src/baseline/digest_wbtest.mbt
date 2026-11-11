///|
// Official NIST FIPS 180-4 test vectors.
test "sha256 matches NIST vectors" {
  assert_eq(
    sha256_hex(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    sha256_hex(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    sha256_hex(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
  assert_eq(
    sha256_hex(
      b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
    ),
    "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
  )
  // One million 'a' characters: exercises multi-block padding.
  let million = Bytes::makei(1000000, _ => b'a')
  assert_eq(
    sha256_hex(million),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
  )
}

///|
test "sha256 is sensitive to single-bit input changes" {
  assert_false(sha256_hex(b"abc") == sha256_hex(b"abd"))
  assert_false(sha256_hex(b"abc") == sha256_hex(b"abcd"))
}
