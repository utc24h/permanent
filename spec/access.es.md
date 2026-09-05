# `spec/access.md` — cómo bajar un archivo

Cada emisión vive en más de un lugar, servida por operadores que no somos nosotros. Usá el que
conteste más rápido desde donde estés.

> 🇬🇧 In English: [`access.md`](access.md)

## Las vías

| Dónde vive el archivo | Lo sirve |
|---|---|
| GitHub | **jsDelivr** · **Statically** |
| GitLab | **Statically** |
| El sitio de este proyecto | él mismo |

jsDelivr no sirve GitLab. Eso no es un defecto de ninguno de los dos: es una vía menos, y la gracia
es que hay varias.

## Las URL

```
https://cdn.jsdelivr.net/gh/<owner>/<repo>@main/<ruta>
https://cdn.statically.io/gh/<owner>/<repo>@main/<ruta>
https://cdn.statically.io/gl/<owner>/<repo>@main/<ruta>
```

`<ruta>` es el archivo dentro del repositorio, por ejemplo:

```
emissions/2026/08/29/2110-emission.jws
```

## Todas sirven los mismos bytes

Comprobado, no supuesto: el mismo archivo bajado por cada vía da el **mismo SHA-256**. Un CDN
delante de un repositorio es una caché, no una copia que alguien mantenga sincronizada.

Eso importa por la **R6**: el archivo viaja en binario y no se toca. Si alguna vía devolviera bytes
distintos, la firma no va a verificar — y esa es la respuesta, no un error de tu código.

## Cuál usar

La que te quede más cerca. Un CDN reparte por cercanía, así que la más rápida desde un continente
no es la más rápida desde otro. Medí desde donde están tus usuarios, no desde donde medimos
nosotros.

Si bajás muchos archivos, usá un CDN. Para eso están, y deja tranquilos a los repositorios.

## Sobre el sitio de este proyecto

Sirve los mismos archivos, y es una comodidad — no evidencia. Es nuestro: una copia que controlamos
no puede ser la prueba de que no cambiamos nada. Las vías de arriba son las que no dependen de
nosotros, y esas son las que hay que señalar cuando importa.
