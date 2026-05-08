import * as Tone from "tone"

// ── Audio context lifecycle ────────────────────────────────────────
// Tone's audio context is created suspended; browsers require a
// user gesture to resume it.

let started = false

export async function ensureStarted(): Promise<void> {
  if (started) return
  await Tone.start()
  started = true
}

// Master output volume. Sets `Tone.Destination`'s volume in dB —
// every synth in the registry routes through it, so this is a
// single point of control for both local hits and incoming remote
// notes.
//
//   linearGain: 0..1   (0 = silent, 1 = full)
export function setMasterVolume(linearGain: number) {
  const clamped = Math.max(0, Math.min(1, linearGain))
  Tone.getDestination().volume.value = clamped === 0 ? -Infinity : Tone.gainToDb(clamped)
}

// ── Engine registry ────────────────────────────────────────────────
// Each (instrument, style) pair gets its own engine. Engines own
// their Tone synths internally — lazy-init on first play so we
// don't allocate audio nodes for flavors no one picks.
//
// Pads call:    play("drums", "synth", "kick")
// Receive side: play(payload.instrument, payload.style, payload.note)

export interface InstrumentEngine {
  /**
   * `octaveOffset` is in octaves, relative to the engine's default
   * voicing. Drums and instruments that already encode the octave
   * in `note` (keyboard, bass) ignore it; chord-based instruments
   * (guitar, pad) use it to transpose all notes in the chord.
   */
  play(note: string, octaveOffset?: number): void
  stopAll(): void
  /**
   * Optional. Called when a user *selects* this flavor (not every
   * play). Sampled engines override this to start downloading their
   * samples ahead of the first hit so there's no awkward silence.
   */
  preload?(): void
}

const engines = new Map<string, InstrumentEngine>()

function register(instrument: string, style: string, engine: InstrumentEngine) {
  engines.set(`${instrument}:${style}`, engine)
}

function getEngine(instrument: string, style: string): InstrumentEngine | undefined {
  return engines.get(`${instrument}:${style}`)
}

export function play(
  instrument: string,
  style: string,
  note: string,
  octaveOffset: number = 0,
) {
  getEngine(instrument, style)?.play(note, octaveOffset)
}

export function stopAll(instrument: string, style: string) {
  getEngine(instrument, style)?.stopAll()
}

export function preload(instrument: string, style: string) {
  getEngine(instrument, style)?.preload?.()
}

// Helper for chord-based engines — shifts every note in a list by
// `octaveOffset` octaves. Tone.Frequency does the math in semitones.
function transposeNotes(notes: readonly string[], octaveOffset: number): string[] {
  if (octaveOffset === 0) return notes as string[]
  const semitones = octaveOffset * 12
  return notes.map((n) => Tone.Frequency(n).transpose(semitones).toNote())
}

// ── Drums : Synth ──────────────────────────────────────────────────
// Existing kit: MembraneSynth (kick), NoiseSynth (snare), MetalSynth
// (hi-hat / open hat / crash). Per-voice schedule tracking keeps
// rapid retriggers from tripping Tone's "strictly greater" assertion.

export type DrumName =
  | "kick"
  | "snare"
  | "hihat"
  | "open_hat"
  | "hihat_pedal"
  | "crash"
  | "ride"
  | "tom_high"
  | "tom_mid"
  | "tom_floor"

// Shared "overhead room" reverb for the crash cymbals across all
// three drum styles. Plain MetalSynth on its own sounds like a tight
// bell-hit at the centre of the cymbal — the user gets the "ping"
// but not the spreading wash you hear when a real cymbal is struck
// on the edge. Adding a parallel reverb send on the crash signal
// gives that wide bloom without smearing the dry attack. Lazy-init
// + singleton so we don't allocate a reverb per style.
let cymbalReverb: Tone.Freeverb | null = null
function getCymbalReverb(): Tone.Freeverb {
  if (cymbalReverb) return cymbalReverb
  cymbalReverb = new Tone.Freeverb({
    roomSize: 0.85,
    dampening: 3000,
  }).toDestination()
  cymbalReverb.wet.value = 0.5
  return cymbalReverb
}

