---
name: decision-diseno
description: Qué hacer cuando falta una decisión de diseño (número de balance, regla, P-xxx) o hay que tocar GDD.md o DECISIONS.md.
---

# Decisiones de diseño

Si falta un número de balance, una regla o hay un P-xxx sin aprobar: **no se inventa.**

1. Frená y presentá **2 o 3 opciones**, cada una con pros y contras, y **una recomendación**.
2. **Mason opina, Cristian decide.** Hasta que Cristian responda, implementá la lectura más conservadora
   o dejá esa parte afuera.
3. Los P-xxx no se implementan salvo que el issue diga que fueron aprobados.

## Editar `docs/GDD.md` y `docs/DECISIONS.md`

Aprobado por Cristian (11/10/2026):
- Los agentes pueden editarlos **solo con autorización explícita de Cristian**.
- Esa autorización **se cita en un comentario de la PR**, y Bailey la **confirma directamente con Cristian**
  antes de aprobar.
- La edición autorizada va en **tu rama de tarea** (`<tipo>/<n>-<slug>`); las ramas `docs/` son de los bots.
- **Sin esa autorización**, el agente propone el texto en la sección **"Decisiones y docs"** de la PR y
  **no lo edita**.

## Gotchas
- Una autorización vale para esa PR y esos archivos; no se arrastra a otras.
- "Parece obvio" no es autorización. Si no hay comentario de Cristian citado, no se edita.
- Una decisión nueva con autorización va a `DECISIONS.md` con el siguiente D-xxx, fecha y el issue/PR de origen.
