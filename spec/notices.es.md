# `spec/notices.md` — qué publicamos cuando algo cambia o se rompe

## Por qué existe este documento

**Este sistema es una constitución que se autorregula.**

Nadie puede saber hoy qué va a hacer falta cambiar en 2031. Lo que sí se puede es dejar escrito, de
antemano y por adelantado, **cómo se cambia sin romper la confianza** — y quedar atado a eso.

Es el mismo motivo por el que existen los **RFC**: un protocolo que va a durar décadas no se
sostiene sobre la buena voluntad de quien lo mantiene, sino sobre un procedimiento público que
cualquiera puede comprobar que se siguió. La regla no protege al que la escribe: lo obliga.

De ahí sale la propiedad que hace verificable todo lo demás: **si un cambio requería una nota y la
nota no está, el cambio es ilegítimo** — y eso lo determina un tercero mirando fechas, sin
preguntarnos nada.

---

Tres instrumentos firmados, y no son intercambiables. Cada uno contesta una pregunta distinta, y
saber cuál corresponde es lo que te permite darte cuenta si nos lo salteamos.

> 🇬🇧 In English: [`notices.md`](notices.md)

| Instrumento | Contesta | Cuándo |
|---|---|---|
| **Nota de cambio** | "esto va a cambiar" | **antes** de un cambio planificado |
| **Nota de publicación** | "pasó esto y hay que saberlo ahora" | cuando pasa |
| **Parte de incidente** | "este turno no salió como debía" | pegado al turno |

---

## 1. Nota de cambio

Se publica **antes** del cambio, nunca después. Si aparece un cambio que la necesitaba y la nota no
está, ese cambio es ilegítimo — para eso existe la regla.

Hace falta para todo lo que altere lo que un verificador tiene que hacer:

- Subir el campo `version`. Este no es cosmético: `version` entra en el contexto de derivación, así
  que subirlo **cambia todos los números**. Primero sale la nota, después el código.
- Agregar o sacar una variante del catálogo.
- Cambiar la fuente de aleatoriedad.
- Cambiar el formato del archivo, las reglas, o las seis convenciones globales.

Lleva: qué cambia, por qué, desde cuándo, y cuál es el primer turno que corre con las reglas
nuevas. Todo lo publicado antes de ese turno sigue reproduciendo con las reglas viejas — que es
justamente para lo que la versión viaja adentro de cada archivo.

## 2. Nota de publicación

Para lo que no se planifica: una clave comprometida, un proveedor perdido, un defecto encontrado en
algo ya publicado. Es la única de las tres que se escribe bajo presión, así que su forma es chica a
propósito.

Lleva: el instante UTC, un `code` de la lista cerrada de abajo, qué pasó, qué se hizo, y qué debería
comprobar un tercero. Va en Markdown y **sin firma**, a propósito: la nota informa, no prueba.
Si la clave estuviera en manos ajenas, firmar con ella «me robaron la clave» no probaría nada —
el que la tiene puede firmar lo mismo. Lo que la respalda es dónde vive: `permanent` es
append-only y la fecha del commit la pone el proveedor, no nosotros.

```
key_compromised       una clave de firma está, o puede estar, en manos ajenas
anchor_lost           un repositorio desapareció, o dejó de aceptar escrituras
defect_published      se encontró un defecto en algo ya publicado
service_interrupted   se dejó de emitir, y no fue un turno suelto
```

La lista es cerrada por el mismo motivo que la de los incidentes: para que la frase se pueda armar
en cualquier idioma, y para que no podamos suavizar una mala semana con una redacción que nadie
compara.

**Nunca reescribe nada.** Un archivo publicado no se corrige, no se borra y no se reemplaza — la
nota dice qué tiene de malo y se queda al lado. Un histórico que se puede corregir es un histórico
en el que hay que confiar.

## 3. Parte de incidente

Va pegado a un turno que no salió como debía. Es firmado, va a `incidents/` en el repositorio del
año, y —acá está lo que importa— **puede existir sin emisión**: es la única forma de explicar un
turno donde no se publicó absolutamente nada.

Su forma:

| Campo | |
|---|---|
| `type` | `"incident"` |
| `status` | `"unresolved"` o `"resolved"` |
| `emission` | el turno al que pertenece |
| `part` | `1`, `2`, `3`… la secuencia, cuando un turno necesita varios |
| `reason` | **un identificador, nunca prosa** |
| `reason_data` | los números detrás del motivo |
| `opened_at_utc` | cuándo se abrió |
| `variant` | la variante afectada, si el incidente es de una sola. Ausente = todas |
| `attempts` | qué se intentó y qué contestó cada anclaje, con sus marcas de tiempo |
| `unanchored_commitment` | el compromiso que se firmó y **nunca se ancló a tiempo**. Va como evidencia de auditoría, no como compromiso válido |
| `warning_en` | la advertencia que acompaña al anterior, en inglés, dentro del propio archivo firmado |

Los cuatro últimos solo aparecen cuando corresponden.