function makeDrumSynth(): InstrumentEngine {
  let kick: Tone.MembraneSynth | null = null
  let snare: Tone.NoiseSynth | null = null
  let hihat: Tone.MetalSynth | null = null
  let openHat: Tone.MetalSynth | null = null
  let hihatPedal: Tone.MetalSynth | null = null
  let crash: Tone.MetalSynth | null = null
  let ride: Tone.MetalSynth | null = null
  let tomHigh: Tone.MembraneSynth | null = null
  let tomMid: Tone.MembraneSynth | null = null
  let tomFloor: Tone.MembraneSynth | null = null

  const lastScheduled: Record<DrumName, number> = {
    kick: 0,
    snare: 0,
    hihat: 0,
    open_hat: 0,
    hihat_pedal: 0,
    crash: 0,
    ride: 0,
    tom_high: 0,
    tom_mid: 0,
    tom_floor: 0,
  }

  function ensure() {
    if (kick) return
    kick = new Tone.MembraneSynth({
      pitchDecay: 0.05,
      octaves: 10,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.4, sustain: 0.01, release: 1.4 },
    }).toDestination()

    snare = new Tone.NoiseSynth({
      noise: { type: "white" },
      envelope: { attack: 0.001, decay: 0.13, sustain: 0 },
    }).toDestination()

    hihat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.1, release: 0.01 },
      harmonicity: 5.1,
      modulationIndex: 32,
      resonance: 4000,
      octaves: 1.5,
    }).toDestination()
    hihat.volume.value = -6

    openHat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.5, release: 0.4 },
      harmonicity: 5.1,
      modulationIndex: 32,
      resonance: 4000,
      octaves: 1.5,
    }).toDestination()
    openHat.volume.value = -6

    // Foot-chick: cymbals snapping closed against each other. Even
    // tighter envelope than the closed-stick hihat, less harmonic
    // content, and noticeably quieter — the foot-only chick is a
    // grace note in real drumming, not a primary voice.
    hihatPedal = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.05, release: 0.01 },
      harmonicity: 4.0,
      modulationIndex: 18,
      resonance: 3000,
      octaves: 1.0,
    }).toDestination()
    hihatPedal.volume.value = -14

    crash = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 1.5, release: 1.5 },
      harmonicity: 8.0,
      modulationIndex: 60,
      resonance: 8000,
      octaves: 0.5,
    }).toDestination()
    crash.volume.value = -12
    crash.connect(getCymbalReverb())

    // Ride — brighter ping than crash, less inharmonic, shorter
    // wash. Skips the reverb send so rhythmic ride patterns stay
    // tight.
    ride = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.8, release: 0.6 },
      harmonicity: 9.0,
      modulationIndex: 35,
      resonance: 6000,
      octaves: 0.7,
    }).toDestination()
    ride.volume.value = -10

    // Toms — MembraneSynth tuned high/mid/low so the three drums
    // have distinct pitches and read as separate kit pieces.
    tomHigh = new Tone.MembraneSynth({
      pitchDecay: 0.04,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.4, sustain: 0, release: 0.5 },
    }).toDestination()

    tomMid = new Tone.MembraneSynth({
      pitchDecay: 0.04,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.5, sustain: 0, release: 0.6 },
    }).toDestination()

    tomFloor = new Tone.MembraneSynth({
      pitchDecay: 0.05,
      octaves: 5,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.7, sustain: 0, release: 0.8 },
    }).toDestination()
  }

  function schedule(name: DrumName): number {
    const candidate = Tone.now()
    const when = Math.max(candidate, lastScheduled[name] + 0.001)
    lastScheduled[name] = when
    return when
  }

  return {
    play(note, _octaveOffset) {
      const drum = note as DrumName
      ensure()
      const when = schedule(drum)
      switch (drum) {
        case "kick":
          kick!.triggerAttackRelease("C1", "8n", when)
          break
        case "snare":
          snare!.triggerAttackRelease("4n", when)
          break
        case "hihat":
          hihat!.triggerAttackRelease("C5", "32n", when)
          break
        case "open_hat":
          openHat!.triggerAttackRelease("C5", "16n", when)
          break
        case "hihat_pedal":
          hihatPedal!.triggerAttackRelease("C5", "64n", when)
          break
        case "crash":
          crash!.triggerAttackRelease("C5", "1n", when)
          break
        case "ride":
          ride!.triggerAttackRelease("C6", "4n", when)
          break
        case "tom_high":
          tomHigh!.triggerAttackRelease("A3", "8n", when)
          break
        case "tom_mid":
          tomMid!.triggerAttackRelease("E3", "8n", when)
          break
        case "tom_floor":
          tomFloor!.triggerAttackRelease("A2", "8n", when)
          break
      }
    },
    // Drums are short percussion — no held notes to release.
    stopAll() {},
  }
}

