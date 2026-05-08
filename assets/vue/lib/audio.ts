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

export function playDrum(name: DrumName) {
  getDrums()
  const now = Tone.now()
  switch (name) {
    case "kick":
      kick!.triggerAttackRelease("C1", "8n", now)
      break
    case "snare":
      snare!.triggerAttackRelease("4n", now)
      break
    case "hihat":
      hihat!.triggerAttackRelease("C5", "32n", now)
      break
    case "open_hat":
      openHat!.triggerAttackRelease("C5", "16n", now)
      break
    case "crash":
      crash!.triggerAttackRelease("C5", "1n", now)
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
// PluckSynth (Karplus-Strong) — plucky string-flavored timbre. Wrap
// it in a PolySynth so a chord plays multiple strings at once.

let pluck: Tone.PolySynth | null = null

function getPluck(): Tone.PolySynth {
  if (!pluck) {
    pluck = new Tone.PolySynth(Tone.PluckSynth, {
      attackNoise: 0.5,
      dampening: 4000,
      resonance: 0.7,
    }).toDestination()
    pluck.volume.value = -8
  }
  return pluck
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

export function playChord(name: ChordName, duration: string = "2n") {
  const notes = CHORDS[name]
  if (notes) getPluck().triggerAttackRelease(notes as unknown as string[], duration, Tone.now())
}

export { Tone }
