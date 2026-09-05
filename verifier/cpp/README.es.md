# `verifier/cpp/` — verificador de referencia

```bash
g++ -std=c++17 -O2 verify.cpp -lcrypto -o verify
./verify 1730-emission.jws [clave-publica-hex]
```

Lee un archivo, no una URL:

```bash
curl -s https://.../2026/08/29/1730-emission.jws -o e.jws && ./verify e.jws
```

La clave pública de un `kid` sale de [`../../keys/history.json`](../../keys/history.json).

## Dependencias

| | |
|---|---|
| **OpenSSL** (`libcrypto`) | SHA-256, HMAC y Ed25519 · <https://openssl-library.org> · `apt install libssl-dev` |
| **nlohmann/json** | solo cabecera · <https://github.com/nlohmann/json> · `apt install nlohmann-json3-dev` |

Las dos están empaquetadas en toda distribución y ninguna va a desaparecer. Escribir un parser JSON
o un hash a mano dentro de un verificador es como un verificador termina acusando a un archivo
honesto.

## Qué contesta

| | |
|---|---|
| `VERIFIED` | firma, compromiso y todos los números reproducen |
| `NOT VERIFIED` | algo no coincide. El archivo no es lo que dice ser |
| `UNVERIFIABLE` | no se pudo completar la comprobación |

## Qué no comprueba, a propósito

No busca la ronda de drand — no tiene cliente HTTP y no lo necesita para la derivación. Comprobá
`round.randomness` vos mismo contra `https://api.drand.sh/public/<ronda>`; la ronda viaja entera
dentro del archivo.

Tampoco verifica la firma **BLS** de drand: eso necesita una librería de pairings, un tipo de
dependencia muy distinto.

## Usalo

Copiá `Stream`, `deriveBlock` y el bucle de `main` en tu proyecto y ya tenés los números.

Leé primero [`../../spec/README.es.md`](../../spec/README.es.md): los tres detalles que rompen toda
reimplementación están ahí.