register("drums", "synth", makeDrumSynth())

// ── Drums : 808 ────────────────────────────────────────────────────
// Classic Roland TR-808 vibe: long sub-y kick, snappy snare with a
// tonal body, brighter and tighter hats, ringy crash.

function makeDrum808(): InstrumentEngine {
  let kick: Tone.MembraneSynth | null = null
  let snareNoise: Tone.NoiseSynth | null = null
  let snareBody: Tone.Synth | null = null
  let hihat: Tone.MetalSynth | null = null
  let openHat: Tone.MetalSynth | null = null
  let hihatPedal: Tone.MetalSynth | null = null
  let crash: Tone.MetalSynth | null = null
  let ride: Tone.MetalSynth | null = null
  let tomHigh: Tone.MembraneSynth | null = null
  let tomMid: Tone.MembraneSynth | null = null
  let tomFloor: Tone.MembraneSynth | null = null

  const lastScheduled: Record<DrumName, number> = {
    kick: 0,
    snare: 0,
    hihat: 0,
    open_hat: 0,
    hihat_pedal: 0,
    crash: 0,
    ride: 0,
    tom_high: 0,
    tom_mid: 0,
    tom_floor: 0,
  }

  function ensure() {
    if (kick) return
    kick = new Tone.MembraneSynth({
      pitchDecay: 0.08,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 1.2, sustain: 0, release: 1.2 },
    }).toDestination()

    snareNoise = new Tone.NoiseSynth({
      noise: { type: "white" },
      envelope: { attack: 0.001, decay: 0.18, sustain: 0 },
    }).toDestination()
    snareNoise.volume.value = -2

    snareBody = new Tone.Synth({
      oscillator: { type: "triangle" },
      envelope: { attack: 0.001, decay: 0.08, sustain: 0, release: 0.05 },
    }).toDestination()
    snareBody.volume.value = -10

    hihat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.05, release: 0.01 },
      harmonicity: 12,
      modulationIndex: 50,
      resonance: 8000,
      octaves: 1.0,
    }).toDestination()
    hihat.volume.value = -8

    openHat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.4, release: 0.3 },
      harmonicity: 12,
      modulationIndex: 50,
      resonance: 8000,
      octaves: 1.0,
    }).toDestination()
    openHat.volume.value = -8

    hihatPedal = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.04, release: 0.01 },
      harmonicity: 8,
      modulationIndex: 30,
      resonance: 6000,
      octaves: 0.8,
    }).toDestination()
    hihatPedal.volume.value = -16

    crash = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 2.5, release: 2.5 },
      harmonicity: 10,
      modulationIndex: 60,
      resonance: 4000,
      octaves: 0.8,
    }).toDestination()
    crash.volume.value = -14
    crash.connect(getCymbalReverb())

    ride = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 1.0, release: 0.8 },
      harmonicity: 11,
      modulationIndex: 40,
      resonance: 5000,
      octaves: 0.8,
    }).toDestination()
    ride.volume.value = -12

    // 808-style toms: longer pitch envelope and decay than synth,
    // so they boom rather than thud.
    tomHigh = new Tone.MembraneSynth({
      pitchDecay: 0.06,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.7, sustain: 0, release: 0.7 },
    }).toDestination()

    tomMid = new Tone.MembraneSynth({
      pitchDecay: 0.07,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.9, sustain: 0, release: 0.9 },
    }).toDestination()

    tomFloor = new Tone.MembraneSynth({
      pitchDecay: 0.08,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 1.2, sustain: 0, release: 1.2 },
    }).toDestination()
  }

  function schedule(name: DrumName): number {
    const candidate = Tone.now()
    const when = Math.max(candidate, lastScheduled[name] + 0.001)
    lastScheduled[name] = when
    return when
  }

  return {
    play(note, _octaveOffset) {
      const drum = note as DrumName
      ensure()
      const when = schedule(drum)
      switch (drum) {
        case "kick":
          kick!.triggerAttackRelease("A0", "2n", when)
          break
        case "snare":
          snareNoise!.triggerAttackRelease("8n", when)
          snareBody!.triggerAttackRelease("E4", "16n", when)
          break
        case "hihat":
          hihat!.triggerAttackRelease("C7", "32n", when)
          break
        case "open_hat":
          openHat!.triggerAttackRelease("C7", "8n", when)
          break
        case "hihat_pedal":
          hihatPedal!.triggerAttackRelease("C7", "64n", when)
          break
        case "crash":
          crash!.triggerAttackRelease("C5", "1n", when)
          break
        case "ride":
          ride!.triggerAttackRelease("C6", "4n", when)
          break
        case "tom_high":
          tomHigh!.triggerAttackRelease("A3", "8n", when)
          break
        case "tom_mid":
          tomMid!.triggerAttackRelease("E3", "8n", when)
          break
        case "tom_floor":
          tomFloor!.triggerAttackRelease("A2", "8n", when)
          break
      }
    },
    stopAll() {},
  }
}

