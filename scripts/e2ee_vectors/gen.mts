// Regenerates test/fixtures/e2ee_vectors.json from the harness CLI's OWN crypto — core.ts,
// passwordPake.ts and terminalBinary.ts, imported straight out of the sibling checkout — so the
// Dart port in lib/e2ee/ is checked against the code every paired machine actually runs, not
// against numbers somebody copied by hand.
//
//   HARNESS_REPO_ROOT=../autonomous-harness \
//     "$HARNESS_REPO_ROOT/cli/node_modules/.bin/tsx" scripts/e2ee_vectors/gen.mts
//
// Every value is deterministic (seeded RNG, Ed25519 is deterministic, AEAD is a pure function of
// key/nonce/aad/plaintext), so a regenerated file only differs when the CLI's crypto did. The
// sha256 of each source file is recorded under `meta`; test/e2ee/e2ee_vectors_test.dart pins the
// core.ts one, so a changed core.ts fails the Dart suite until somebody re-reads the port.
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(here, '..', '..')
const harnessRoot = resolve(process.env.HARNESS_REPO_ROOT ?? join(repoRoot, '..', 'autonomous-harness'))
const libDir = join(harnessRoot, 'cli', 'src', 'lib')
const sources = {
  core: join(libDir, 'e2ee', 'core.ts'),
  passwordPake: join(libDir, 'e2ee', 'passwordPake.ts'),
  relayClient: join(libDir, 'e2ee', 'relayClient.ts'),
  terminalBinary: join(libDir, 'terminalBinary.ts'),
}

const C = await import(pathToFileURL(sources.core).href)
const PW = await import(pathToFileURL(sources.passwordPake).href)
const TB = await import(pathToFileURL(sources.terminalBinary).href)

const hex = (u: Uint8Array): string => Buffer.from(u).toString('hex')
const sha256File = (path: string): string => createHash('sha256').update(readFileSync(path)).digest('hex')

/** The exact LCG core.test.ts uses, so the CPace vector below is the one that file pins. */
function seeded(seed: number): (n: number) => Uint8Array {
  let s = seed >>> 0
  return (n: number) => {
    const o = new Uint8Array(n)
    for (let i = 0; i < n; i++) { s = (Math.imul(s, 1103515245) + 12345) & 0x7fffffff; o[i] = s & 0xff }
    return o
  }
}

function git(...args: string[]): string {
  try { return execFileSync('git', ['-C', harnessRoot, ...args], { encoding: 'utf8' }).trim() } catch { return '' }
}

const machineId = 'f2e0383771b734e4fc00f0bc8ccf060f'

// ── identities, hello, session keys, welcome ─────────────────────────────────────────────────────
const adapterId = C.newIdentity(seeded(10)) // the remote machine
const clientId = C.newIdentity(seeded(20)) // this app
const clientEph = C.newEphemeral(seeded(3))
const adapterEph = C.newEphemeral(seeded(4))
const keys = C.sessionKeys(clientEph.priv, adapterEph.pub, machineId, clientEph.pub, adapterEph.pub)
const groupKey = seeded(7)(32)
const welcomeInitial = { groupKey: C.b64e(groupKey), epoch: 'ab12cd34', features: { terminalP2p: 1 } }

// ── the rekey that rotates the group key mid-session ─────────────────────────────────────────────
const nextGroupKey = seeded(8)(32)
const rekeyed = { groupKey: C.b64e(nextGroupKey), epoch: 'cd34ef56' }

