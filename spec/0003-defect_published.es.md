# Nota de publicación 0003

| | |
|---|---|
| **Publicada** | 2026-09-24 |
| **Código** | `defect_published` |
| **Turnos afectados** | 2026-09-24, de 11:10 a 15:30 UTC |

## Qué pasó

El **24 de septiembre de 2026** GitLab tuvo un incidente que declaró como
`Partial Service Disruption` en `Website` y `Git Operations`. Lo abrió una alerta automática a las
**13:27 UTC**, lo declaró públicamente a las 13:48 y lo cerró como `All Systems Operational` antes de
las **21:12 UTC**: unas **siete horas y media** de interrupción declarada. La severidad bajó de 2 a 3
en el camino.

La causa que publicó es el **agotamiento de descriptores de archivo** en el servicio que le da acceso
a los repositorios — es lo que su propio registro del incidente declara, con esas palabras.

Este sistema siguió emitiendo. **Todos los turnos del día se publicaron, ninguno se perdió**, y cada
uno tiene su compromiso y su emisión anclados, firmados y verificables. GitHub aceptó todas las
escrituras.


**El defecto no está en lo que se emitió: está en lo que este sistema dijo sobre lo que pasó.**

Siete partes de incidente, firmados y publicados, declaran que un archivo faltaba en GitLab cuando
el archivo **estaba anclado en GitLab**:

| Parte | Declara faltante | Realidad |
|---|---|---|
| `incidents/2026/09/24/1110-01.jws` | `1110-commitment.jws` | está en GitLab |
| `1300-01.jws` | `1300-commitment.jws`, `1300-emission.jws` | están los dos |
| `1450-01.jws` | `1450-commitment.jws` | está |
| `1500-01.jws` | `1500-commitment.jws` | está |
| `1510-01.jws` | `1510-commitment.jws` | está |
| `1520-01.jws` | `1520-commitment.jws` | está |
| `1530-01.jws` | `1530-commitment.jws`, `1530-emission.jws` | están los dos |

Y un octavo, `1440-01.jws`, acierta a medias: `1440-commitment.jws` falta de verdad en GitLab, pero
`1440-emission.jws` está anclado ahí.

Los otros nueve partes del día, de los turnos 13:10 a 14:30, **dicen la verdad**: esos archivos de
verdad no están en GitLab, porque durante esa hora y veinte minutos el proveedor no aceptó ninguna
escritura.

## Por qué pasó

Cuando una escritura sale y la respuesta no vuelve, el emisor no sabe si entró. Para averiguarlo
pregunta por el archivo con una segunda consulta, separada de la escritura.

El reintento posterior recibía de GitLab una respuesta explícita:

```
400 Bad Request — A file with this name already exists
```

Eso es el proveedor afirmando que el archivo está. Pero el emisor no tomaba esa respuesta sola:
exigía la confirmación de la segunda consulta. Y durante el incidente esa consulta tardaba entre 8 y
10 segundos contra un plazo de 10, así que muchas veces no volvía. **Sin confirmación, el anclaje se
anotaba como faltante.**

El resultado dependía de si una lectura entraba en su plazo. Dos turnos consecutivos con la misma
realidad dan resultados opuestos: el de las 15:30 declaró faltante exactamente lo que el de las
15:40 confirmó como presente, diez minutos después.

**Un resultado que sale de una carrera contra el reloj no puede viajar dentro de un archivo firmado
como si fuera un hecho.**

El `1110-01.jws` lo muestra dentro de sí mismo: declara `missing: ["gitlab"]` y unos campos más
abajo, en su propia bitácora de intentos, lleva el `400 A file with this name already exists` que lo
desmiente.

## Qué se encontró investigándolo

**1. Dos cosas distintas viajaban en el mismo campo.** «Se comprobó que no está» y «no se pudo
comprobar» terminaban las dos en `missing`. La regla que lo prohíbe estaba escrita en el emisor —*no
saber no autoriza a concluir que no llegó*— y se perdía una capa más arriba, donde los dos casos
caían en la misma rama.

**2. La comprobación no respetaba el reloj del turno.** Su único tope eran sus 10 segundos, sin mirar
cuánto quedaba. El margen que reserva el arranque del turno siguiente está calculado para un intento
de 15 segundos, y con la comprobación de por medio un intento podía durar 25. Ninguna emisión se
perdió por esto —el piso de margen es de 127 segundos contra unos 70 de peor caso medido— pero la
garantía estaba escrita y no se cumplía, y el compromiso terminaba anclando más cerca de su ronda de
lo que el diseño reserva.

**3. Ningún mecanismo levanta un parte falso.** El portal considera explicado a cualquier parte que
traiga su bitácora adentro, y el aviso automático no insiste sobre lo que está explicado. Un parte
falso **con** bitácora cumple las dos condiciones. Los siete se encontraron comparando a mano, archivo
por archivo, contra los dos repositorios.

**4. Y los partes de incidente también quedaron desparejos, sin que nada lo declare.** Diez de ellos
faltan en GitLab: `1300-01.jws` y los de los turnos 13:10 a 14:30. Se publican por la misma vía que
todo lo demás, así que cuando el proveedor no aceptaba escrituras tampoco entraron.