register("drums", "808", makeDrum808())

// ── Drums : Acoustic ───────────────────────────────────────────────
// Warmer kit — pink-noise snare with a tom-like body, less metallic
// cymbals. Approximates an acoustic kit through synthesis (no
// samples shipped).

function makeDrumAcoustic(): InstrumentEngine {
  let kick: Tone.MembraneSynth | null = null
  let snareNoise: Tone.NoiseSynth | null = null
  let snareBody: Tone.MembraneSynth | null = null
  let hihat: Tone.MetalSynth | null = null
  let openHat: Tone.MetalSynth | null = null
  let hihatPedal: Tone.MetalSynth | null = null
  let crash: Tone.MetalSynth | null = null
  let ride: Tone.MetalSynth | null = null
  let tomHigh: Tone.MembraneSynth | null = null
  let tomMid: Tone.MembraneSynth | null = null
  let tomFloor: Tone.MembraneSynth | null = null

  const lastScheduled: Record<DrumName, number> = {
    kick: 0,
    snare: 0,
    hihat: 0,
    open_hat: 0,
    hihat_pedal: 0,
    crash: 0,
    ride: 0,
    tom_high: 0,
    tom_mid: 0,
    tom_floor: 0,
  }

  function ensure() {
    if (kick) return
    kick = new Tone.MembraneSynth({
      pitchDecay: 0.03,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.28, sustain: 0, release: 0.5 },
    }).toDestination()

    snareNoise = new Tone.NoiseSynth({
      noise: { type: "pink" },
      envelope: { attack: 0.001, decay: 0.18, sustain: 0 },
    }).toDestination()
    snareNoise.volume.value = -4

    snareBody = new Tone.MembraneSynth({
      pitchDecay: 0.02,
      octaves: 2,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.15, sustain: 0, release: 0.2 },
    }).toDestination()
    snareBody.volume.value = -10

    hihat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.08, release: 0.01 },
      harmonicity: 4.0,
      modulationIndex: 28,
      resonance: 5000,
      octaves: 1.5,
    }).toDestination()
    hihat.volume.value = -8

    openHat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.6, release: 0.5 },
      harmonicity: 4.0,
      modulationIndex: 28,
      resonance: 5000,
      octaves: 1.5,
    }).toDestination()
    openHat.volume.value = -8

    hihatPedal = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.06, release: 0.01 },
      harmonicity: 3.5,
      modulationIndex: 20,
      resonance: 4000,
      octaves: 1.2,
    }).toDestination()
    hihatPedal.volume.value = -16

    crash = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 1.8, release: 1.5 },
      harmonicity: 6.0,
      modulationIndex: 50,
      resonance: 7000,
      octaves: 0.5,
    }).toDestination()
    crash.volume.value = -14
    crash.connect(getCymbalReverb())

    ride = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.9, release: 0.7 },
      harmonicity: 7.0,
      modulationIndex: 32,
      resonance: 5500,
      octaves: 0.6,
    }).toDestination()
    ride.volume.value = -10

    // Acoustic toms: shorter and tighter than 808 but with enough
    // body to read as drum hits rather than blips.
    tomHigh = new Tone.MembraneSynth({
      pitchDecay: 0.03,
      octaves: 3,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.3, sustain: 0, release: 0.4 },
    }).toDestination()

    tomMid = new Tone.MembraneSynth({
      pitchDecay: 0.04,
      octaves: 3,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.4, sustain: 0, release: 0.5 },
    }).toDestination()

    tomFloor = new Tone.MembraneSynth({
      pitchDecay: 0.05,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.6, sustain: 0, release: 0.7 },
    }).toDestination()
  }

  function schedule(name: DrumName): number {
    const candidate = Tone.now()
    const when = Math.max(candidate, lastScheduled[name] + 0.001)
    lastScheduled[name] = when
    return when
  }

  return {
    play(note, _octaveOffset) {
      const drum = note as DrumName
      ensure()
      const when = schedule(drum)
      switch (drum) {
        case "kick":
          kick!.triggerAttackRelease("C2", "8n", when)
          break
        case "snare":
          snareNoise!.triggerAttackRelease("16n", when)
          snareBody!.triggerAttackRelease("D3", "16n", when)
          break
        case "hihat":
          hihat!.triggerAttackRelease("C5", "32n", when)
          break
        case "open_hat":
          openHat!.triggerAttackRelease("C5", "8n", when)
          break
        case "hihat_pedal":
          hihatPedal!.triggerAttackRelease("C5", "64n", when)
          break
        case "crash":
          crash!.triggerAttackRelease("C5", "2n", when)
          break
        case "ride":
          ride!.triggerAttackRelease("C6", "4n", when)
          break
        case "tom_high":
          tomHigh!.triggerAttackRelease("A3", "8n", when)
          break
        case "tom_mid":
          tomMid!.triggerAttackRelease("E3", "8n", when)
          break
        case "tom_floor":
          tomFloor!.triggerAttackRelease("A2", "8n", when)
          break
      }
    },
    stopAll() {},
  }
}