// ── binary terminal frames (HTRM v3) and their loopback (HTRL) twins ─────────────────────────────
const terminalC2s = TB.deriveTerminalBinaryKey(keys.c2s)
const terminalS2c = TB.deriveTerminalBinaryKey(keys.s2c)
const streamId = '0f8fad5b-d9cb-469f-a165-70867728950e'
const terminalFrames = [
  { dir: 'c2s', counter: 0, frame: { kind: 1, streamId, seq: 0, bytes: C.utf8('ls -la\r'), compressed: false } },
  { dir: 's2c', counter: 7, frame: { kind: 3, streamId, seq: 42, bytes: C.utf8('\x1b[2Jhello'), compressed: false, cols: 120, rows: 40 } },
  { dir: 's2c', counter: 8, frame: { kind: 2, streamId, seq: 43, bytes: Uint8Array.of(0x78, 0x9c, 1, 2, 3), compressed: true } },
  { dir: 'c2s', counter: 1, frame: { kind: 4, streamId, seq: 43, bytes: new Uint8Array(), compressed: false } },
].map(({ dir, counter, frame }) => ({
  dir,
  counter,
  kind: frame.kind,
  streamId: frame.streamId,
  seq: frame.seq,
  compressed: frame.compressed,
  cols: frame.cols ?? null,
  rows: frame.rows ?? null,
  bytes: hex(frame.bytes),
  sealed: hex(TB.sealTerminalBinary(dir === 'c2s' ? terminalC2s : terminalS2c, counter, frame)),
  local: hex(TB.encodeTerminalLocal(frame)),
}))

// ── CPace over a 6-char code (the vector core.test.ts pins) ──────────────────────────────────────
const codeSid = C.newPairId(seeded(42))
const codeCi = C.pairContext(machineId)
const codeG = C.cpaceGenerator('K7P4X9', codeSid, codeCi)
const codeA = C.cpaceStart(codeG, seeded(1))
const codeB = C.cpaceStart(codeG, seeded(2))
const codeK = C.cpaceShared(codeB.Y, codeA.y)

// ── password link (`harness link connect`), joiner side = this app ───────────────────────────────
const password = 'correct horse ⅰ battery' // U+2170 SMALL ROMAN NUMERAL ONE — NFKC folds it to 'i'
const stretched = await PW.stretchPassword(password, machineId)
const pwSid = seeded(42)(16)
const pwCi = PW.pwContext(machineId)
const pwG = PW.pwCpaceGenerator(stretched, pwSid, pwCi)
const pwA = C.cpaceStart(pwG, seeded(1)) // the target machine
const pwB = C.cpaceStart(pwG, seeded(2)) // this app
const pwK = C.cpaceShared(pwA.Y, pwB.y)
const pwIsk = C.cpaceISK(pwSid, pwK, pwA.Y, pwB.Y)
const pwTh = C.transcriptHash(pwSid, pwCi, pwA.Y, pwB.Y)
const pwKc = C.kcKeys(pwIsk, pwCi)
const pwPairKey = C.pairKey(pwIsk, pwCi)
const idEnvelope = (id: { priv: Uint8Array; pub: Uint8Array }) =>
  C.utf8(JSON.stringify({ id: C.b64e(id.pub), sig: C.b64e(C.pairBindSig(id.priv, pwTh)) }))

