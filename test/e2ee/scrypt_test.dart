import 'package:flutter_test/flutter_test.dart';
import 'package:harness/e2ee/bytes.dart';
import 'package:harness/e2ee/scrypt.dart';

void main() {
  // RFC 7914 §12. The (N=2^17, r=8, p=1) the remote password actually uses is covered against the
  // CLI in password_link_vectors_test.dart.
  const vectors = [
    (
      '',
      '',
      16,
      1,
      1,
      '77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442'
          'fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906',
    ),
    (
      'password',
      'NaCl',
      1024,
      8,
      16,
      'fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162'
          '2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640',
    ),
    (
      'pleaseletmein',
      'SodiumChloride',
      16384,
      8,
      1,
      '7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2'
          'd5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887',
    ),
  ];

  for (final (password, salt, n, r, p, expected) in vectors) {
    test('RFC 7914: "$password" / "$salt", N=$n r=$r p=$p', () {
      final key = scrypt(
        utf8Bytes(password),
        utf8Bytes(salt),
        n: n,
        r: r,
        p: p,
        dkLen: 64,
      );
      expect(hexOf(key), expected);
    });
  }

  test('refuses an N that is not a power of two', () {
    expect(
      () => scrypt([1], [2], n: 1000, r: 1, p: 1, dkLen: 32),
      throwsArgumentError,
    );
  });
}