register("drums", "acoustic", makeDrumAcoustic())

// ── Keyboard : Synth ───────────────────────────────────────────────
// PolySynth over Tone.Synth — multiple notes can ring at once.

function makeKeyboardSynth(): InstrumentEngine {
  let poly: Tone.PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new Tone.PolySynth(Tone.Synth, {
      oscillator: { type: "triangle" },
      envelope: { attack: 0.005, decay: 0.1, sustain: 0.3, release: 0.8 },
    }).toDestination()
    poly.volume.value = -10
  }

  return {
    play(note) {
      ensure()
      poly!.triggerAttackRelease(note, "8n", Tone.now())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("keyboard", "synth", makeKeyboardSynth())

// ── Keyboard : Lead ────────────────────────────────────────────────
// Sawtooth + sweeping lowpass filter envelope, Moog-y solo voice.

function makeKeyboardLead(): InstrumentEngine {
  let poly: Tone.PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new Tone.PolySynth(Tone.MonoSynth, {
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.01, decay: 0.4, sustain: 0.4, release: 0.5 },
      filter: { type: "lowpass", frequency: 1500, Q: 6 },
      filterEnvelope: {
        attack: 0.04,
        decay: 0.4,
        sustain: 0.3,
        release: 0.5,
        baseFrequency: 300,
        octaves: 3,
      },
    }).toDestination()
    poly.volume.value = -12
  }

  return {
    play(note) {
      ensure()
      poly!.triggerAttackRelease(note, "8n", Tone.now())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("keyboard", "lead", makeKeyboardLead())

// ── Keyboard : Piano (Salamander Grand Piano, sampled) ────────────
// Real grand-piano samples — Salamander Grand Piano is a free
// open-source recording of a Yamaha C5 concert grand, streamed from
// the Tone.js community CDN. Three anchor samples (A3 / A4 / A5)
// cover the keyboard's full visible range — Sampler pitch-shifts
// between them. ~150 KB total download, only fetched when the user
// actually picks Piano (preload() hook).

function makeKeyboardPiano(): InstrumentEngine {
  let sampler: Tone.Sampler | null = null

  function ensure() {
    if (sampler) return
    sampler = new Tone.Sampler({
      urls: {
        A3: "A3.mp3",
        A4: "A4.mp3",
        A5: "A5.mp3",
      },
      release: 1,
      baseUrl: "https://tonejs.github.io/audio/salamander/",
    }).toDestination()
    sampler.volume.value = -6
  }

  return {
    play(note) {
      ensure()
      // Tone.Sampler triggers are silent until samples finish loading.
      // After the user picks Piano, preload() fires the fetch; by the
      // time they hit a key, samples are usually ready.
      sampler!.triggerAttackRelease(note, "2n", Tone.now())
    },
    stopAll() {
      sampler?.releaseAll()
    },
    preload() {
      ensure()
    },
  }
}

register("keyboard", "piano", makeKeyboardPiano())

// ── Guitar : Synth ─────────────────────────────────────────────────
// PolySynth(MonoSynth) with a sweeping filter envelope. We'd love to
// use Tone.PluckSynth (real Karplus-Strong), but it's implemented on
// AudioWorkletNode which the browser only allows in secure contexts
// (HTTPS / localhost) — broken on LAN dev.

export type ChordName =
  | "C"
  | "D"
  | "E"
  | "F"
  | "G"
  | "A"
  | "Am"
  | "Dm"
  | "Em"
  | "B7"
  | "A7"
  | "D7"

export const CHORDS: Record<ChordName, string[]> = {
  C: ["C3", "E3", "G3", "C4", "E4"],
  D: ["D3", "A3", "D4", "F#4"],
  E: ["E2", "B2", "E3", "G#3", "B3", "E4"],
  F: ["F2", "C3", "F3", "A3", "C4", "F4"],
  G: ["G2", "B2", "D3", "G3", "B3", "G4"],
  A: ["A2", "E3", "A3", "C#4", "E4"],
  Am: ["A2", "E3", "A3", "C4", "E4"],
  Dm: ["D3", "A3", "D4", "F4"],
  Em: ["E2", "B2", "E3", "G3", "B3", "E4"],
  B7: ["B2", "D#3", "A3", "B3", "D#4", "F#4"],
  A7: ["A2", "E3", "G3", "C#4", "E4"],
  D7: ["D3", "A3", "C4", "F#4"],
}

function makeGuitarSynth(): InstrumentEngine {
  let poly: Tone.PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new Tone.PolySynth(Tone.MonoSynth, {
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.002, decay: 0.3, sustain: 0, release: 1.8 },
      filter: { type: "lowpass", frequency: 3000, Q: 2 },
      filterEnvelope: {
        attack: 0.001,
        decay: 0.4,
        sustain: 0,
        release: 1.8,
        baseFrequency: 200,
        octaves: 3,
      },
    }).toDestination()
    poly.volume.value = -8
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const now = Tone.now()
      const shifted = transposeNotes(notes, octaveOffset)
      // Strum: stagger ~12 ms per string.
      shifted.forEach((note, i) => {
        poly!.triggerAttackRelease(note, "2n", now + i * 0.012)
      })
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("guitar", "synth", makeGuitarSynth())

// ── Guitar : Pluck (hand-rolled Karplus-Strong) ────────────────────
// What Tone.PluckSynth does, but without the AudioWorklet — so it
// works in non-secure contexts (LAN dev). The Karplus-Strong
// algorithm models a vibrating string as a delay line + lowpass
// filter + feedback loop. The "pluck" is a short white-noise burst
// fed into the delay; the loop sustains and gradually decays as the
// filter and feedback gain remove energy each round-trip.
//
//   noise burst ─→ delay (delayTime = 1/freq) ─→ filter (lowpass)
//                       ↑                              │
//                       └──── feedback gain (0.995) ───┘
//                                              │
//                                              ↓
//                                          output
//
// One graph per plucked note, disposed after natural decay.

function makeGuitarPluck(): InstrumentEngine {
  let output: Tone.Gain | null = null
  let activeStrings: { dispose: () => void }[] = []

  function ensure() {
    if (output) return
    // Karplus-Strong is intrinsically louder than the other guitar
    // flavors because the noise burst hits the delay line at full
    // amplitude. 0.3 brings it roughly in line with synth + acoustic.
    output = new Tone.Gain(0.3).toDestination()
  }

  function pluckNote(note: string, when: number) {
    ensure()
    const freq = Tone.Frequency(note).toFrequency()
    const delayTime = 1 / freq

    const delay = new Tone.Delay(delayTime, 0.05)
    const filter = new Tone.Filter(4000, "lowpass")
    const feedback = new Tone.Gain(0.995)

    delay.connect(filter)
    filter.connect(feedback)
    feedback.connect(delay)
    filter.connect(output!)

    // Pluck = 5 ms of white noise into the delay line.
    const noise = new Tone.Noise("white")
    const env = new Tone.AmplitudeEnvelope({
      attack: 0.001,
      decay: 0.005,
      sustain: 0,
      release: 0.001,
    })
    noise.connect(env)
    env.connect(delay)
    noise.start(when)
    env.triggerAttackRelease(0.005, when)
    noise.stop(when + 0.05)

    const nodes = [noise, env, delay, filter, feedback]
    const string = {
      dispose() {
        for (const n of nodes) {
          try {
            n.dispose()
          } catch {
            // already disposed; ignore
          }
        }
      },
    }
    activeStrings.push(string)

    // Auto-dispose after the string has decayed naturally (~6s with
    // the 0.995 feedback). Otherwise we'd accumulate audio nodes per
    // strum forever.
    setTimeout(() => {
      string.dispose()
      activeStrings = activeStrings.filter((s) => s !== string)
    }, 6000)
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const now = Tone.now()
      const shifted = transposeNotes(notes, octaveOffset)
      shifted.forEach((note, i) => {
        pluckNote(note, now + i * 0.012)
      })
    },
    stopAll() {
      // Cut every currently-ringing string.
      const strings = activeStrings.slice()
      activeStrings = []
      for (const s of strings) s.dispose()
    },
  }
}

register("guitar", "pluck", makeGuitarPluck())

// ── Guitar : Acoustic (sampled) ────────────────────────────────────
// Real acoustic-guitar samples streamed from the tonejs-instruments
// CDN. Three anchor samples (A2 / A3 / A4) cover our chord range
// from E2 up through G4; Sampler pitch-shifts between them.

function makeGuitarAcoustic(): InstrumentEngine {
  let sampler: Tone.Sampler | null = null

  function ensure() {
    if (sampler) return
    sampler = new Tone.Sampler({
      urls: {
        A2: "A2.mp3",
        A3: "A3.mp3",
        A4: "A4.mp3",
      },
      release: 0.5,
      baseUrl:
        "https://nbrosowsky.github.io/tonejs-instruments/samples/guitar-acoustic/",
    }).toDestination()
    sampler.volume.value = -4
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const now = Tone.now()
      const shifted = transposeNotes(notes, octaveOffset)
      shifted.forEach((note, i) => {
        sampler!.triggerAttackRelease(note, "2n", now + i * 0.012)
      })
    },
    stopAll() {
      sampler?.releaseAll()
    },
    preload() {
      ensure()
    },
  }
}

register("guitar", "acoustic", makeGuitarAcoustic())

// ── Bass : Synth ───────────────────────────────────────────────────
// Punchy MonoSynth bass — sawtooth through a moving lowpass filter.
// Bass is monophonic by tradition (and by physical bass-guitar
// constraint), so we use a single MonoSynth instead of PolySynth.

function makeBassSynth(): InstrumentEngine {
  let synth: Tone.MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new Tone.MonoSynth({
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.005, decay: 0.4, sustain: 0.3, release: 0.4 },
      filter: { type: "lowpass", frequency: 1200, Q: 4 },
      filterEnvelope: {
        attack: 0.005,
        decay: 0.3,
        sustain: 0.2,
        release: 0.4,
        baseFrequency: 100,
        octaves: 3,
      },
    }).toDestination()
    synth.volume.value = -6
  }

  return {
    play(note) {
      ensure()
      synth!.triggerAttackRelease(note, "8n", Tone.now())
    },
    stopAll() {
      synth?.triggerRelease(Tone.now())
    },
  }
}

