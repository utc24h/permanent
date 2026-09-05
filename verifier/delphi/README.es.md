# `verifier/delphi/` — verificador de referencia

```
dcc64 verify.dpr
verify.exe 1730-emission.jws [clave-publica-hex]
```

Lee un archivo, no una URL:

```
curl -s https://.../2026/08/29/1730-emission.jws -o e.jws && verify e.jws
```

La clave pública de un `kid` sale de [`../../keys/history.json`](../../keys/history.json).

## Dependencias

| | |
|---|---|
| SHA-256, HMAC, base64url, JSON | **la librería estándar** — `System.Hash`, `System.NetEncoding`, `System.JSON` |
| **Ed25519** | `libcrypto-3-x64.dll` · <https://openssl-library.org> — al lado del ejecutable |

La librería se carga en tiempo de ejecución a propósito: sin ella el verificador contesta
`UNVERIFIABLE` para la firma y comprueba todo lo demás igual. Que falte una DLL no es motivo para
contestar «falso».

Compila para Windows y para Linux. En Linux busca `libcrypto.so.3`.

## Dos cosas con las que te vas a tropezar

**`SHA256` es a la vez nombre de función y valor de enum.** Pascal no distingue mayúsculas, así que
una función llamada `Sha256` tapa a `THashSHA2.TSHA2Version.SHA256` y el compilador dice *"Not
enough actual parameters"*, que no apunta a ningún lado. Calificá el enum.

**`THashSHA2.GetHashBytes` no acepta `TBytes`** — solo `string` o `TStream`. Pasarle un string
obligaría a elegir una codificación, y la regla **R2** dice que los hashes van sobre los **bytes**.
Usá la API de instancia: `Create` · `Update` · `HashAsBytes`.

## Qué contesta

| | |
|---|---|
| `VERIFIED` | firma, compromiso y todos los números reproducen |
| `NOT VERIFIED` | algo no coincide. El archivo no es lo que dice ser |
| `UNVERIFIABLE` | no se pudo completar la comprobación |

## Qué no comprueba, a propósito

No busca la ronda de drand, y no verifica su firma **BLS** — eso necesita una librería de pairings.
Comprobá `round.randomness` vos mismo contra `https://api.drand.sh/public/<ronda>`; la ronda viaja
entera dentro del archivo.

## Usalo

Copiá `TStream_`, `DeriveBlock` y `Hkdf` en tu proyecto y ya tenés los números.

Leé primero [`../../spec/README.es.md`](../../spec/README.es.md): los tres detalles que rompen toda
reimplementación están ahí.
