// API de misiones de OrigenLabs Mapper.
//
// Cada usuario se identifica con un "código de sincronización" (por ejemplo
// ABCD-EFGH-JKLM-NPQR-STUV) que la app genera en el primer dispositivo y se
// ingresa en los demás. El servidor solo guarda el hash SHA-256 del código.

import crypto from "node:crypto";
import express from "express";
import pg from "pg";

const PORT = process.env.PORT || 8080;
const DATABASE_URL = process.env.DATABASE_URL;
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || "")
  .split(",")
  .map((o) => o.trim())
  .filter(Boolean);

if (!DATABASE_URL) {
  console.error("Falta la variable DATABASE_URL");
  process.exit(1);
}

const pool = new pg.Pool({
  connectionString: DATABASE_URL,
  // La red privada de Railway no usa SSL; la URL pública sí
  ssl: DATABASE_URL.includes(".railway.internal")
    ? false
    : { rejectUnauthorized: false },
  max: 5,
});

async function migrate() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS missions (
      id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      workspace   char(64)    NOT NULL,
      name        text        NOT NULL,
      data        jsonb       NOT NULL,
      created_at  timestamptz NOT NULL DEFAULT now(),
      updated_at  timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS missions_workspace_idx
      ON missions (workspace, updated_at DESC);
  `);
}

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "2mb" }));

// CORS: solo los dominios de la app
app.use((req, res, next) => {
  const origin = req.get("Origin");
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    res.set("Access-Control-Allow-Origin", origin);
    res.set("Vary", "Origin");
    res.set("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, X-Workspace-Key");
    res.set("Access-Control-Max-Age", "600");
  }
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

app.get("/health", (_req, res) => res.json({ ok: true }));

const KEY_PATTERN = /^[A-Z2-7]{4}(-[A-Z2-7]{4}){4}$/;
const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function workspace(req, res, next) {
  const key = (req.get("X-Workspace-Key") || "").trim().toUpperCase();
  if (!KEY_PATTERN.test(key)) {
    return res.status(401).json({ error: "Código de sincronización inválido" });
  }
  req.workspace = crypto.createHash("sha256").update(key).digest("hex");
  next();
}

function validId(req, res, next) {
  if (!UUID_PATTERN.test(req.params.id)) {
    return res.status(404).json({ error: "Misión no encontrada" });
  }
  next();
}

function cleanName(name) {
  if (typeof name !== "string") return null;
  const n = name.trim().slice(0, 120);
  return n.length ? n : null;
}

const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

app.get(
  "/missions",
  workspace,
  wrap(async (req, res) => {
    const { rows } = await pool.query(
      `SELECT id, name, data->'summary' AS summary, created_at, updated_at
         FROM missions WHERE workspace = $1
        ORDER BY updated_at DESC LIMIT 500`,
      [req.workspace]
    );
    res.json(rows);
  })
);

app.get(
  "/missions/:id",
  workspace,
  validId,
  wrap(async (req, res) => {
    const { rows } = await pool.query(
      `SELECT id, name, data, created_at, updated_at
         FROM missions WHERE id = $1 AND workspace = $2`,
      [req.params.id, req.workspace]
    );
    if (!rows.length) return res.status(404).json({ error: "Misión no encontrada" });
    res.json(rows[0]);
  })
);

app.post(
  "/missions",
  workspace,
  wrap(async (req, res) => {
    const name = cleanName(req.body?.name);
    const data = req.body?.data;
    if (!name || typeof data !== "object" || data === null) {
      return res.status(400).json({ error: "Faltan el nombre o los datos" });
    }
    const { rows } = await pool.query(
      `INSERT INTO missions (workspace, name, data)
       VALUES ($1, $2, $3)
       RETURNING id, name, created_at, updated_at`,
      [req.workspace, name, data]
    );
    res.status(201).json(rows[0]);
  })
);

app.put(
  "/missions/:id",
  workspace,
  validId,
  wrap(async (req, res) => {
    const name = req.body?.name === undefined ? undefined : cleanName(req.body.name);
    const data = req.body?.data;
    if (name === null) return res.status(400).json({ error: "Nombre inválido" });
    if (data !== undefined && (typeof data !== "object" || data === null)) {
      return res.status(400).json({ error: "Datos inválidos" });
    }
    const { rows } = await pool.query(
      `UPDATE missions
          SET name = COALESCE($3, name),
              data = COALESCE($4, data),
              updated_at = now()
        WHERE id = $1 AND workspace = $2
        RETURNING id, name, created_at, updated_at`,
      [req.params.id, req.workspace, name ?? null, data ?? null]
    );
    if (!rows.length) return res.status(404).json({ error: "Misión no encontrada" });
    res.json(rows[0]);
  })
);

app.delete(
  "/missions/:id",
  workspace,
  validId,
  wrap(async (req, res) => {
    const { rowCount } = await pool.query(
      `DELETE FROM missions WHERE id = $1 AND workspace = $2`,
      [req.params.id, req.workspace]
    );
    if (!rowCount) return res.status(404).json({ error: "Misión no encontrada" });
    res.sendStatus(204);
  })
);

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: "Error interno del servidor" });
});

migrate()
  .then(() => {
    app.listen(PORT, () => console.log(`API de misiones en el puerto ${PORT}`));
  })
  .catch((err) => {
    console.error("No se pudo preparar la base de datos", err);
    process.exit(1);
  });
