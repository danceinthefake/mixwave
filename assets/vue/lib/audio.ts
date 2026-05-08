import * as Tone from "tone"

// Tone's audio context is created suspended; browsers require a
// user gesture to resume it. This helper is idempotent — instruments
// call it from their first user interaction handler.
let started = false

export async function ensureStarted(): Promise<void> {
  if (started) return
  await Tone.start()
  started = true
}

// ── Drums ──────────────────────────────────────────────────────────
// Lazy-initialized so we don't allocate audio nodes for browsers that
// never touch the kit.

let kick: Tone.MembraneSynth | null = null
let snare: Tone.NoiseSynth | null = null
let hihat: Tone.MetalSynth | null = null
let openHat: Tone.MetalSynth | null = null
let crash: Tone.MetalSynth | null = null

function getDrums() {
  if (!kick) {
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
    hihat.volume.value = -16

    openHat = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 0.5, release: 0.4 },
      harmonicity: 5.1,
      modulationIndex: 32,
      resonance: 4000,
      octaves: 1.5,
    }).toDestination()
    openHat.volume.value = -16

    crash = new Tone.MetalSynth({
      envelope: { attack: 0.001, decay: 1.5, release: 1.5 },
      harmonicity: 8.0,
      modulationIndex: 60,
      resonance: 8000,
      octaves: 0.5,
    }).toDestination()
    crash.volume.value = -22
  }
}

export type DrumName = "kick" | "snare" | "hihat" | "open_hat" | "crash"

// Tone.js requires each scheduled time to be *strictly greater* than
// the previous one on the same synth. Two rapid clicks inside the
// same audio render tick can return the same Tone.now() and trip the
// assertion. Track the last-scheduled time per-voice and bump by 1ms
// if we'd otherwise collide.
const drumLastScheduled: Record<DrumName, number> = {
  kick: 0,
  snare: 0,
  hihat: 0,
  open_hat: 0,
  crash: 0,
}

function schedule(name: DrumName): number {
  const candidate = Tone.now()
  const when = Math.max(candidate, drumLastScheduled[name] + 0.001)
  drumLastScheduled[name] = when
  return when
}

export function playDrum(name: DrumName) {
  getDrums()
  const when = schedule(name)
  switch (name) {
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
    case "crash":
      crash!.triggerAttackRelease("C5", "1n", when)
      break
  }
}

// ── Keyboard ───────────────────────────────────────────────────────
// PolySynth over Tone.Synth — multiple notes can ring at once.

let polysynth: Tone.PolySynth | null = null

function getPolysynth(): Tone.PolySynth {
  if (!polysynth) {
    polysynth = new Tone.PolySynth(Tone.Synth, {
      oscillator: { type: "triangle" },
      envelope: { attack: 0.005, decay: 0.1, sustain: 0.3, release: 0.8 },
    }).toDestination()
    polysynth.volume.value = -10
  }
  return polysynth
}

export function playKey(note: string, duration: string = "8n") {
  getPolysynth().triggerAttackRelease(note, duration, Tone.now())
}

// ── Guitar ─────────────────────────────────────────────────────────
// We'd love to use Tone.PluckSynth (real Karplus-Strong), but it's
// implemented with AudioWorkletNode, which the browser only allows
// in secure contexts (HTTPS or localhost). LAN dev testing over
// http://<lan-ip>:4000 is not secure, so PluckSynth refuses to
// instantiate.
//
// Workaround: PolySynth wrapping MonoSynth with a plucky envelope
// (fast attack, zero sustain, medium release) and a sweeping low-
// pass filter envelope to mimic a string's brightness fading. Less
// authentic than Karplus-Strong but works everywhere.

let pluckPoly: Tone.PolySynth | null = null

function getPluckPoly(): Tone.PolySynth {
  if (!pluckPoly) {
    pluckPoly = new Tone.PolySynth(Tone.MonoSynth, {
      oscillator: { type: "sawtooth" },
      envelope: {
        attack: 0.002,
        decay: 0.3,
        sustain: 0,
        release: 1.8,
      },
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
    pluckPoly.volume.value = -8
  }
  return pluckPoly
}

// Eight common chord voicings. Notes are listed low-to-high, roughly
// matching how each chord sits on a real guitar.
export const CHORDS = {
  C: ["C3", "E3", "G3", "C4", "E4"],
  Am: ["A2", "E3", "A3", "C4", "E4"],
  Dm: ["D3", "A3", "D4", "F4"],
  G: ["G2", "B2", "D3", "G3", "B3", "G4"],
  E: ["E2", "B2", "E3", "G#3", "B3", "E4"],
  Em: ["E2", "B2", "E3", "G3", "B3", "E4"],
  F: ["F2", "C3", "F3", "A3", "C4", "F4"],
  B7: ["B2", "D#3", "A3", "B3", "D#4", "F#4"],
} as const

export type ChordName = keyof typeof CHORDS

// Silence all currently-ringing keyboard notes. Called from
// KeyboardPad's onUnmounted so a held key doesn't leak across an
// instrument switch (BRAINSTORM §9).
export function stopAllKeyboard() {
  if (polysynth) polysynth.releaseAll()
}

// Silence all currently-ringing chord voices.
export function stopAllGuitar() {
  if (pluckPoly) pluckPoly.releaseAll()
}

export function playChord(name: ChordName) {
  const notes = CHORDS[name]
  if (!notes) return
  const synth = getPluckPoly()
  const now = Tone.now()
  // Strum: stagger ~12 ms per string so it sounds plucked rather
  // than block-chord. Long release on the envelope (1.8s) gives
  // each string a natural ring-out.
  notes.forEach((note, i) => {
    synth.triggerAttackRelease(note, "2n", now + i * 0.012)
  })
}

export { Tone }