La comprobación que compara los dos anclajes mira **solo** el directorio de emisiones. El de
incidentes se lee con otro propósito —saber qué turnos ya tienen parte para no declarar dos veces lo
mismo— y ahí basta con que el archivo esté en **uno** de los dos. Correcto para no duplicar, y ciego
para el desfase.

⚠️ El efecto incómodo: el parte del turno 13:10, que es el que declara que faltan archivos de ese
turno en GitLab, **también falta en GitLab**. Quien mire solo ese repositorio ve el hueco sin la
explicación al lado. Está en GitHub, firmado, y el portal lo muestra igual.

## Qué se hizo

**En el emisor:**

- Se separa lo comprobado de lo que no se pudo comprobar. `missing` lleva **solo** los anclajes que
  contestaron que el archivo no está.
- Cuando no se pudo comprobar nada, el motivo del parte es **`anchor_timeout`** — *la escritura salió
  y no vimos la respuesta*—, que ya estaba en la lista cerrada de esta especificación desde antes. Los
  anclajes sobre los que no se sabe se nombran en `unconfirmed`: se nombran, no se afirman.
- La comprobación **no puede pasarse del límite del turno**. Usa su plazo cuando hay tiempo de sobra
  y lo que quede cuando no.
- **Se sigue reintentando contra todo lo que falta**, incluido lo que no se pudo comprobar. Dejar de
  insistir sobre un hueco que puede ser real sería peor que declararlo mal.

**En el portal:** un caso nuevo. Antes había dos —«faltó en X» y «entró en todos»— y un parte sin
`missing` caía en el segundo por descarte, lo que habría publicado *«entró en todos los anclajes»*
sobre justo lo que se ignora. Ahora dice **«no se pudo comprobar en X»**, y al lado cómo comprobarlo
sin credencial.

**En la lista de motivos de esta especificación:** nada. No se agregó ni se cambió ningún código.
`anchor_timeout` ya estaba publicado, con el significado que hacía falta.

**Y en este documento, una frase que se contradecía con otra suya.** Decía *«Tres instrumentos
firmados»* al presentarlos, y treinta y siete líneas más abajo explicaba que una nota va *«en
Markdown y sin firma, a propósito: la nota informa, no prueba»*. De los tres, **solo el parte de
incidente va firmado**; las dos notas no, y eso es deliberado y está razonado ahí mismo — firmar
«me robaron la clave» con la clave robada no probaría nada.

Lo que los tres comparten no es la firma: es que **quedan en un repositorio que no se reescribe,
con la fecha que pone el proveedor**. Sobraba el adjetivo, así que se quitó. Se declara acá, con el
mismo criterio que la nota `0002` usó para el año que caducaba: un arreglo de redacción se nombra,
no entra callado.

## Qué NO cambió

**Nada de lo emitido.** Ningún archivo `.jws`, ninguna firma, ninguna regla de derivación, ningún
número. Todo lo emitido ese día reproduce igual que antes de esta nota.

**Los ocho partes con la declaración incorrecta se quedan como están.** Un archivo publicado no se
reescribe. Cada uno lleva al lado, en el portal, un texto que dice qué archivo está anclado y en qué
commit, con la fecha que le puso el proveedor.

**Los 18 archivos que de verdad faltan en GitLab no se reponen.** Son los de los turnos 13:10 a
13:50 y 14:10 a 14:30 completos, más `1400-commitment.jws` y `1440-commitment.jws`. **Ni los 10
partes de incidente ausentes**, por lo mismo. Subirlos después llevaría fecha
posterior a su ronda, y usaría el canal de las emisiones para decir algo que ese canal no sabe decir.
Esos turnos perdieron redundancia, no prueba: están anclados en GitHub, firmados, y se comprueban.

## Qué debería comprobar un tercero

- Los archivos que los siete partes declaran faltantes **están en GitLab**, cada uno con su commit y
  con la fecha que puso GitLab. Se lee sin credencial:

  ```
  commits?path=emissions/2026/09/24/1510-commitment.jws
  ```

  Ese, por ejemplo, está en el commit `cc90a4998de9a74c55b92c0e1f0c6a847a7c2a0c`, sellado por GitLab
  a las **15:08:33 UTC** — **seis segundos antes** de que el emisor diera la escritura por perdida.
  El mismo contraste se repite en los siete: entre 6 y 21 segundos.

- Los archivos de los turnos 13:10 a 14:30 **de verdad no están en GitLab**, y sus partes lo declaran
  correctamente. La diferencia entre los dos grupos es comprobable archivo por archivo.

- Cada turno del día tiene su compromiso anclado **antes** de que existiera la ronda de drand que
  determina su resultado, y esa fecha la pone el proveedor.

- Los partes llevan su bitácora de intentos adentro, firmada, con la hora y la respuesta de cada uno.
  En siete de ellos esa bitácora **contradice** lo que el mismo archivo declara, que es exactamente
  el defecto que esta nota registra.

- El incidente del proveedor es público y contrastable, con su propia cronología y sus propias horas.

- Desde esta nota en adelante, un anclaje sobre el que no se pudo comprobar nada se declara
  `anchor_timeout` y aparece en `unconfirmed`. **Si un parte dice `missing`, es porque alguien
  contestó que el archivo no está.**
