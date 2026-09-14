/* Packaging selected variables as R code you can run.

   The bundle is the repository's own `R/` folder with only the variables you
   picked: the same runner, the same loader, the same derive() scripts, shipped
   verbatim. Nothing here rewrites or regenerates a harmonised variable — a
   bundle-specific runner would be a second implementation of the join, the
   identifier cleaning and the duplicate resolution, and the day it drifted
   from the tested one the researcher's numbers would quietly stop matching
   this repository's.

   Raw columns are the one thing generated, because there is nothing to copy:
   a deposited column has no script in the repository. What is generated is
   deliberately the thinnest possible thing — a variable script whose derive()
   is the identity, written from templates/passthrough.R. It declares a source
   file and a source variable like any other, so runner.R does the resolving,
   the identifier cleaning, the duplicate resolution and the join for it too.
   The rule above therefore still holds: no second implementation of anything,
   only a second kind of leaf.

   It is built in the browser rather than by the server so it still works on a
   static deploy, where there is no server to ask.

   Loaded on demand — see download() in atlas/basket.js. */

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

/* ── Generating a passthrough ──────────────────────────────────────────

   The one piece of R this file writes. Everything substituted into the
   template is either a name the researcher chose (already constrained by
   basket.js to letters, digits, _ and .) or a string out of the dictionaries,
   which can contain anything at all — so labels and notes are escaped for an
   R double-quoted string rather than trusted. */