register("bass", "synth", makeBassSynth())

// ── Bass : Sub ─────────────────────────────────────────────────────
// Pure sine sub-bass. Slow attack, long sustain, deep low-frequency
// emphasis. Sits underneath everything else in the mix.

function makeBassSub(): InstrumentEngine {
  let synth: Tone.MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new Tone.MonoSynth({
      oscillator: { type: "sine" },
      envelope: { attack: 0.04, decay: 0.3, sustain: 0.7, release: 0.8 },
      filter: { type: "lowpass", frequency: 200, Q: 1 },
      filterEnvelope: {
        attack: 0.04,
        decay: 0.3,
        sustain: 0.5,
        release: 0.8,
        baseFrequency: 80,
        octaves: 1,
      },
    }).toDestination()
    synth.volume.value = -3
  }

  return {
    play(note) {
      ensure()
      synth!.triggerAttackRelease(note, "4n", Tone.now())
    },
    stopAll() {
      synth?.triggerRelease(Tone.now())
    },
  }
}

register("bass", "sub", makeBassSub())

// ── Bass : Slap ────────────────────────────────────────────────────
// Funky slap-bass character — square through a bandpass that
// sweeps for the popped attack feel.

function makeBassSlap(): InstrumentEngine {
  let synth: Tone.MonoSynth | null = null

  function ensure() {
    if (synth) return
    synth = new Tone.MonoSynth({
      oscillator: { type: "square" },
      envelope: { attack: 0.001, decay: 0.18, sustain: 0, release: 0.15 },
      filter: { type: "bandpass", frequency: 800, Q: 8 },
      filterEnvelope: {
        attack: 0.001,
        decay: 0.3,
        sustain: 0,
        release: 0.2,
        baseFrequency: 200,
        octaves: 4,
      },
    }).toDestination()
    // Bandpass + short envelope makes Slap quieter than the other
    // bass flavors at matched settings. -2 dB lifts it close to
    // Synth/Sub so users don't need to chase the volume slider when
    // switching styles.
    synth.volume.value = -2
  }

  return {
    play(note) {
      ensure()
      synth!.triggerAttackRelease(note, "16n", Tone.now())
    },
    stopAll() {
      synth?.triggerRelease(Tone.now())
    },
  }
}

