# permanent

Todo lo que no depende del año: especificación, registro de claves, verificador y manifiesto.

Este es el repositorio **permanente**: todo lo que no depende del año. Los datos —las emisiones—
viven en un repositorio aparte por año.

> 🇬🇧 In English: [`README.md`](README.md)

## Por qué están separados

En el repositorio del año **nadie edita nunca**. Eso es una invariante, y cualquiera la comprueba con
un solo comando:

```bash
git log --diff-filter=M --oneline    # tiene que no devolver nada
```

Si la especificación y el registro de claves vivieran ahí adentro, esa invariante se perdería: los
dos se editan por diseño. Además, el token del emisor solo necesita alcance sobre el repositorio del
año.

## Qué hay acá

| | |
|---|---|
| `spec/` | La especificación: con esto y un `.jws`, cualquiera reproduce los números |
| `keys/` | El registro de claves — `kid` → clave pública + época |
| `verifier/` | El verificador de referencia |
| `manifest.json` | Dónde vive cada cosa: los repositorios del año y sus vías de acceso |

---

Creado por `provision/`, no a mano.
