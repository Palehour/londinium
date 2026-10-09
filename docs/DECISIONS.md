# Registro de decisiones

Cada entrada dice si está **Decidida** (Cristian la confirmó) o **Propuesta** (todavía falta su visto bueno). Las propuestas no se implementan hasta pasar a Decidida.

## Decididas

| ID | Fecha | Decisión |
|---|---|---|
| D-001 | 2026-10-05 | Anno es la inspiración, no una copia. |
| D-002 | 2026-10-05 | Londres a través de varias eras, con paralelismos históricos reales al estilo Assassin's Creed y figuras reales. |
| D-003 | 2026-10-05 | Tono realista, con folklore de terror londinense para la tensión. |
| D-004 | 2026-10-05 | El jugador elige un rol. Ritmo moderado. Modos campaña y sandbox. |
| D-005 | 2026-10-05 | Arte objetivo: grabado victoriano. Para testear, low poly o isométrico; sprites con IA en el prototipo si se puede. |
| D-006 | 2026-10-05 | Sin IA en runtime. Presupuesto casi cero. Arrancar chico. |
| D-007 | 2026-10-05 | Godot 4 en Windows. Agentes de código: Codex, Claude y Grok Build. |
| D-008 | 2026-10-06 | La música de Cristian Bergagna (horrorsynth y darkwave) es parte del juego. |
| D-009 | 2026-10-06 | Primer hito: probar el flujo simple de fabricación, consumo, uso, población y preferencias. |
| D-010 | 2026-10-08 | El trigo entra por el muelle, salvo en lugares donde históricamente se podía cultivar; ahí se cultiva en el mapa. Según Chronicler, en Whitechapel en los 1850 no hay tierra cultivable; los candidatos son Barking/Ilford, West Ham y East Ham (Essex), y Stepney en la era medieval. |
| D-011 | 2026-10-08 | Almacén global en el prototipo. Más adelante se define si conviene el transporte físico. |
| D-012 | 2026-10-08 | ~~Por ahora los trabajadores se asignan solos a los edificios.~~ Reemplazada por D-021. |
| D-013 | 2026-10-08 | El prototipo se puede perder. Condiciones de derrota iniciales: quiebra, motín de hambre y despoblación, cada una con aviso previo (umbrales en el GDD, a balancear). |
| D-014 | 2026-10-08 | Los roles llegan después del hito 1. El diseño y el código dejan un gancho para modificadores de rol (parámetros en datos, leídos con una sola función que aplica modificadores) para no tener que rehacer nada. |
| D-015 | 2026-10-08 | Fase 2: cervecería como segunda cadena, con el grano disputado entre el pan y la cerveza. |
| D-016 | 2026-10-08 | El primer evento histórico es el cólera de 1866 en Whitechapel (East London Water Company, Old Ford), su peor año según Chronicler. El brote de 1854 (Broad Street) fue en Soho. |
| D-017 | 2026-10-08 | Prototipo en la era victoriana, en Whitechapel. Ambientación: la inmigración judía masiva empieza en los 1880; en los 1850 había una comunidad chica de judíos holandeses que hacía cigarros. (antes P-001) |
| D-018 | 2026-10-08 | Fase 1: cadena trigo, harina y pan; trabajadores que consumen pan, crecen y pagan impuestos; panel de estadísticas; cuadrados de colores. (antes P-002) |
| D-019 | 2026-10-08 | El jugador juega el hito 1 como administrador neutral del distrito, sin rol. (antes P-010) |
| D-020 | 2026-10-08 | La fuente de grano es un embarcadero sobre el río (grano comprado en Mark Lane y llegado en lanchas desde los Surrey Docks); el molino del prototipo queda como licencia de diseño. Chronicler no encontró molinos harineros en Whitechapel en los 1850. Millwall Dock (1868) y el molino de McDougall (1869) sirven para una etapa victoriana posterior. (antes P-012) |
| D-021 | 2026-10-08 | Los trabajadores se asignan solos a los edificios con esta regla: primero un trabajador por edificio en el orden de la cadena (embarcadero, molino, panadería); después, el resto con la prioridad panadería, molino, embarcadero. Cuando la emigración reduce la población, los puestos se liberan en el orden inverso al de la asignación. Evita que el embarcadero, raíz de la cadena, quede vacío primero. Reemplaza a D-012 (issue #5, PR #19). |

## Propuestas

| ID | Fecha | Propuesta | Quién | Comentario |
|---|---|---|---|---|
| P-004 | 2026-10-08 | El té importado como primera preferencia (no obligatoria). | Mason | Cubre "preferencias" del hito con un solo bien y sin otra cadena. |
| P-007 | 2026-10-08 | Eras: romana, medieval, 1666, victoriana y Blitz, con lo construido pasando de una era a otra. | Grok Bot | La continuidad entre eras es lo más caro del proyecto; conviene tratarla como visión y no comprometerla hasta validar el loop. |
| P-008 | 2026-10-08 | Roles: mercader, familia noble, gremio obrero, sociedad secreta. | Grok Bot | Buena variedad; cada rol debería cambiar qué decisiones económicas importan, no solo dar bonos. Se apoya en el gancho de D-014. |
| P-009 | 2026-10-08 | "Grietas de la historia" por donde se cuela el folklore de terror. | Grok Bot | Encaja con D-003; queda fuera del hito 1. |
| P-011 | 2026-10-08 | Harina importada como fuente que se saltea el molino: más cara, pero no ocupa trabajadores. | Mason | Históricamente correcta según Chronicler, y suma la decisión de moler o comprar. |
| P-013 | 2026-10-08 | El pan (trigo) y la cerveza (cebada malteada) se disputan la capacidad del embarcadero, el dinero y los trabajadores, en lugar de usar el mismo grano. | Mason | Es más fiel a la historia: según Chronicler, la malta bajaba por el Lea desde Hertfordshire. Si Cristian prefiere un "grano" genérico más simple, queda como licencia de diseño. |
| P-014 | 2026-10-08 | La cerveza es la necesidad que permite que un trabajador ascienda a artesano. | Mason | Une la cervecería con la promoción de clase de la fase 2. |
