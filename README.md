# Oracle Data Cleanup

Colección de procedimientos y packages PL/SQL para ejecutar procesos de depuración controlada en bases Oracle. Las rutinas organizan la limpieza por entidad, aplican reglas sobre información operativa e histórica y registran la ejecución para facilitar su seguimiento.

## Contenido

```text
entities/
  700/    Proceso completo de depuración para la entidad 700.
  702/    Proceso completo de depuración para la entidad 702.
  703/    Procedimiento principal y package de depuración para la entidad 703.

auditoria-go/
  702/    Rutinas de Auditoría GO y DDL de soporte para la entidad 702.
```

Los procesos de las entidades 700 y 702 incluyen dos procedimientos de limpieza y el package que coordina su ejecución. La implementación de 703 agrupa sus objetos específicos, mientras que Auditoría GO incorpora rutinas para datos de entidad e históricos junto con las tablas de control necesarias.

## Objetivos del diseño

- separar las reglas de depuración por entidad;
- procesar información activa e histórica de forma controlada;
- centralizar la orquestación en packages PL/SQL;
- conservar trazabilidad mediante tablas y registros de auditoría;
- permitir la ejecución programada o manual desde herramientas Oracle.

## Uso

Antes de ejecutar los scripts:

1. revisar schemas, tablespaces y dependencias;
2. validar los permisos del usuario ejecutor;
3. confirmar las políticas de retención aplicables;
4. probar el proceso en un ambiente controlado;
5. verificar los registros de auditoría después de cada corrida.

Estas rutinas realizan operaciones de eliminación y modificación de datos, por lo que deben ejecutarse con respaldo, monitoreo y una política de recuperación definida.
