# Nota de publicación 0002

| | |
|---|---|
| **Publicada** | 2026-09-13 |
| **Código** | `defect_published` |
| **Turnos afectados** | 2026-09-13, de 08:50 a 10:00 UTC |

## Qué pasó

El **13 de septiembre de 2026**, entre las 08:47 y las 09:58 UTC, GitHub rechazó dieciséis escrituras
de este sistema con `HTTP 500` y `HTTP 502`. GitLab aceptó todas, al primer intento, desde la misma
máquina y en el mismo segundo.

Fueron cinco turnos afectados. En cuatro el archivo entró tras reintentar. **En el turno de las 09:00 no entró**:
`emissions/2026/09/13/0900-commitment.jws` está en GitLab y falta en GitHub.

Ese turno se comprueba con normalidad. GitLab aceptó el compromiso al primer intento y selló su
commit a las **08:57:55 UTC**, **125 segundos antes** de que existiera la ronda 6461966 de drand,
que es la que determina el resultado. Lo que ese turno perdió es redundancia, no prueba: el
compromiso queda en un proveedor en vez de dos.

## Por qué pasó

La causa inmediata es del proveedor, y está declarada por él. GitHub abrió un incidente de impacto
crítico ese mismo día, de **09:16 a 10:44 UTC**, con esta explicación:

> *«increased database replication delays on collab which is causing increased error rates in
> authorization endpoints and follow-on increased error rates across the system»*

y lo mitigó descartando carga en el borde (*internal load-shedding*). Nuestros primeros rechazos
son de las 08:47 — **29 minutos antes de que el incidente estuviera declarado**.

El emisor hizo lo que tenía que hacer: reintentó cinco veces contra GitHub entre las 08:57:58 y las
08:59:22, y paró porque no quedaba plazo. **El compromiso tiene que estar anclado antes de que nazca
su ronda**, y un sexto intento caía después del corte. Eso no es un defecto: es la regla
funcionando.

## Qué se encontró investigándolo

Los defectos están en lo que el sistema **dijo** sobre lo que pasó, no en lo que emitió.

1. **Cinco partes de incidente firmados declaran `unknown_state`, y es falso.** Este repositorio
   publica ese código con el significado *«no se pudo determinar qué pasó»*. En los cinco se
   determinó perfectamente:

   - En los turnos 08:50, 09:10, 09:30 y 10:00 el archivo **entró**, tras reintentar, y el propio
     parte trae adentro la bitacora con la hora y el código HTTP de cada intento. Un archivo
     firmado que se contradice a sí mismo.
   - En el turno 09:00 el archivo **no entró**, y se sabía cuál faltaba y en qué anclaje: el parte
     lo dice en sus propios campos `files` y `missing`.

2. **La lista cerrada de motivos no tenía dónde poner ninguno de los dos casos.** `anchor_unreachable`
   significa *«ningún repositorio aceptó la escritura»*, y en los dos casos uno aceptó. No había
   código para «entró en un anclaje y no en el otro» ni para «entró en todos, pero hizo falta
   reintentar», así que los dos caían en `unknown_state` por descarte.

   Esa lista es el vocabulario de un **fallo de turno** —por qué este turno no produjo resultado—
   y el parte de incidente la estaba usando para contestar otra pregunta: qué pasó operativamente.

3. **El parte del turno 09:00 se publicó sin la bitácora de intentos**, aunque `attempts` está
   declarado en esta especificación y los otros cuatro sí la llevan. El motivo: ese parte lo escribió
   el barrido, que compara listados de archivos y sabe *qué* falta pero no *por qué*. Los cinco
   rechazos estaban en la memoria del mismo proceso, 105 segundos antes, y no viajaron.

   **El turno que más necesitaba la bitácora fue el único que se publicó sin ella.**

4. **Este documento hablaba del año 2031.** Decía *«nadie puede saber hoy qué va a hacer falta
   cambiar en 2031»*. El año era un ejemplo y envejece solo: leído en 2031 dice lo contrario de lo
   que quiere decir.

## Qué se hizo

**En la lista de motivos de esta especificación**, dos códigos nuevos:

```
anchor_partial        entró en un anclaje y no en el otro
anchor_retried        entró en todos, pero hizo falta reintentar
```

Con eso `unknown_state` vuelve a significar lo que dice: queda para lo que de verdad no se sabe —un
turno de otro día, o uno que quedó huérfano porque el emisor se cayó antes de declararlo.

**En el emisor:**

- El parte lo declara **el turno**, que es quien tiene los datos, y no el barrido. En los dos casos,
  con el código que corresponde y **con la bitácora de intentos adentro**.
- El barrido queda como red de seguridad, para lo que el turno no alcanzó a declarar. Ahí, y solo
  ahí, `unknown_state` es literal.
- El margen entre el anclaje y la ronda se mide desde **la fecha que pone el proveedor**, que es la
  única del anclaje que un tercero puede comprobar. Antes se medía desde el reloj propio al terminar
  de reintentar, lo que en este mismo turno declaró 37 segundos donde había 125.

**En el portal:**

- La página de reportes cuenta sola los partes cuyo código trae los números, con la bitácora en
  tabla. Los que no, siguen esperando que una persona los escriba.
- Toda hora se muestra en la zona horaria del que mira.

**En este documento:** se quitó el año, que no aportaba nada y caduca.

**Y en `spec/README`, un cambio que viaja en la misma propuesta y no es parte de esto:** se agregó al
principio una frase que dice, con las palabras que usa la norma, qué define esta especificación —
resultados *verificables y auditables*. Estaba escrita desde el 11 de septiembre y no se había
publicado. Se declara acá para que no entre sin que nadie la nombre.

## Qué NO cambió

**Nada de lo emitido.** No se tocó ningún archivo `.jws`, ninguna firma, ninguna regla de derivación
ni el campo `version`. Todo lo publicado reproduce exactamente igual que antes.

**Y los cinco partes que dicen `unknown_state` se quedan como están.** Un archivo publicado no se
corrige, no se borra y no se reemplaza: esta nota dice qué tienen de malo y se queda al lado. Que
digan menos de lo que se sabía es un defecto; reescribirlos sería uno peor.

**El compromiso que falta en GitHub no se repuso.** Subirlo después llevaría fecha posterior a su
ronda y se leería como un compromiso que llegó tarde. El hecho se explica; el archivo no se fabrica
después.

## Qué debería comprobar un tercero

- `emissions/2026/09/13/0900-commitment.jws` **está en GitLab y falta en GitHub**. Su emisión,
  `0900-emission.jws`, está en los dos.
- La fecha que GitLab le puso a ese commit es **2026-09-13T08:57:55Z**, anterior a la hora nominal
  de la ronda 6461966 (09:00:00Z). Se lee sin credencial:

  ```
  commits?path=emissions/2026/09/13/0900-commitment.jws
  ```

- Los partes de los turnos 08:50, 09:10, 09:30 y 10:00 llevan adentro, firmados, **once** intentos
  con su hora y su código de respuesta. Los cinco del turno 09:00 no viajan en ningún archivo: solo
  están en el log del emisor, que es justamente el defecto que esta nota declara. Contrastan con el incidente que GitHub declaró ese día entre las
  09:16 y las 10:44 UTC.
- El historial de este repositorio muestra que `spec/notices.md` fue **modificado y nunca
  reemplazado**: las versiones anteriores siguen en el registro, con la fecha que el proveedor le
  puso a cada commit.
- Desde esta nota en adelante, un turno donde un archivo entre en unos anclajes y no en todos se
  declara con `anchor_partial` **dentro del propio turno**, y con la bitácora de intentos adentro.
