# `keys/` — la historia de claves

`history.json` resuelve `kid` → clave pública. Es **la raíz de confianza de todas las firmas** del
sistema.

> 🇬🇧 In English: [`README.md`](README.md)

## El formato

```json
{
  "AAAA-MM-DD_HHMM": "<64 caracteres hex>"
}
```

Ese es el archivo entero. Dos reglas lo hacen legible:

- **El `kid` ES la fecha en que se generó la clave**, `AAAA-MM-DD_HHMM` en UTC — la misma forma de la
  ruta de anclaje cambiando las barras. Así, quien abre un `.jws` sabe de qué época es su clave sin
  abrir ningún otro archivo.
- **Una época va hasta que empieza la siguiente.** La última no tiene fin: es la activa. No hay campo
  `status` porque no hay nada que declarar — lo dice el orden.

Una firma fechada fuera de la época de su clave se rechaza aunque la firma sea válida. Eso es lo que
impide que una clave actual robada sirva para fabricar pasado.

**Un valor vacío significa que la clave pública se perdió.** Se conserva y se declara en vez de
borrarla, porque «esto no se puede verificar» y «esto no verifica» son afirmaciones muy distintas.
Una clave pública no se puede recuperar desde una firma Ed25519: borrar la entrada convertiría en
silencio una pérdida nuestra en una acusación contra el archivo.

## Verificar una firma con herramientas estándar

Al lado de `history.json` hay **un archivo JWK por clave**, con su `kid` de nombre:

```
keys/AAAA-MM-DD_HHMM.jwk.json
```

```json
{
  "kty": "OKP",
  "crv": "Ed25519",
  "alg": "EdDSA",
  "use": "sig",
  "kid": "AAAA-MM-DD_HHMM",
  "x": "4RvrMJdRNWKR7ylMx8JG2s5dnDJbAyqDfek0fl-K2OM"
}
```

Los archivos emitidos son JWS, así que cualquier biblioteca JOSE —o jwt.io— lo toma tal cual. Se lee
el `kid` de la cabecera del JWS, se busca ese archivo, y se verifica. Sin convertir nada.

**Los dos archivos dicen lo mismo**, uno en hex y otro en base64url. Se generan de la misma fuente en
el mismo commit, y una prueba rompe el build si alguna vez difieren. Si aun así los encontrás
distintos, el que vale es `history.json` — y queremos enterarnos.

Una clave con el valor vacío en `history.json` no tiene archivo JWK: no queda clave que publicar.

## Cómo se lee, que es la parte que importa

Una firma se verifica contra la versión de la historia **contemporánea a esa firma**, no contra la
última. El motivo: `history.json` es un archivo **mutable** —se sobrescribe a sí mismo—, así que
insertar una clave falsa **no requiere un `force-push`**, alcanza con un commit común.

Lo que da la garantía es que la historia no se puede borrar:

```bash
git log --follow -p -- keys/history.json
```

> ⚠️ **Alcance honesto:** esto protege contra el repudio; no prueba honestidad. Y solo lo puede
> ejercer alguien capaz de leer una historia de git. Que la herramienta lo haga por vos es la única
> respuesta real, y todavía no está escrita.
