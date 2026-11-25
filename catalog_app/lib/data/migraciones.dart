// Esquema de la base de datos local, versión por versión.
// Nunca se edita una versión ya publicada: los cambios van en una versión nueva.
//
// Fechas: milisegundos desde 1970 (hora del teléfono).
// Precios: pesos chilenos enteros.

const versionBaseDatos = 3;

const migraciones = <int, List<String>>{
  1: [
    '''
    CREATE TABLE compras(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      codigo TEXT NOT NULL UNIQUE,
      fecha_compra INTEGER NOT NULL,
      vendedor TEXT NOT NULL,
      lugar TEXT NOT NULL DEFAULT '',
      lat REAL,
      lng REAL,
      precision_m REAL,
      precio INTEGER NOT NULL CHECK(precio >= 0),
      motor TEXT NOT NULL CHECK(motor IN ('bencinero', 'diesel')),
      material TEXT NOT NULL CHECK(material IN ('ceramico', 'metalico', 'dpf')),
      original INTEGER NOT NULL DEFAULT 0,
      codigo_fabrica TEXT NOT NULL DEFAULT '',
      autos TEXT NOT NULL DEFAULT '',
      foto_path TEXT,
      notas TEXT NOT NULL DEFAULT '',
      estado TEXT NOT NULL DEFAULT 'activa' CHECK(estado IN ('activa', 'anulada')),
      anulada_en INTEGER,
      motivo_anulacion TEXT NOT NULL DEFAULT '',
      impresiones INTEGER NOT NULL DEFAULT 0,
      creado_en INTEGER NOT NULL,
      actualizado_en INTEGER NOT NULL,
      fecha_compra_editada_en INTEGER
    )
    ''',
    'CREATE INDEX idx_compras_fecha ON compras(fecha_compra)',
    'CREATE INDEX idx_compras_vendedor ON compras(vendedor)',
    'CREATE INDEX idx_compras_codigo_fabrica ON compras(codigo_fabrica)',
    // Último número usado por día de compra (AAMMDD). Nunca baja.
    'CREATE TABLE contador_codigos(dia TEXT PRIMARY KEY, ultimo INTEGER NOT NULL)',
    '''
    CREATE TABLE lotes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      creado_en INTEGER NOT NULL,
      cerrado_en INTEGER,
      notas TEXT NOT NULL DEFAULT ''
    )
    ''',
    '''
    CREATE TABLE lote_items(
      lote_id INTEGER NOT NULL REFERENCES lotes(id) ON DELETE CASCADE,
      compra_id INTEGER NOT NULL REFERENCES compras(id),
      escaneado_en INTEGER NOT NULL,
      PRIMARY KEY(lote_id, compra_id)
    )
    ''',
    'CREATE INDEX idx_lote_items_compra ON lote_items(compra_id)',
    'CREATE TABLE ajustes(clave TEXT PRIMARY KEY, valor TEXT NOT NULL)',
  ],
  2: [
    // Monto recibido al entregar o vender un lote (para calcular la utilidad neta).
    'ALTER TABLE lotes ADD COLUMN monto_recibido INTEGER',
  ],
  3: [
    // Nivel de llenado de la cerámica / monolito al comprar.
    "ALTER TABLE compras ADD COLUMN llenado TEXT NOT NULL DEFAULT 'entero'",
    // Lotes cerrados por el Supervisor (evitan volver a contar un mismo catalítico en otra revisión).
    '''
    CREATE TABLE lotes_supervisor(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      comprador TEXT NOT NULL DEFAULT '',
      prefijo TEXT NOT NULL DEFAULT '',
      rango_texto TEXT NOT NULL DEFAULT '',
      creado_en INTEGER NOT NULL,
      cerrado_en INTEGER NOT NULL,
      notas TEXT NOT NULL DEFAULT ''
    )
    ''',
    '''
    CREATE TABLE lotes_supervisor_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lote_sup_id INTEGER NOT NULL REFERENCES lotes_supervisor(id) ON DELETE CASCADE,
      codigo TEXT NOT NULL UNIQUE,
      fecha_compra INTEGER,
      vendedor TEXT NOT NULL DEFAULT '',
      tipo TEXT NOT NULL DEFAULT '',
      llenado TEXT NOT NULL DEFAULT 'entero',
      codigo_fabrica TEXT NOT NULL DEFAULT '',
      autos TEXT NOT NULL DEFAULT '',
      precio INTEGER NOT NULL DEFAULT 0,
      escaneado_en INTEGER,
      observacion_tipo TEXT NOT NULL DEFAULT '',
      observacion_nota TEXT NOT NULL DEFAULT ''
    )
    ''',
    'CREATE INDEX idx_lotes_sup_items_lote ON lotes_supervisor_items(lote_sup_id)',
  ],
};
