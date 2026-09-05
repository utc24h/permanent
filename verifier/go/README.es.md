# `verifier/go/` — verificador de referencia

Solo librería estándar. Nada que instalar, nada en qué confiar.

```bash
go run . 1730-emission.jws
go run . https://.../2026/08/29/1730-emission.jws
go run . 1730-emission.jws <clave-publica-hex>
```

Sin la clave comprueba todo menos la firma, y lo dice. La clave pública de un `kid` sale de
[`../../keys/history.json`](../../keys/history.json).

## Qué contesta

| | |
|---|---|
| `VERIFIED` | firma, compromiso y todos los números reproducen |
| `NOT VERIFIED` | algo no coincide. El archivo no es lo que dice ser |
| `UNVERIFIABLE` | no se pudo completar la comprobación — sin clave, sin red |

**La tercera no es un fallo y no hay que reportarla como tal.** «No puedo comprobar» y «esto es
falso» son respuestas distintas, y un verificador que las mezcla es peor que ninguno.

## Qué comprueba

1. La **firma Ed25519**, sobre el texto crudo de `header.payload`
2. Que `SHA-256(seed)` coincida con `seed_sha256`
3. Que la ronda de drand traiga de verdad ese `randomness` — se le pregunta a drand, no a nosotros
4. Que **las 34 variantes** reproduzcan desde la semilla y la ronda

## Qué no comprueba, a propósito

No verifica la firma **BLS** de drand. Eso necesita una librería de pairings, o sea una dependencia
en cada lenguaje y una compilación que la mitad de los lectores no puede correr. En su lugar le
pregunta la ronda a drand: la prueba de que el número es de ellos la dan ellos.

Si querés también la comprobación BLS, agregala con la librería de tu lenguaje — la ronda viaja
entera dentro del archivo, con `signature` y `previous_signature`, así que no falta nada.

## Usalo

Para eso está. Son ~300 líneas y lo interesante son `derive`, `deriveBlock` y `stream` — copiá eso
en tu proyecto y ya tenés los números. El resto es plomería.

Leé primero [`../../spec/README.es.md`](../../spec/README.es.md): los tres detalles que rompen toda
reimplementación están ahí, y te vas a estrellar contra los tres.