const vectors = {
  meta: {
    note: 'Generated by scripts/e2ee_vectors/gen.mts from the harness CLI — do not edit by hand.',
    cliCommit: git('rev-parse', 'HEAD'),
    cliDirty: git('status', '--porcelain', '--', ...Object.values(sources)) !== '',
    sha256: Object.fromEntries(Object.entries(sources).map(([name, path]) => [name, sha256File(path)])),
  },
  machineId,
  encryptedDownTypes: [...C.ENCRYPTED_DOWN_TYPES].sort(),
  lvCat: hex(C.lvCat('ab', Uint8Array.of(1, 2, 3))),
  counterNonce: { counter: 2 ** 40 + 5, nonce: hex(C.counterNonce(2 ** 40 + 5)) },
  identities: {
    adapter: { seed: hex(adapterId.priv), pub: hex(adapterId.pub), fingerprint: C.fingerprint(adapterId.pub) },
    client: { seed: hex(clientId.priv), pub: hex(clientId.pub), fingerprint: C.fingerprint(clientId.pub) },
  },
  session: {
    clientEph: { priv: hex(clientEph.priv), pub: hex(clientEph.pub) },
    adapterEph: { priv: hex(adapterEph.priv), pub: hex(adapterEph.pub) },
    c2s: hex(keys.c2s),
    s2c: hex(keys.s2c),
    terminalC2s: hex(terminalC2s),
    terminalS2c: hex(terminalS2c),
    hello: {
      identityPub: C.b64e(clientId.pub),
      ephPub: C.b64e(clientEph.pub),
      sig: C.b64e(C.helloSig(clientId.priv, machineId, clientEph.pub)),
    },
    welcome: {
      webEphPub: C.b64e(clientEph.pub),
      ephPub: C.b64e(adapterEph.pub),
      sig: C.b64e(C.welcomeSig(adapterId.priv, machineId, clientEph.pub, adapterEph.pub)),
      enc: C.b64e(C.aeadSeal(keys.s2c, 0, C.utf8('e2e-welcome'), C.utf8(JSON.stringify(welcomeInitial)))),
    },
    welcomeInitial,
    rekey: { n: 2, enc: C.b64e(C.aeadSeal(keys.s2c, 2, C.utf8('e2e-rekey'), C.utf8(JSON.stringify(rekeyed)))) },
    rekeyed,
  },
  envelopes: {
    down: {
      type: 'terminal_open',
      payload: { agentId: 'agent-1', cols: 80, rows: 24, requestId: 'req-1' },
      wrapped: C.wrapPayload(keys.c2s, 'p', 0, 'terminal_open', undefined, { agentId: 'agent-1', cols: 80, rows: 24, requestId: 'req-1' }),
    },
    upPairwise: {
      type: 'agents_list_result',
      payload: { requestId: 'req-2', agents: [{ id: 'agent-1', name: 'Ví dụ ✓' }] },
      wrapped: C.wrapPayload(keys.s2c, 'p', 1, 'agents_list_result', undefined, { requestId: 'req-2', agents: [{ id: 'agent-1', name: 'Ví dụ ✓' }] }),
    },
    upGroup: {
      type: 'text_delta',
      dbSessionId: 'sess-1',
      payload: { content: 'hi' },
      wrapped: C.wrapPayload(groupKey, 'g', 5, 'text_delta', 'sess-1', { content: 'hi' }, 'ab12cd34'),
    },
    upGroupAfterRekey: {
      type: 'turn_started',
      payload: { agentId: 'agent-1' },
      wrapped: C.wrapPayload(nextGroupKey, 'g', 0, 'turn_started', undefined, { agentId: 'agent-1' }, 'cd34ef56'),
    },
  },
  terminalFrames,
  cpaceCode: {
    code: 'K7P4X9',
    sid: hex(codeSid),
    ci: codeCi,
    generator: hex(codeG.toRawBytes()),
    ya: hex(codeA.Y),
    yb: hex(codeB.Y),
    yScalarA: codeA.y.toString(16),
    shared: hex(codeK),
    isk: hex(C.cpaceISK(codeSid, codeK, codeA.Y, codeB.Y)),
  },
  passwordLink: {
    password,
    passwordNfkc: password.normalize('NFKC'),
    stretched: hex(stretched),
    sid: hex(pwSid),
    ci: pwCi,
    generator: hex(pwG.toRawBytes()),
    ya: hex(pwA.Y),
    yb: hex(pwB.Y),
    shared: hex(pwK),
    isk: hex(pwIsk),
    transcript: hex(pwTh),
    round2Mac: hex(C.macTag(pwKc.web, pwTh)),
    round3Mac: hex(C.macTag(pwKc.adapter, pwTh)),
    round3Enc: C.b64e(C.aeadSeal(pwPairKey, 3, C.utf8('e2e-id'), idEnvelope(adapterId))),
    round4Enc: C.b64e(C.aeadSeal(pwPairKey, 4, C.utf8('e2e-id'), idEnvelope(clientId))),
  },
}

const out = join(repoRoot, 'test', 'fixtures', 'e2ee_vectors.json')
writeFileSync(out, JSON.stringify(vectors, null, 2) + '\n')
console.log(`wrote ${out}`)
console.log(`core.ts sha256 ${vectors.meta.sha256.core}${vectors.meta.cliDirty ? ' (CLI tree DIRTY)' : ''}`)
