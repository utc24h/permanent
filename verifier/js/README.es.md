# `verifier/js/` — verificador de referencia

Solo WebCrypto. Sin dependencias, nada que instalar. Node 18 o superior.

```bash
node verify.mjs 1730-emission.jws
node verify.mjs https://.../2026/08/29/1730-emission.jws <clave-publica-hex>
```

Sin la clave comprueba todo menos la firma, y lo dice. La clave pública de un `kid` sale de
[`../../keys/history.json`](../../keys/history.json).

## Qué contesta

| | |
|---|---|
| `VERIFIED` | firma, compromiso y todos los números reproducen |
| `NOT VERIFIED` | algo no coincide. El archivo no es lo que dice ser |
| `UNVERIFIABLE` | no se pudo completar — sin clave, sin red, sin Ed25519 |

**La tercera no es un fallo.** «No puedo comprobar» y «esto es falso» son respuestas distintas.

## En un navegador

`derive()`, `deriveBlock()` y `Stream` corren sin cambios: solo usan `crypto.subtle`. Lo único
específico de Node es `readSource()`, que para URLs ya usa `fetch`.

Ed25519 en WebCrypto es reciente. Si el entorno no lo tiene, el verificador dice `UNVERIFIABLE` para
la firma en vez de adivinar.

## Qué no comprueba, a propósito

No verifica la firma **BLS** de drand: eso necesita una librería de pairings, y este archivo no tiene
dependencias. En su lugar le pide la ronda a drand — la prueba de que el número es de ellos la dan
ellos. La ronda viaja entera dentro del archivo por si querés agregar la comprobación vos.

## Usalo

Para eso está. Copiá `Stream`, `deriveBlock` y `derive` en tu proyecto y ya tenés los números. El
resto es plomería.

Leé primero [`../../spec/README.es.md`](../../spec/README.es.md): los tres detalles que rompen toda
reimplementación están ahí.