const rString = (s) => String(s ?? "")
  .replace(/\\/g, "\\\\")
  .replace(/"/g, '\\"')
  .replace(/\r?\n/g, " ")
  .trim();

// Passthroughs must still satisfy R/lib/discovery.R: three levels below
// R/variables/, a first level that is one of the fixed categories and equals
// spec$category, and a file name that equals spec$id. "other" is the honest
// category for a raw column, and the family groups them by the deposit they
// came from, which is the only grouping a raw column actually has.
const PASSTHROUGH_CATEGORY = "other";
const familyFor = (file) => `raw_${String(file).replace(/[^A-Za-z0-9_.]/g, "_")}`;

export const passthroughPath = (raw) =>
  `R/variables/${PASSTHROUGH_CATEGORY}/${familyFor(raw.file)}/${raw.column}.R`;

/* ── The project around the scripts ─────────────────────────────────────

   A download used to be a folder of R and a README that said which command to
   type. That is fine if you already work in a terminal and it is a wall if you
   do not — and "the working directory was wrong" and "R could not find the
   data" are between them almost every way this fails.

   So the bundle is an RStudio project: opening the .Rproj sets the working
   directory, run.R is the one file to run, and `data/` is a real folder with a
   note in it saying what to put there. run.R checks the working directory, the
   data root and every deposited file it will need BEFORE sourcing the runner,
   and each failure says what to do rather than what went wrong. */

function scaffold(template, fill) {
  const keys = Object.keys(fill).join("|");
  // A function replacement, not a string: values are data and must never be
  // read as `$1`/`$&` replacement patterns. Keys are all [a-z_] by
  // construction, so the alternation needs no escaping of its own.
  return template.replace(new RegExp(`\\{\\{(${keys})\\}\\}`, "g"),
                          (_, key) => fill[key]);
}

/* Most of run.R's placeholders land inside R double-quoted strings, so they
   are escaped on the way in exactly as a passthrough's label is. Two are not
   strings at all — `set_root` is a statement and `files` is a c(...) vector —
   and escaping those would turn working R into a syntax error.

   These values come from dataset.toml rather than from the dictionaries, so
   this is insurance rather than a live hazard. It is cheap insurance: the
   atlas is meant to be pointed at another study by editing that file, and a
   study whose name carried a quote would otherwise produce a bundle that
   would not parse. */
const R_CODE_FIELDS = new Set(["set_root", "files"]);

const escapeForR = (fill) => Object.fromEntries(
  Object.entries(fill).map(([key, value]) =>
    [key, R_CODE_FIELDS.has(key) ? value : rString(value)]));

// An R character vector, one name per line so a long list stays readable in
// the file the researcher opens.
const rVector = (names) => names.length
  ? `c(\n${names.map((n) => `  "${rString(n)}"`).join(",\n")}\n)`
  : "character(0)";

/* How run.R tells io.R where to read from. A pipeline that offers no data-root
   override cannot be pointed anywhere, so say that plainly at the point it
   would have mattered rather than leaving a setting that does nothing. */
function setRoot(env, root) {
  return env
    ? `Sys.setenv(${env} = data_dir)`
    : `if (!identical(data_dir, normalizePath("${root}", mustWork = FALSE))) {
  fail(
    "This pipeline reads its data from a ${root}/ folder in the working\n",
    "directory and offers no way to point somewhere else, so the deposits\n",
    "have to sit beside this file.\n\n",
    "  Found them in: ", data_dir, "\n\n",
    "Move or symlink them to: ", file.path(getwd(), "${root}"), "\n"
  )
}`;
}

function passthrough(raw, template, today) {
  // Raw values here, escaped once on the way in below. Escaping a field as it
  // is collected AND again as it is substituted turns a label's quote into
  // `\\"` and its backslash into `\\\\`, which R reads back as literal
  // backslashes rather than as the label the dictionary recorded.
  const fill = {
    id: raw.column,
    var: raw.name,
    file: raw.file,
    wave: raw.wave || "",
    label: raw.label || raw.name,
    created: today,
  };
  return template.replace(/\{\{(id|var|file|wave|label|created)\}\}/g,
                          (_, key) => rString(fill[key]));
}

/* ── The README ────────────────────────────────────────────────────────── */

const STATUS_NOTE_RAW =
  "not harmonised — the deposited codes, unchanged and not recoded";

function readme({ derived, raw }, { dataset, repo, root, lookup, project, env, built }) {
  const term = dataset?.wave?.plural || "sweeps";
  const name = dataset?.fullName || dataset?.name || "the study";
  const total = derived.length + raw.length;
  const files = [...new Set([
    ...derived.flatMap((d) => d.source_files || []),
    ...raw.map((r) => r.file),
  ])].sort();

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

  derived = [...derived].sort((a, b) =>
    (a.family || "").localeCompare(b.family || "") || byWave(a, b));
  const drafts = derived.filter((d) => d.status !== "verified");

  // waveRank, not waves.indexOf: a wave the config does not list yields -1 from
  // indexOf and would sort BEFORE every known one, while the harmonised list
  // three lines up deliberately sorts it last. One README, one order.
  const rank = (w) => {
    const i = waves.indexOf(w);
    return i === -1 ? waves.length : i;
  };
  const rawSorted = [...raw].sort((a, b) =>
    (rank(a.wave) - rank(b.wave)) || a.column.localeCompare(b.column));

  const first = derived[0]?.id || rawSorted[0]?.column || "<id>";

  return `# ${total} variable${total === 1 ? "" : "s"} from ${name}

${derived.length} harmonised · ${raw.length} raw.
Downloaded from the variable atlas on ${new Date().toISOString().slice(0, 10)}.
Built from ${repo ? `https://github.com/${repo}` : "the harmonisation repository"}${built ? `, site data of ${built}` : ""}.

**This archive contains no study data** — only R scripts. You supply the
deposits, and nothing here writes to them.

## What you need

- R (base only — **no packages to install**)
- Your own licensed copy of ${name}'s deposits: one directory per
  ${dataset?.wave?.term || "sweep"}, plus \`${lookup}\` at its top level

## Running it

**1. Open \`${project}.Rproj\`.** That starts RStudio with the working directory
already set to this folder — which is the single most common thing to get
wrong. No RStudio? Just \`setwd()\` to this folder instead.

**2. Tell it where your data is.** Either one:

- **Put the data here.** Copy your deposit folders into the \`data/\` folder, so
  that \`data/${lookup}\` exists. See \`data/README.md\`.
${env ? `- **Point at data you already have.** Open \`run.R\` and set:

      DATA_DIR <- "~/${root}"
` : `- There is no second option for this study: its pipeline reads from a
  \`${root}/\` folder in the working directory and offers no override, so the
  deposits have to be here. A symbolic link counts.
`}
**3. Run \`run.R\`.** In RStudio, click *Source*. In a terminal, \`Rscript run.R\`.

That is all of it. \`run.R\` checks the working directory, the data folder and
every deposited file it needs *before* it starts, and if something is not ready
it says what to do about it rather than failing part-way through.

The result is written to \`output/derived_variables.csv\`: one row per cohort
member, one column per variable below, joined on
\`${dataset?.identifier || "the identifier"}\`. Raw and harmonised columns sit
side by side in that one file — the join, the identifier cleaning and the
duplicate resolution are the same code for both.

To build one variable rather than all of them while you check it, set this near
the top of \`run.R\`:

    VARIABLES <- c("${first}")
${derived.length ? `
## Harmonised variables

Each of these is one script from the repository, copied verbatim, that turns
raw variables into a single comparable column.

${derived.map((d) => `- **${d.id}** — ${d.label || "no label"}
  <br>_${String(d.status || "unknown").replace(/_/g, " ")}_: ${STATUS_NOTE[d.status] || "status unknown"}${d.github_issue ? ` · issue #${d.github_issue}` : ""}`).join("\n")}
` : ""}${rawSorted.length ? `
## Raw variables

These are **not** harmonised. Each one carries a single deposited column
through unchanged, under the name you chose. The generated script does no
recoding whatsoever, so the values you get are the codes as deposited —
**missing-value sentinels included**. Negative codes in this corpus are
usually missing-value markers, and the schemes are not consistent between
variables or between ${term}. Look each one up in its data dictionary before
you analyse it.

${rawSorted.map((r) => `- **${r.column}** — \`${r.name}\` from \`${r.file}\` (${r.wave})${
  r.label ? `
  <br>${r.label}` : ""}
  <br>_raw_: ${STATUS_NOTE_RAW}`).join("\n")}

If you find yourself writing the same recoding for one of these by hand, that
is the point at which it is worth requesting a harmonised variable through the
atlas instead — then everyone gets the same one, tested.
` : ""}
## Source files

Between them these variables need:

${files.map((f) => `- \`${f}\``).join("\n")}

A variable whose source file is missing from your copy will stop the run with a
message naming it. Run the others by naming them individually.

${drafts.length ? `## Read this before using the output

${drafts.length} of the harmonised variables ${drafts.length === 1 ? "is" : "are"} not verified against real data:

${drafts.map((d) => `- **${d.id}** — ${String(d.status).replace(/_/g, " ")}`).join("\n")}

A variable's synthetic tests check that its recoding does what it says on
fabricated rows. They cannot tell you that the codes it recodes are the codes
your deposit actually uses. Check these against the data dictionaries before
you rely on them, and please report back through the repository's issues.

` : ""}## What is in here

    ${project}.Rproj
                    open this first — it sets the working directory
    run.R           the file you run: checks everything, then runs the pipeline
    data/           where your deposits go, if you want them inside the project
    output/         where results are written (created on the first run)

    R/runner.R      discovers the variable scripts, loads what they declare,
                    joins on the identifier, writes output/
    R/lib/io.R      resolves and reads deposited files; normalises identifiers
    R/lib/utils.R   shared recoding helpers
    R/lib/discovery.R  finds and validates variable scripts
    R/variables/    one script per variable${rawSorted.length ? `; the ones under
                    other/raw_*/ were generated here for your raw columns,
                    everything else is unchanged from the repository` : ", unchanged from the repository"}

Nothing here writes to your data. \`R/lib/io.R\` opens files for reading only,
and results go to \`output/\`.

## If something goes wrong

\`run.R\` stops with an explanation rather than a stack trace. The three it
catches before anything reads a file:

- **Wrong working directory** — it cannot see its own \`R/\` folder. Open
  \`${project}.Rproj\`, or \`setwd()\` to this folder.
- **It cannot find your data** — it lists every place it looked and what it
  found there. Set \`DATA_DIR\` in \`run.R\`, or put the deposits in \`data/\`.
- **A deposited file is missing** — it names which, before the run rather than
  during it. Build the rest by naming them in \`VARIABLES\`.

Warnings *during* a run about dropped or conflicting identifiers are not
errors. Some deposits carry rows whose identifier cannot be linked to a cohort
member, and some carry the same identifier twice with disagreeing values;
\`R/lib/io.R\` drops both and says so, because nothing in the deposit says which
record is authoritative. A real-data run may therefore report a lower N than
the raw file, and that is the pipeline refusing to guess.

The harmonised scripts are copied verbatim, so the code you are running is the
code that was tested. Re-download rather than editing in place, and if you
change a derivation, please open a pull request so everyone gets it.
${derived.length ? `
## Families

Variables measuring the same concept, usually one per ${dataset?.wave?.term || "wave"}.
Where a ${dataset?.wave?.term || "wave"} is missing from a family it is generally because the
study did not measure it then — check the variable's notes in the atlas rather
than assuming the ${term} are comparable.

${[...new Set(derived.map((d) => d.family))].filter(Boolean).sort()
  .map((f) => `- **${f}** — ${derived.filter((d) => d.family === f)
    .sort(byWave).map((d) => d.id).join(", ")}`).join("\n")}
` : ""}`;
}

