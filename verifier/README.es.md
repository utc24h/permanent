# `verifier/` — verificadores de referencia

Una carpeta por lenguaje. Cada uno toma un `.jws` y comprueba, paso a paso y a la vista:

- la firma Ed25519 contra la clave de su `kid`, resuelta en [`../keys/`](../keys/)
- el compromiso: que la semilla revelada dé el hash comprometido de antemano
- la ronda de drand contra la fuente original
- que el resultado **reproduzca** desde la semilla y la ronda

> 🇬🇧 In English: [`README.md`](README.md)

| | Necesita |
|---|---|
| [`go/`](go/) | nada. Librería estándar |
| [`js/`](js/) | nada. WebCrypto, Node 18+ o un navegador |
| [`py/`](py/) | `cryptography` solo para la firma |
| [`cpp/`](cpp/) | OpenSSL y nlohmann/json |
| [`delphi/`](delphi/) | `libcrypto` solo para la firma |

**Los cinco verifican el mismo archivo y llegan al mismo resultado.** De eso se trata: si cinco
implementaciones independientes coinciden, la especificación alcanza — y si la tuya no coincide, la
especificación dice dónde mirar.

## Sobre las dependencias

La regla no es «cero dependencias». Es **nada que pueda desaparecer o pudrirse**.

OpenSSL es la librería criptográfica más auditada que existe, va a sobrevivir a todos los que lean
esto, y es más rápida que cualquier cosa hecha a mano. Donde un lenguaje no trae Ed25519 en su
librería estándar, usarla es la respuesta correcta — no una concesión. Lo que se evita es el
paquete chico de un solo mantenedor que desaparece en tres años y se lleva puesta tu compilación.

Cada carpeta declara su dependencia, de dónde sale, y qué pasa sin ella.

## Las tres respuestas

| | |
|---|---|
| `VERIFIED` | firma, compromiso y todos los números reproducen |
| `NOT VERIFIED` | algo no coincide. El archivo no es lo que dice ser |
| `UNVERIFIABLE` | no se pudo completar — sin clave, sin red, sin librería |

**La tercera no es un fallo y no hay que reportarla como tal.** «No puedo comprobar» y «esto es
falso» son respuestas distintas, y mezclarlas es como una emisión honesta termina acusada de
mentira.

## Qué NO hacen

No emiten juicio más allá de eso. Muestran el cálculo; la conclusión es de quien mira.

> ⚠️ Con una `version` que empieza en `0.`, la emisión es de **prueba y no es parte del histórico**.
> Verifica bien, y hay que leerlo como información, no como un fallo.
