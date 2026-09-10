# Nota de publicación 0001

| | |
|---|---|
| **Publicada** | 2026-09-10 |
| **Código** | `defect_published` |
| **Turno afectado** | 2026-09-06, 22:10 UTC |

## Qué pasó

La emisión del turno de las **22:10 del 6 de septiembre de 2026** se publicó en GitHub y **no llegó
a GitLab**. Quedó así durante tres días, hasta que se encontró a mano el 9 de septiembre.

El compromiso de ese turno sí llegó a los dos anclajes, a tiempo: se firmó **1 minuto y 51 segundos antes**
de que existiera la ronda de drand que determina el resultado — `committed_at_utc` en el archivo
publicado dice `22:08:09`, y la ronda nace a las `22:10:00`. Esa parte —la que hace
imposible haber elegido el número— nunca estuvo en duda.

**Lo que falló fue la copia.** Y el efecto es concreto: quien mirara solo GitLab veía un compromiso
sin su emisión, sin forma de distinguir un problema de red de algo escondido.

## Por qué pasó

La causa inmediata fue de red, y está en el registro del emisor:

```
gitlab error 10.002s — dial tcp [2606:4700:90:0:f22e:fbec:5bed:a9b9]:443:
                       connect: network is unreachable
```

El sistema de nombres devolvió solo la dirección IPv6 de `gitlab.com` —la respuesta IPv4 se
perdió— y la máquina que emite no tiene ruta IPv6. La escritura murió al instante.

Eso dura segundos y se recupera solo. **Lo que no se recuperó fue el sistema**, y ahí están los
defectos de verdad:

1. **No se reintentaba contra el anclaje que había fallado.** Con un anclaje aceptando, el emisor
   daba el turno por bueno y no volvía a intentar con el otro. Un segundo intento treinta segundos
   después habría resuelto todo.

2. **No se avisaba.** El aviso solo se disparaba cuando fallaban **todos** los anclajes. Con uno
   funcionando, el turno terminaba en silencio.

3. **Nada comparaba los anclajes entre sí.** Ningún proceso preguntaba si lo publicado en uno
   estaba también en el otro.

4. **El portal se armaba con un solo anclaje** — el primero que respondiera. Ese día respondió
   GitHub, que tenía el archivo, así que el portal se dibujó bien por casualidad. Con GitHub caído,
   habría mostrado un hueco sobre una emisión que existía y verificaba.

Tres días de silencio no fueron mala suerte: **no había nada mirando.**

## Qué se encontró investigándolo

Al escribir la corrección aparecieron defectos en textos ya publicados en este repositorio:

- **La especificación decía que los turnos son cada cinco minutos.** Son cada diez desde el 27 de
  agosto de 2026, y el ejemplo de `spec/README.md` estaba construido sobre las `05:05`, un instante
  que no es un turno y no tiene archivo.

- **Las reglas de los avisos se contradecían.** `spec/notices.md` decía que las notas de publicación
  viven en `spec/NNNN-*.md` —Markdown— y dos líneas después que van *firmadas con la misma clave que
  todo lo demás*. Un archivo Markdown no lleva firma adentro; las dos cosas no podían ser ciertas.

- **El parte de incidente publicaba cuatro campos que la especificación no declaraba**:
  `variant`, `attempts`, `unanchored_commitment` y `warning_en`.

## Qué se hizo

**En el emisor:**

- Se reintenta contra **el anclaje que falló**, y solo contra ese, durante la ventana del turno.
- Al terminar un turno se compara **el día entero** contra todos los anclajes. Si algo está en uno y
  no en otro, se publica un parte de incidente firmado en `<año>/incidents/`.
- Se avisa cuando una emisión entra en unos anclajes y no en todos, no solo cuando fallan todos.
- La comprobación de arranque muestra **a qué dirección** se conectó cada anclaje, para que un
  problema como el de ese día se vea en la primera pantalla y no dentro de un mensaje de error.

**En el portal:**

- Se lee de **todos** los anclajes y se muestra la unión: una emisión publicada en cualquiera de
  ellos aparece.
- Hay una página de reportes que lista cada parte de incidente y lo explica.

**En esta especificación:** se corrigieron los tres defectos de arriba. Las notas quedan declaradas
como Markdown **sin firma**, con el motivo escrito al lado: una nota informa, no prueba. Si una
clave de firma estuviera en manos ajenas, firmar con ella *«me robaron la clave»* no probaría nada.

## Qué NO cambió

**Nada de lo emitido.** No se tocó ningún archivo `.jws`, ninguna firma, ninguna regla de
derivación ni el campo `version`. Todo lo publicado hasta hoy reproduce exactamente igual que antes,
y los archivos del turno 22:10 del 6 de septiembre son byte por byte los que se firmaron ese día.

**Y la emisión que falta en GitLab no se repuso.** Con un anclaje alcanza para probar, y meterla
tres días tarde usaría el canal de las emisiones para decir algo que ese canal no sabe decir —que
llegó tarde—. El hecho se explica acá; el archivo no se fabrica después.

## Qué debería comprobar un tercero

- El turno del **2026-09-06 22:10** está completo y verifica en GitHub: la semilla revelada da el
  compromiso, la ronda 6443386 de drand trae ese mismo valor, y el compromiso se ancló antes.
- En GitLab **falta** `emissions/2026/09/06/2210-emission.jws`, y su compromiso sí está.
- El historial de este repositorio muestra que `spec/README` y `spec/notices` fueron **modificados y
  nunca reemplazados**: las versiones anteriores siguen en el registro, con la fecha que el
  proveedor le puso a cada commit.
- Desde esta nota en adelante, un desfase entre anclajes aparece como parte de incidente en
  `<año>/incidents/` dentro del turno siguiente.
