/* Packaging selected harmonised variables as R code you can run.

   The bundle is the repository's own `R/` folder with only the variables you
   picked: the same runner, the same loader, the same derive() scripts, shipped
   verbatim. Nothing here rewrites or regenerates R — a bundle-specific runner
   would be a second implementation of the join, the identifier cleaning and
   the duplicate resolution, and the day it drifted from the tested one the
   researcher's numbers would quietly stop matching this repository's.

   It is built in the browser rather than by the server so it still works on a
   static deploy, where there is no server to ask.

   Loaded on demand — see downloadBundle() in app.js. */

const ZIP_VERSION = 20;         // 2.0: the floor for deflate
const UTF8_NAMES = 0x0800;      // filenames below are ASCII, but say so anyway
const STORED = 0;
const DEFLATED = 8;

/* ── A zip file, by hand ───────────────────────────────────────────────
   Small enough to be worth it: the alternative is a dependency, and this
   repository's Python has none by policy. The format is the 1989 one — local
   header per entry, central directory, end record — with no zip64 and no data
   descriptors, neither of which a few dozen kilobytes of R can need. */

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[i] = c >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/* MS-DOS packed date and time — two's the resolution, so seconds are halved.
   Zip has carried these since before the study's first sweep was archived. */
function dosStamp(d) {
  const time = (d.getHours() << 11) | (d.getMinutes() << 5) | (d.getSeconds() >> 1);
  const date = ((d.getFullYear() - 1980) << 9) | ((d.getMonth() + 1) << 5) | d.getDate();
  return { time: time & 0xffff, date: date & 0xffff };
}

/* Raw deflate via the platform, when it has it. Returns null rather than
   throwing, so an older browser gets a stored (uncompressed) archive that is
   larger and equally valid. */
async function deflate(bytes) {
  if (typeof CompressionStream !== "function") return null;
  try {
    const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("deflate-raw"));
    const out = new Uint8Array(await new Response(stream).arrayBuffer());
    // Incompressible input can come back longer; store it instead.
    return out.length < bytes.length ? out : null;
  } catch {
    return null;
  }
}

function block(size) {
  const bytes = new Uint8Array(size);
  return { bytes, view: new DataView(bytes.buffer) };
}

export async function zip(entries, when = new Date()) {
  const encoder = new TextEncoder();
  const { time, date } = dosStamp(when);
  const chunks = [];
  const central = [];
  let offset = 0;

  for (const [path, text] of entries) {
    const name = encoder.encode(path);
    const data = encoder.encode(text);
    const packed = await deflate(data);
    const body = packed || data;
    const method = packed ? DEFLATED : STORED;
    const sum = crc32(data);

    const local = block(30);
    local.view.setUint32(0, 0x04034b50, true);
    local.view.setUint16(4, ZIP_VERSION, true);
    local.view.setUint16(6, UTF8_NAMES, true);
    local.view.setUint16(8, method, true);
    local.view.setUint16(10, time, true);
    local.view.setUint16(12, date, true);
    local.view.setUint32(14, sum, true);
    local.view.setUint32(18, body.length, true);
    local.view.setUint32(22, data.length, true);
    local.view.setUint16(26, name.length, true);
    chunks.push(local.bytes, name, body);

    const entry = block(46);
    entry.view.setUint32(0, 0x02014b50, true);
    entry.view.setUint16(4, ZIP_VERSION, true);
    entry.view.setUint16(6, ZIP_VERSION, true);
    entry.view.setUint16(8, UTF8_NAMES, true);
    entry.view.setUint16(10, method, true);
    entry.view.setUint16(12, time, true);
    entry.view.setUint16(14, date, true);
    entry.view.setUint32(16, sum, true);
    entry.view.setUint32(20, body.length, true);
    entry.view.setUint32(24, data.length, true);
    entry.view.setUint16(28, name.length, true);
    // Regular file, 0644. Left at zero, some unzips produce unreadable modes.
    entry.view.setUint32(38, ((0o100644 << 16) >>> 0), true);
    entry.view.setUint32(42, offset, true);
    central.push(entry.bytes, name);

    offset += local.bytes.length + name.length + body.length;
  }

  const size = central.reduce((n, c) => n + c.length, 0);
  const end = block(22);
  end.view.setUint32(0, 0x06054b50, true);
  end.view.setUint16(8, entries.length, true);
  end.view.setUint16(10, entries.length, true);
  end.view.setUint32(12, size, true);
  end.view.setUint32(16, offset, true);

  return new Blob([...chunks, ...central, end.bytes], { type: "application/zip" });
}

/* ── What goes in it ───────────────────────────────────────────────────── */

const STATUS_NOTE = {
  verified: "run against the real study data, and the output checked",
  ready_for_real_data_test: "passes its synthetic tests; not yet run on real data",
  draft: "synthetic tests only — output not yet trusted",
};

