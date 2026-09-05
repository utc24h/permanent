# `verifier/py/` — verificador de referencia

```bash
python3 verify.py 1730-emission.jws
python3 verify.py https://.../2026/08/29/1730-emission.jws <clave-publica-hex>
```

Sin la clave comprueba todo menos la firma, y lo dice. La clave pública de un `kid` sale de
[`../../keys/history.json`](../../keys/history.json).

## Dependencia

| | |
|---|---|
| Hashing, HKDF, derivación | librería estándar — `hashlib`, `hmac` |
| **Firma Ed25519** | **`cryptography`** · `pip install cryptography` · <https://pypi.org/project/cryptography/> |

`cryptography` la mantiene la Python Cryptographic Authority y por debajo es OpenSSL. Sin ella el
verificador contesta `UNVERIFIABLE` para la firma en vez de adivinar; todo lo demás corre igual.

## Qué contesta

| | |
|---|---|
| `VERIFIED` | firma, compromiso y todos los números reproducen |
| `NOT VERIFIED` | algo no coincide. El archivo no es lo que dice ser |
| `UNVERIFIABLE` | no se pudo completar la comprobación |

## Qué no comprueba, a propósito

No verifica la firma **BLS** de drand: eso necesita una librería de pairings, que es un tipo de
dependencia muy distinto. En su lugar le pide la ronda a drand — la prueba de que el número es de
ellos la dan ellos. La ronda viaja entera dentro del archivo por si querés agregar la comprobación.

## Usalo

Copiá `Stream`, `derive_block` y `derive` en tu proyecto y ya tenés los números. El resto es
plomería.

Leé primero [`../../spec/README.es.md`](../../spec/README.es.md): los tres detalles que rompen toda
reimplementación están ahí.