⚠️ **`unanchored_commitment` no es un compromiso.** Llegaría con fecha posterior a su ronda, así que
se lee como que llegamos tarde — y por eso viaja con su advertencia adentro y con otro nombre de
campo. No hay controversia si la etiqueta dice la verdad; la controversia nace cuando algo se
presenta como lo que no es.

`reason` sale de una lista cerrada para que cualquiera pueda armar la frase en cualquier idioma, y
para que no podamos tapar un turno malo con una redacción que nadie compara:

```
anchor_timeout        la escritura salió y no vimos la respuesta
anchor_unreachable    ningún repositorio aceptó la escritura
anchor_too_late       el compromiso llegó cuando su ronda ya existía
beacon_unreachable    no se pudo leer la ronda de drand dentro del plazo
beacon_invalid        un relay contestó algo que no verifica
unknown_state         no se pudo determinar qué pasó
```

## Las claves: qué se puede hacer con el registro

El registro de claves (`keys/history.json`) es la raíz de todo: dice qué clave pública corresponde
a cada `kid`, y sin él ninguna firma se puede comprobar. Por eso los cambios sobre él son los más
regulados de todo el sistema.

**Solo hay una operación legítima: agregar una época.**

| Operación | ¿Se puede? | Con qué instrumento |
|---|---|---|
| Agregar una clave nueva | **sí** | nota de cambio, publicada **antes** |
| Agregar una clave nueva de urgencia | **sí** | nota de publicación, `code: key_compromised` |
| Cambiar el valor de una entrada existente | **nunca** | — |
| Quitar una entrada | **nunca** | — |

Quitar una entrada no libera nada: **mata todo lo que esa clave firmó.** Sin su clave pública, ese
tramo del histórico deja de poder verificarse para siempre. Por eso una rotación limita el daño
**hacia adelante y no hacia atrás**, y por eso las claves viejas se quedan aunque no se usen más.

Cada época deja además su propio archivo, con el `kid` de nombre —y el `kid` es una fecha, así que
la historia se ordena sola. Los archivos anteriores no se tocan nunca. El detalle del formato y de
cómo se lee está en [`keys/README.es.md`](../keys/README.es.md).

### Cómo se cambia una clave, y qué prueba cada cosa

No existe la revocación: nadie puede «apagar» una clave publicada. Lo que se hace es **declarar
desde cuándo dejamos de usarla** y empezar a emitir con la nueva. La vieja queda en el registro
para siempre, porque sigue siendo la única forma de comprobar lo que firmó.

Una clave privada perdida o filtrada **no altera nada del pasado** —lo publicado ya está anclado,
con fecha de terceros y en repositorios que no son solo nuestros— pero **puede molestar en el
presente**, porque quien la tenga puede fabricar archivos que verifican.

Los tres casos no se defienden igual, y conviene no confundirlos:

| Caso | ¿Se firma la transición con la clave vieja? | Qué da la garantía |
|---|---|---|
| **Rotación planificada** | **sí**, y además con la nueva | la firma con la vieja: el mismo dueño entrega el relevo |
| **Clave perdida** | no se puede: ya no existe | el anclaje — la entrada nueva llega con fecha de un tercero |
| **Clave robada** | se puede, **pero no prueba nada**: quien la robó también puede firmar | quién publicó primero, y por el canal de siempre |

> 🔑 **Por eso, ante una filtración, publicar rápido no es prolijidad: es la defensa entera.**
> No ganamos porque nuestra firma sea distinta —no lo es—, sino porque la nota llega **antes**,
> anclada, en los mismos repositorios donde venimos publicando desde el primer turno. El que se
> aparezca después tiene que explicar por qué su versión no está en ningún lado.

### El procedimiento, en orden

1. **Detener la emisión.** Detener es parte del procedimiento, no una falla: seguir emitiendo con
   una clave dudosa ensucia el histórico con archivos que después hay que discutir uno por uno.
2. **Agregar la clave nueva** al registro, como una época más.
3. **Publicar la nota**, que dice el tramo exacto —desde qué turno hasta qué turno— en el que la
   clave vieja pudo estar comprometida. Firmada con la clave nueva, y también con la vieja si
   todavía se tiene y el caso lo justifica.
4. **Reanudar** emitiendo con la nueva.

El tramo declarado es lo que importa: **fuera de él, todo lo firmado con la clave vieja sigue
valiendo.** Una filtración no invalida cuatro años de histórico, invalida una ventana — y decir
cuál es esa ventana, con precisión y por escrito, es exactamente para lo que existen estos
instrumentos.

### Dónde se publica la respuesta, y por qué no en el portal

La nota va **a los repositorios de anclaje**, no al sitio. El portal la muestra porque es cómodo,
pero no es donde vive la prueba.

El motivo es el que ordena todo el diseño: **un dominio se pierde.** Un reclamo al registrador lo
suspende sin juicio y en días, un proveedor cierra una cuenta, un servidor se apaga. Si la
recuperación dependiera del sitio, bastaría con voltear el sitio para que no pudiéramos
respondernos.

En cambio la nota entra donde ya está todo lo demás:

- en **dos proveedores independientes**, que no son nuestros;
- en una historia **continua desde el primer turno**, que no se puede reescribir sin dejar rastro;
- con **fecha puesta por ellos**, no por nosotros.