/* The archive: a README, the pipeline verbatim, one file per selected
   harmonised variable at the path the runner expects, and one generated
   passthrough per raw column. */
export async function build(picked, pipeline, meta) {
  const { derived = [], raw = [] } = picked;
  const root = pipeline.root || "data";
  const lookup = pipeline.lookup || "master_file_info_lookup.csv";
  const env = pipeline.env || "";
  const entries = [];
  const today = new Date().toISOString().slice(0, 10);
  const folder = `${meta.dataset?.key || "atlas"}-variables-${today}`;

  entries.push([`${folder}/README.md`,
                readme({ derived, raw },
                       { ...meta, root, lookup, env, project: folder, built: meta.built })]);

  for (const [path, text] of Object.entries(pipeline.files)) {
    entries.push([`${folder}/${path}`, text]);
  }

  // The project scaffolding. Every deposited file the whole bundle touches is
  // resolved by run.R up front, so a missing one is named before the run
  // rather than discovered in the middle of it.
  const needed = [...new Set([
    ...derived.flatMap((d) => d.source_files || []),
    ...raw.map((r) => r.file),
  ])].sort();

  const scaffoldFill = {
    dataset: meta.dataset?.fullName || meta.dataset?.name || "the study",
    project: folder,
    root,
    lookup,
    env,
    identifier: meta.dataset?.identifier || "the identifier",
    set_root: setRoot(env, root),
    files: rVector(needed),
    wave_plural: meta.dataset?.wave?.plural || "sweeps",
    sample_wave: meta.dataset?.wave?.order?.[0] || "<wave>",
    sample_id: derived[0]?.id || raw[0]?.column || "<id>",
  };

  const template = (path) => {
    const text = pipeline.templates?.[path];
    if (!text) throw new Error(`${path} is missing from pipeline.json — rebuild the site`);
    return text;
  };

  entries.push([`${folder}/run.R`,
                scaffold(template("templates/run.R"), escapeForR(scaffoldFill))]);
  entries.push([`${folder}/${folder}.Rproj`, template("templates/project.Rproj")]);
  entries.push([`${folder}/data/README.md`,
                scaffold(template("templates/data-README.md"), scaffoldFill)]);

  for (const d of derived) {
    // Its real path in the repository. The runner validates that the
    // category directory matches the script's own spec$category, so this
    // has to be the declared path rather than one reassembled from fields.
    if (!d.file || !d.source) continue;
    entries.push([`${folder}/${d.file}`, d.source]);
  }

  for (const r of raw) {
    entries.push([`${folder}/${passthroughPath(r)}`,
                  passthrough(r, template("templates/passthrough.R"), today)]);
  }

  return { name: `${folder}.zip`, blob: await zip(entries) };
}
