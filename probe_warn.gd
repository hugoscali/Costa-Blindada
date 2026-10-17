extends RefCounted
## Probe de análisis: ¿el proyecto reporta warnings por llamadas/propiedades dinámica
## sobre una variable sin tipo (patrón "back-reference" al script raíz)?


func probe() -> void:
	var app = null
	var s: String = app.some_method(1)
	var n: int = app.some_prop
	var d: Dictionary = {}
	var v = d.get("x", 0)
	var f: float = v
	print(s + str(n) + str(f))