Por eso, si algún día este portal no responde, **el sistema no se cayó**: se cayó una comodidad.
Los archivos, el registro de claves, la especificación y las notas siguen donde siempre, y se leen
sin nosotros.

> **Y de ahí sale la única forma de reconocer un impostor.** Si aparece otro sitio diciendo ser
> este, con una nota firmada con una clave vieja, no hay que creerle ni a él ni a nosotros: hay
> que mirar **dónde está su historia**. La nuestra viene sin cortes desde el primer turno, anclada
> y fechada por terceros. La suya empieza el día que apareció.

### Cómo lo comprobás, sin creernos nada

```bash
git log --follow -p -- keys/history.json
```

Tiene que mostrar **únicamente líneas agregadas**. Ni una modificada, ni una borrada. Si aparece
otra cosa, ahí está la prueba y no hace falta discutirla con nosotros.

> ⚠️ **Alcance honesto, y conviene decirlo acá también:** esto protege contra el repudio —no
> podemos negar después lo que publicamos antes— pero **no prueba honestidad**. Y hoy solo lo puede
> ejercer alguien capaz de leer una historia de git.

---

## Dónde vive cada cosa

**El criterio: reglas donde se revisan, hechos donde ocurrieron.**

| Qué | Dónde |
|---|---|
| Estas reglas | `permanent` → `spec/notices.md` |
| Cada nota de cambio y cada nota de publicación | `permanent` → `spec/NNNN-*.md` |
| Cada parte de incidente | repositorio del año → `<año>/incidents/` |

No es una preferencia de orden, y las dos familias **no prometen lo mismo**:

| | Qué garantiza | Cómo se comprueba |
|---|---|---|
| `<año>/` | **Nada cambia nunca.** Ningún archivo se modifica ni se borra | un solo comando sobre el historial |
| `permanent/` | **Nada se quita ni se altera. Solo se agrega** | el historial de cada archivo muestra únicamente líneas nuevas |

Los partes de incidente van al año porque son **hechos**, y pertenecen al año en que ocurrieron.

### El permanente SÍ se modifica, y hace falta que pueda

Decir «acá nadie edita nunca» sería falso. Si una clave de firma se pierde o queda en manos ajenas
**hay que cambiarla**, y eso toca `keys/history.json`. Lo que no ocurre nunca es reescribir.

Ante una clave comprometida:

1. Se **agrega** una época nueva al registro, con la clave nueva.
2. La entrada vieja **se queda para siempre**. Borrarla mataría todo lo que esa clave firmó: sin su
   clave pública, ese histórico deja de poder verificarse y se muere con ella.
3. Se publica una **nota de publicación** con `code: key_compromised` diciendo desde cuándo no se
   puede confiar en la vieja.

Por eso el cambio de significado va en un documento **nuevo** y no encima del viejo. Una rotación
limita el daño **hacia adelante, no hacia atrás** — y lo que protege al pasado no es haber
destruido nada, sino que estos repositorios sean append-only, lleven fecha de un tercero y no sean
solo nuestros.

> **La comprobación, y es mecánica:** el historial de `keys/history.json` tiene que mostrar
> **únicamente líneas agregadas**. Ni una modificada, ni una borrada. Si alguna vez ves lo
> contrario, no hace falta que discutas con nosotros: ahí está la prueba.

---

## Este documento también se cambia, y con sus propias reglas

Nada de lo de arriba es definitivo. Va a haber cosas que hoy no se pueden prever, y algunas de
estas reglas van a resultar equivocadas. **Eso está contemplado: cambiarlas es legítimo.**

Lo que no es legítimo es cambiarlas **en silencio**.

> **Este documento se rige por la regla 1 de este documento.** Modificarlo requiere una **nota de
> cambio, publicada antes**, igual que cambiar el formato de un archivo o el catálogo de variantes.
> Si alguna vez encontrás que estas reglas cambiaron y no hay nota que lo anuncie, **ese cambio es
> ilegítimo** — por la propia regla que estás leyendo.

Es la parte que lo convierte en una constitución y no en un reglamento: **se aplica a sí misma.**
Un texto que dice cómo se cambia todo, pero que puede cambiarse sin avisar, no obliga a nadie — y
menos que a nadie, a quien lo escribió.

Por eso la garantía no depende de que sigamos siendo los mismos, ni de que sigamos pensando igual:

```bash
git log --follow -p -- spec/notices.md
```

La historia de este archivo es pública, append-only y con fecha de terceros, igual que todo lo
demás. Cada versión que existió sigue ahí, y se puede leer al lado de la nota que la anunció.

**Si las dos no coinciden, la que vale es la que está anclada — y nosotros tenemos que explicarnos.**

---

## Para qué te sirve

Todo hueco del histórico tiene un archivo firmado al lado, y su motivo sale de una lista fija. Así
la comprobación es mecánica y no depende de leer nuestra prosa:

> **Un hueco sin nada al lado es una anomalía. Tratalo como tal.**

No podemos esconder un turno salteado detrás de uno que se ve normal, ni explicarlo con una
redacción inventada después.
