# `spec/` — la especificación publicada

Esta especificación define cómo producir y comprobar resultados **verificables y auditables**
—*verifiably random and auditable*—: cualquiera puede reproducir los números desde el archivo
publicado, y el registro de lo publicado queda anclado *append-only* en dos proveedores sin relación
entre sí, con la fecha puesta por ellos.

Lo que hace falta para que **cualquiera** reproduzca los números sin nuestro código:

1. Los insumos: `seed`, `round.randomness`, `drand_round`
2. El contexto de derivación: `version|variant|round`, más `|bN` por bloque
3. El flujo: `info = contexto‖"|"‖bytes_ya_generados`, bloques de 64 bytes por HKDF-SHA256
4. El entero sin sesgo: `corte = (espacio/rango)*rango`, se descarta y se reintenta
5. Los 6 moldes, con su regla exacta
6. La convención de versión: `0.x` es prueba, un entero es histórico

> 🇬🇧 In English: [`README.md`](README.md) · Avisos firmados: [`notices.es.md`](notices.es.md)

## Por qué se publica esto y no el emisor

Se escribió un verificador en Python desde cero, usando solo el archivo y el documento, y reprodujo
**8.262 de 8.262** resultados. Si un tercero llega a los mismos números con eso, no hay nada más que
entregar.

---

## Las seis reglas globales

La ambigüedad acá es lo que hace que una emisión honesta parezca una mentira. **R2, R5 y R6 son las
tres que hacen que un verificador mal escrito acuse a un archivo legítimo.**

| | Regla |
|---|---|
| **R1** | El hex va en minúscula y sin prefijo |
| **R2** | Los hashes se computan sobre los **bytes decodificados**, nunca sobre el texto hex |
| **R3** | Las horas son UTC, RFC 3339, con `Z` |
| **R4** | Un SHA-256 son siempre 64 caracteres hex |
| **R5** | La firma se verifica sobre el **texto crudo**. Re-serializar el JSON cambia los bytes y rompe una firma que es perfectamente válida |
| **R6** | El archivo viaja en binario y no se toca. Sin recodificar, sin salto de línea al final, sin editor |

## Qué ronda de drand le toca a cada turno

**Hay un turno cada 10 minutos, en el reloj, siempre UTC:** `HH:00`, `HH:10`, `HH:20`, `HH:30`,
`HH:40`, `HH:50`. 144 turnos por día. Cualquier otro instante no es un turno y no tiene archivo.

**La ronda objetivo no se elige. Se deriva**, y eso es lo que hace imposible que nombremos una ronda
que nos convenga:

> La ronda objetivo de un turno es **aquella cuya hora nominal es exactamente la hora del turno**.
>
> ```
> ronda = (turno − genesis_time) / period + 1
> ```
>
> `genesis_time` y `period` salen de la chain de drand, que va clavada en cada archivo como
> `drand_chain_hash` y `drand_public_key`.

Cualquiera la recalcula y comprueba que el archivo nombra la ronda que tenía que nombrar. Un archivo
cuyo `drand_round` no sea esa es inválido, por bien que verifique todo lo demás.

Eso además fija cuándo nace el número: la ronda existe **en el turno**, así que el resultado no
puede existir antes de su propio turno.

## El corte es el turno

El resultado se publica unos segundos **después** del turno — es lo que tarda leer la ronda, derivar
y empujar. Nunca antes: publicar antes significaría derivar de una ronda anterior, y ahí el número
existiría antes que su turno.

De ahí sale la regla que tiene que cumplir cualquiera que construya sobre esto:

> **Nada que dependa de una emisión puede aceptar entradas después de su turno.**

Cualquiera que publique algo lo conoce antes que el lector, mientras dura la publicación. Cerrar en
el turno deja ese intervalo sin valor.

## Los turnos que faltan, y cómo comprobar que cada uno está explicado

Un turno puede faltar en el histórico. Es esperable, y **todo hueco lleva su explicación en el turno
inmediatamente anterior.** Eso es lo que hace la regla comprobable, en vez de algo que haya que
creernos.

**La regla:** mientras un turno no esté cerrado, no arranca uno nuevo. Un compromiso publicado tiene
que terminar en un `-emission` o en un `-failure`; hasta que exista alguno de los dos, el emisor no
empieza otro turno.

**Por eso un hueco se lee hacia atrás:**

```
emissions/2026/08/22/0510                falta
emissions/2026/08/22/0500-emission.jws   con  "recovery": { "code": "emitted_after_expiry", ... }
```

El turno de las 05:00 se cerró tarde. Mientras estuvo abierto, el 05:10 no pudo arrancar. Esa es toda
la explicación, y está en un archivo firmado.

**Qué cuenta como explicado.** Un hueco está explicado cuando el `-emission` del turno anterior trae
una nota `recovery`, o cuando ese turno terminó en un `-failure`. Los dos están firmados y los dos
dicen por qué.

> 🔎 **Y el reverso es la garantía: un hueco con un turno limpio antes —un `-emission` sin nota
> `recovery`— es una anomalía sin explicación, y hay que tratarla como tal.** Cualquiera puede
> recorrer el histórico y comprobar que todo hueco tiene su motivo al lado. No podemos esconder un
> turno salteado detrás de uno que se ve normal.

**Por qué una emisión tardía se publica igual.** El resultado es función determinista de una semilla
comprometida antes y de una ronda de drand nombrada antes. Publicarlo tarde no nos da ninguna
libertad — el número ya estaba fijado. Anular el turno **sí** nos la habría dado: un operador que
puede cancelar un turno demorándose puede cancelar los que no le convienen. Así que el número sale
siempre, y la demora se declara.

---

## Los tres detalles que rompen una reimplementación

No son casos raros. Todas las reimplementaciones hechas hasta hoy se estrellaron contra los tres.

**1. En las variantes simples, el molde es el nombre del grupo, no un campo.**

Solo `composite` lleva un arreglo `blocks` explícito. Todo lo demás lleva sus parámetros planos, y
el molde es la clave del grupo donde está:

```json
"discrete_uniform": { "u-0-9": { "min": 0, "max": 9, "result": 2 } }
"composite":        { "s-5-of-50-and-2-of-12": { "blocks": [ … ], "result": [[…],[…]] } }
```

**2. `random_matrix` lleva `rows` y `cols`, no `count`.** Cuántos valores sacar es `rows × cols`, y
el resultado se publica como una lista de filas.

**3. `truncated_continuous` publica `min` y `max` ya multiplicados por `scale`.** No hay que
multiplicar de nuevo. Con `min: 1000, max: 1000000, scale: 1000`, el rango se lee directo del
archivo:

```
valor = min + entero(max − min + 1)
```

## La forma de `result` depende del molde

| Molde | `result` |
|---|---|
| `discrete_uniform` | un escalar — `2` |
| `sample_without_replacement` | una lista ordenada — `[3, 11, 24]` |
| `uniform_vector_with_replacement` | una lista, el orden importa — `[1, 0, 1]` |
| `permutation` | una lista, el orden **es** el resultado — `[8, 5, 4, …]` |
| `truncated_continuous` | un escalar, se lee con `scale` — `833590` |
| `random_matrix` | una lista de filas — `[[1,4,7],[2,9,0]]` |
| `composite` | una lista por bloque — `[[7,12,30],[2]]` |
