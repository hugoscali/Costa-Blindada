# 🏖️ Beach Defense 2000 Remake — Godot Edition

## Cómo ejecutar

1. Abrir **Godot 4.7.2** (shortcut en el escritorio)
2. En el Project Manager → **Import**
3. Seleccionar este archivo: `project.godot`
4. Click en **Edit** para abrir el editor
5. Presionar **F5** (o el botón ▶) para ejecutar

## Controls

| Tecla | Acción |
|-------|--------|
| Mouse | Apuntar (izq/der, arriba/abajo) |
| Clic Izquierdo | Disparar |
| 1 | Pistola (∞ balas) |
| 2 | Ametralladora (rápida) |
| 3 | Cañón (daño en área) |
| ENTER | Comenzar / reiniciar |

## Enemigos

| Oleada | Enemí |
|--------|--------|
| 1-2 | 🚤 Botes con soldados |
| 3+ | ✈️ Aviones |
| 5+ | 🛡️ Tanques |

Los soldados desembarcan y disparan. Sobreviví el máximo de oleadas.

## Estructura

```
project.godot          ← Config del proyecto
scenes/main.tscn       ← Escena raíz
scripts/main.gd        ← Todo el juego (mundo, enemigos, armas, waves)
```

## Requisitos

- Godot 4.7+ (Forward+ renderer)
- GPU con Vulkan 1.0+ (o OpenGL 3.3 mínimo)
