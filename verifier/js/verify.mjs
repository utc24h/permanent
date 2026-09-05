// Reference verifier for the randomness beacon.
//
// WebCrypto only. No dependencies, nothing to install.
//
//	node verify.mjs emission.jws
//	node verify.mjs https://.../2026/08/29/1730-emission.jws <public-key-hex>
//
// The core — derive(), deriveBlock(), Stream — runs unchanged in a browser.
// Only readSource() is Node-specific.

const HKDF_BLOCK = 64;
const DRAND_RELAY = "https://drand.cloudflare.com";

const subtle = globalThis.crypto?.subtle ?? (await import("node:crypto")).webcrypto.subtle;

// --- The byte stream -------------------------------------------------------

class Stream {
  constructor(seed, publicValue, context) {
    this.seed = seed;
    this.public = publicValue;
    this.context = context;
    this.buf = new Uint8Array(0);
    this.pos = 0;
  }

  async nextByte() {
    if (this.pos >= this.buf.length) {
      const info = concat(this.context, encode("|" + this.buf.length));
      const block = await hkdf(this.seed, this.public, info, HKDF_BLOCK);
      this.buf = concat(this.buf, block);
    }
    return this.buf[this.pos++];
  }

  // Uniform value in [0,limit) with no modulo bias: values above the last
  // whole multiple of limit are discarded and drawn again.
  async integer(limit) {
    if (limit <= 1) return 0;

    let width = 1;
    let space = 256;
    while (space < limit) {
      width++;
      space *= 256;
    }
    const cut = Math.floor(space / limit) * limit;

    for (;;) {
      let v = 0;
      for (let i = 0; i < width; i++) v = v * 256 + (await this.nextByte());
      if (v < cut) return v % limit;
    }
  }
}

// hkdf is HKDF-SHA256, RFC 5869. WebCrypto does both stages in one call.
async function hkdf(ikm, salt, info, length) {
  const key = await subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt, info },
    key,
    length * 8,
  );
  return new Uint8Array(bits);
}

// --- Derivation ------------------------------------------------------------

// A variant is published in one of two shapes, and this is the first thing a
// reimplementation gets wrong:
//
//   - composite carries an explicit "blocks" array
//   - every other group carries its parameters FLAT, and the mold is the
//     GROUP NAME, not a field
//
// Two more traps in the flat shape: random_matrix carries rows/cols instead of
// count, and truncated_continuous publishes min/max already multiplied by
// scale.
function blocksOf(group, v) {
  if (group === "composite") return v.blocks;
  const count = group === "random_matrix" ? v.rows * v.cols : v.count;
  return [{ mold: group, count, min: v.min, max: v.max }];
}

async function derive(em, name, spec) {
  const seed = fromHex(em.seed);
  const publicValue = fromHex(em.round.randomness);
  const base = `${em.version}|${name}|${em.drand_round}`;

  const blocks = [];
  for (let i = 0; i < spec.length; i++) {
    const s = new Stream(seed, publicValue, encode(`${base}|b${i}`));
    blocks.push(await deriveBlock(s, spec[i]));
  }
  return shape(name, spec, blocks);
}

async function deriveBlock(s, b) {
  const universe = b.max - b.min + 1;
  if (universe < 1) throw new Error(`empty universe [${b.min}..${b.max}]`);
  const count = b.count || 1;

  switch (b.mold) {
    case "discrete_uniform":
      return [b.min + (await s.integer(universe))];

    case "sample_without_replacement": {
      if (count > universe) throw new Error(`asks for ${count} out of ${universe}`);
      const out = await sampleWithoutReplacement(s, universe, count, b.min);
      return out.sort((x, y) => x - y);
    }

    case "permutation":
      if (count > universe) throw new Error(`asks for ${count} out of ${universe}`);
      return sampleWithoutReplacement(s, universe, count, b.min);

    case "uniform_vector_with_replacement":
    case "random_matrix": {
      const out = [];
      for (let i = 0; i < count; i++) out.push(b.min + (await s.integer(universe)));
      return out;
    }

    // min and max already carry the scale, so the span is read straight off
    // the file. Multiplying again is the classic reimplementation bug.
    case "truncated_continuous":
      return [b.min + (await s.integer(b.max - b.min + 1))];
  }
  throw new Error(`unknown mold "${b.mold}"`);
}

// Draws k distinct values in the order they come out, with a partial
// Fisher-Yates over a sparse map.
async function sampleWithoutReplacement(s, universe, count, min) {
  const moved = new Map();
  const out = [];

  for (let i = 0; i < count; i++) {
    const j = i + (await s.integer(universe - i));
    const vj = moved.has(j) ? moved.get(j) : j;
    const vi = moved.has(i) ? moved.get(i) : i;
    moved.set(j, vi);
    moved.set(i, vj);
    out.push(min + vj);
  }
  return out;
}

