---
name: planificar-issue
description: Arma el plan de un issue de Londinium sin escribir código. Usar cuando Cristian pida modo plan o antes de una tarea grande.
---

# Planificar un issue

Modo plan: **no se escribe código ni se editan archivos hasta que Cristian apruebe.**

El plan responde, corto:
1. **Qué entra y qué no**, copiado del alcance y del fuera de alcance del issue.
2. **Interfaces:** clases, comandos y claves de `data/` que se agregan o cambian (nombres reales, con ruta).
3. **Orden del tick:** en qué paso de `docs/ARCHITECTURE.md` ("Tick order") entra el cambio y por qué ahí.
4. **Un test por criterio de aceptación:** archivo y nombre del test, o paso manual si toca pantalla.
5. **Dudas de diseño:** las que falten van por `decision-diseno`, no se resuelven acá.

El plan vive en el chat o en un comentario del issue. **No va en `docs/`.**

## Gotchas
- Un criterio sin test o sin paso manual no está planificado.
- Si el plan necesita cambiar `GDD.md` o `DECISIONS.md`, decilo explícitamente: requiere la autorización de Cristian
  (ver `decision-diseno`).
- Verificá nombres y rutas en el repo antes de escribirlos en el plan.