register("bass", "slap", makeBassSlap())

// ── Pad : Warm ─────────────────────────────────────────────────────
// Slow-attack analog-style pad. Triangle through a long envelope —
// the chord swells in over half a second and fades out for several
// seconds after release. Sits behind everything else as ambience.

function makePadWarm(): InstrumentEngine {
  let poly: Tone.PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new Tone.PolySynth(Tone.Synth, {
      oscillator: { type: "fattriangle" },
      envelope: { attack: 0.8, decay: 0.5, sustain: 0.6, release: 2.5 },
    }).toDestination()
    poly.volume.value = -14
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const shifted = transposeNotes(notes, octaveOffset)
      poly!.triggerAttackRelease(shifted, "2n", Tone.now())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("pad", "warm", makePadWarm())

// ── Pad : Bell ─────────────────────────────────────────────────────
// FMSynth-driven bell-pad. Bright, harmonic, glassy attack that
// settles into a sustained tone.

function makePadBell(): InstrumentEngine {
  let poly: Tone.PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new Tone.PolySynth(Tone.FMSynth, {
      harmonicity: 3,
      modulationIndex: 10,
      envelope: { attack: 1.0, decay: 0.4, sustain: 0.5, release: 3.0 },
      modulation: { type: "sine" },
      modulationEnvelope: { attack: 0.4, decay: 0, sustain: 1, release: 2.5 },
    }).toDestination()
    poly.volume.value = -14
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const shifted = transposeNotes(notes, octaveOffset)
      poly!.triggerAttackRelease(shifted, "2n", Tone.now())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("pad", "bell", makePadBell())

// ── Pad : Sweep ────────────────────────────────────────────────────
// Sawtooth pad with a wide filter envelope sweep — classic 80s pad
// vibe, low-to-bright over the attack phase.

function makePadSweep(): InstrumentEngine {
  let poly: Tone.PolySynth | null = null

  function ensure() {
    if (poly) return
    poly = new Tone.PolySynth(Tone.MonoSynth, {
      oscillator: { type: "sawtooth" },
      envelope: { attack: 0.6, decay: 0.4, sustain: 0.7, release: 2.5 },
      filter: { type: "lowpass", frequency: 600, Q: 5 },
      filterEnvelope: {
        attack: 1.2,
        decay: 0.6,
        sustain: 0.5,
        release: 2.5,
        baseFrequency: 100,
        octaves: 4,
      },
    }).toDestination()
    poly.volume.value = -14
  }

  return {
    play(chord, octaveOffset = 0) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const shifted = transposeNotes(notes, octaveOffset)
      poly!.triggerAttackRelease(shifted, "2n", Tone.now())
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("pad", "sweep", makePadSweep())

export { Tone }