function readme(picked, { dataset, repo, root, env, built }) {
  const term = dataset?.wave?.plural || "sweeps";
  const name = dataset?.fullName || dataset?.name || "the study";
  const files = [...new Set(picked.flatMap((d) => d.source_files || []))].sort();

  /* Longitudinal siblings are conventionally named for the wave they cover,
     and those names do not sort. Alphabetically, 42m follows 34y and 5y comes
     after 51y — an order that makes a family look wrong at a glance. Where
     the suffix names a known wave, use the study's own order; anything else
     keeps its place at the end, alphabetically. */
  const waves = dataset?.wave?.order || [];
  const waveRank = (id) => {
    const i = waves.indexOf(String(id).slice(String(id).lastIndexOf("_") + 1));
    return i === -1 ? waves.length : i;
  };
  const byWave = (a, b) =>
    waveRank(a.id) - waveRank(b.id) || a.id.localeCompare(b.id);

  picked = [...picked].sort((a, b) =>
    (a.family || "").localeCompare(b.family || "") || byWave(a, b));
  const drafts = picked.filter((d) => d.status !== "verified");

  // The pipeline may offer no data-root override, in which case the only
  // way to run it is with the deposits alongside — so that becomes the
  // instruction rather than the fallback.
  const running = env
    ? `From this directory, pointing at wherever your deposits are:

    ${env}=/path/to/${root} Rscript R/runner.R

If \`${root}/\` is already in this directory, the variable can be left out:

    Rscript R/runner.R`
    : `Put this \`R\` folder beside your \`${root}/\` directory, then from the
directory holding both:

    Rscript R/runner.R`;

  return `# ${picked.length} harmonised variable${picked.length === 1 ? "" : "s"} from ${name}

Downloaded from the variable atlas on ${new Date().toISOString().slice(0, 10)}.
Built from ${repo ? `https://github.com/${repo}` : "the harmonisation repository"}${built ? `, site data of ${built}` : ""}.

**This archive contains no study data** — only R scripts. You supply the
deposits, and nothing here writes to them.

## What you need

- R (base only — no packages to install)
- Your own licensed copy of ${name}'s deposits, in the standard
  \`${root}/\` layout: one directory per ${dataset?.wave?.term || "sweep"}, plus
  \`master_file_info_lookup.csv\` at its top level

## Running it

${running}

Either way the result is written to \`output/derived_variables.csv\`: one row per
cohort member, one column per variable below, joined on \`${dataset?.identifier || "the identifier"}\`.

To run a single variable rather than all of them, name it:

    Rscript R/runner.R ${picked[0]?.id || "<id>"}

## What is included

${picked.map((d) => `- **${d.id}** — ${d.label || "no label"}
  <br>_${String(d.status || "unknown").replace(/_/g, " ")}_: ${STATUS_NOTE[d.status] || "status unknown"}${d.github_issue ? ` · issue #${d.github_issue}` : ""}`).join("\n")}

Each script declares the deposited files and raw variables it reads. Between
them these need:

${files.map((f) => `- \`${f}\``).join("\n")}

A variable whose source file is missing from your copy will stop the run with a
message naming it. Run the others by naming them individually.

${drafts.length ? `## Read this before using the output

${drafts.length} of these ${drafts.length === 1 ? "is" : "are"} not verified against real data:

${drafts.map((d) => `- **${d.id}** — ${String(d.status).replace(/_/g, " ")}`).join("\n")}

A variable's synthetic tests check that its recoding does what it says on
fabricated rows. They cannot tell you that the codes it recodes are the codes
your deposit actually uses. Check these against the data dictionaries before
you rely on them, and please report back through the repository's issues.

` : ""}## What is in here

    R/runner.R      discovers the variable scripts, loads what they declare,
                    joins on the identifier, writes output/
    R/lib/io.R      resolves and reads deposited files; normalises identifiers
    R/lib/utils.R   shared recoding helpers
    R/lib/discovery.R  finds and validates variable scripts
    R/variables/    one script per variable, unchanged from the repository

These are copied verbatim, so the code you are running is the code that was
tested. Re-download rather than editing in place, and if you change a
derivation, please open a pull request so everyone gets it.

## Families

Variables measuring the same concept, usually one per ${dataset?.wave?.term || "wave"}.
Where a ${dataset?.wave?.term || "wave"} is missing from a family it is generally because the
study did not measure it then — check the variable's notes in the atlas rather
than assuming the ${term} are comparable.

${[...new Set(picked.map((d) => d.family))].filter(Boolean).sort()
  .map((f) => `- **${f}** — ${picked.filter((d) => d.family === f)
    .sort(byWave).map((d) => d.id).join(", ")}`).join("\n")}
`;
}

/* The archive: a README, the pipeline verbatim, and one file per selected
   variable at the path the runner expects to find it. */
export async function build(picked, pipeline, meta) {
  const root = pipeline.root || "data";
  const entries = [];
  const folder = `${meta.dataset?.key || "atlas"}-variables-${new Date().toISOString().slice(0, 10)}`;

  entries.push([`${folder}/README.md`,
                readme(picked, { ...meta, root, env: pipeline.env || "" })]);

  for (const [path, text] of Object.entries(pipeline.files)) {
    entries.push([`${folder}/${path}`, text]);
  }

  for (const d of picked) {
    // Its real path in the repository. The runner validates that the
    // category directory matches the script's own spec$category, so this
    // has to be the declared path rather than one reassembled from fields.
    if (!d.file || !d.source) continue;
    entries.push([`${folder}/${d.file}`, d.source]);
  }

  return { name: `${folder}.zip`, blob: await zip(entries) };
}