// shape renders the result the way the file publishes it. The shape depends on
// the mold: a scalar, a list, a list of rows, or one list per block.
function shape(name, spec, values) {
  if (spec.length > 1) return values;
  const flat = values[0];

  switch (spec[0].mold) {
    case "discrete_uniform":
    case "truncated_continuous":
      return flat[0];

    case "random_matrix": {
      const [rows, cols] = dimensions(name, flat.length);
      const out = [];
      for (let i = 0; i < rows; i++) out.push(flat.slice(i * cols, (i + 1) * cols));
      return out;
    }
  }
  return flat;
}

// dimensions reads the matrix shape from the variant name, m-<rows>x<cols>.
function dimensions(name, total) {
  const m = /^m-(\d+)x(\d+)$/.exec(name);
  if (m) {
    const rows = Number(m[1]);
    const cols = Number(m[2]);
    if (rows > 0 && cols > 0 && rows * cols === total) return [rows, cols];
  }
  return [1, total];
}

// --- Checks ----------------------------------------------------------------

async function main() {
  const [source, keyHex] = process.argv.slice(2);
  if (!source) {
    console.log("usage: node verify.mjs <file.jws|url> [public-key-hex]");
    process.exit(2);
  }

  let raw;
  try {
    raw = (await readSource(source)).trim();
  } catch (e) {
    unverifiable(`cannot read the file: ${e.message}`);
  }

  const parts = raw.split(".");
  if (parts.length !== 3) notVerified(`expected 3 dot-separated parts, got ${parts.length}`);
  const header = JSON.parse(decode(fromB64Url(parts[0])));
  const em = JSON.parse(decode(fromB64Url(parts[1])));

  console.log(
    `file      : ${em.type} turn ${em.utc_turn}, version ${em.version}, drand round ${em.drand_round}`,
  );
  console.log(`key id    : ${header.kid}`);

  // 1. Signature, over the RAW text: re-serializing the JSON changes the bytes
  // and breaks a signature that is perfectly valid.
  if (keyHex) {
    const signed = encode(parts[0] + "." + parts[1]);
    let ok;
    try {
      const key = await subtle.importKey("raw", fromHex(keyHex), "Ed25519", false, ["verify"]);
      ok = await subtle.verify("Ed25519", key, fromB64Url(parts[2]), signed);
    } catch {
      unverifiable("this runtime has no Ed25519 in WebCrypto");
    }
    if (!ok) notVerified("the Ed25519 signature does not verify");
    console.log("signature : OK");
  } else {
    console.log("signature : SKIPPED, no public key given");
  }

  // 2. The revealed seed must hash to what was committed.
  const sum = new Uint8Array(await subtle.digest("SHA-256", fromHex(em.seed)));
  if (toHex(sum) !== em.seed_sha256) {
    notVerified("SHA-256 of the seed does not match seed_sha256");
  }
  console.log("seed      : OK, matches its own hash");

  // 3. The public value comes from drand, not from us. Ask them.
  try {
    const body = await readSource(`${DRAND_RELAY}/public/${em.drand_round}`);
    if (JSON.parse(body).randomness !== em.round.randomness) {
      notVerified(`drand round ${em.drand_round} carries a different randomness`);
    }
    console.log(`drand     : OK, round ${em.drand_round} carries this randomness`);
  } catch (e) {
    console.log(`drand     : SKIPPED, ${e.message}`);
  }

  // 4. Every number, reproduced from the seed and the round.
  let checked = 0;
  let failed = 0;
  for (const [group, variants] of Object.entries(em.variants)) {
    for (const [name, v] of Object.entries(variants)) {
      const got = JSON.stringify(await derive(em, name, blocksOf(group, v)));
      const want = JSON.stringify(v.result);
      if (got !== want) {
        failed++;
        console.log(`  ${name.padEnd(24)} MISMATCH\n     expected ${want}\n     computed ${got}`);
        continue;
      }
      checked++;
    }
  }
  if (failed > 0) notVerified(`${failed} of ${checked + failed} variants do not reproduce`);
  console.log(`numbers   : OK, ${checked} variants reproduced`);

  console.log("\nVERIFIED");
}

// --- Plumbing --------------------------------------------------------------

const encode = (s) => new TextEncoder().encode(s);
const decode = (b) => new TextDecoder().decode(b);

function concat(a, b) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

function fromHex(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

const toHex = (bytes) => [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");

function fromB64Url(s) {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), "="));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

async function readSource(source) {
  if (/^https?:\/\//.test(source)) {
    const resp = await fetch(source);
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    return resp.text();
  }
  const { readFile } = await import("node:fs/promises");
  return readFile(source, "utf8");
}

function notVerified(message) {
  console.log(`\nNOT VERIFIED: ${message}`);
  process.exit(1);
}

function unverifiable(message) {
  console.log(`\nUNVERIFIABLE: ${message}`);
  process.exit(3);
}

await main();
