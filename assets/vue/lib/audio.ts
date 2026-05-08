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

// ── Engine registry ────────────────────────────────────────────────
// Each (instrument, style) pair gets its own engine. Engines own
// their Tone synths internally — lazy-init on first play so we
// don't allocate audio nodes for flavors no one picks.
//
// Pads call:    play("drums", "synth", "kick")
// Receive side: play(payload.instrument, payload.style, payload.note)

export interface InstrumentEngine {
  play(note: string): void
  stopAll(): void
}

const engines = new Map<string, InstrumentEngine>()

function register(instrument: string, style: string, engine: InstrumentEngine) {
  engines.set(`${instrument}:${style}`, engine)
}

function getEngine(instrument: string, style: string): InstrumentEngine | undefined {
  return engines.get(`${instrument}:${style}`)
}

export function play(instrument: string, style: string, note: string) {
  getEngine(instrument, style)?.play(note)
}

export function stopAll(instrument: string, style: string) {
  getEngine(instrument, style)?.stopAll()
}

// ── Drums : Synth ──────────────────────────────────────────────────
// Existing kit: MembraneSynth (kick), NoiseSynth (snare), MetalSynth
// (hi-hat / open hat / crash). Per-voice schedule tracking keeps
// rapid retriggers from tripping Tone's "strictly greater" assertion.

export type DrumName = "kick" | "snare" | "hihat" | "open_hat" | "crash"

function makeDrumSynth(): InstrumentEngine {
  let kick: Tone.MembraneSynth | null = null
  let snare: Tone.NoiseSynth | null = null
  let hihat: Tone.MetalSynth | null = null
  let openHat: Tone.MetalSynth | null = null
  let crash: Tone.MetalSynth | null = null

  const lastScheduled: Record<DrumName, number> = {
    kick: 0,
    snare: 0,
    hihat: 0,
    open_hat: 0,
    crash: 0,
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

  function schedule(name: DrumName): number {
    const candidate = Tone.now()
    const when = Math.max(candidate, lastScheduled[name] + 0.001)
    lastScheduled[name] = when
    return when
  }

  return {
    play(note) {
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
        case "crash":
          crash!.triggerAttackRelease("C5", "1n", when)
          break
      }
    },
    // Drums are short percussion — no held notes to release.
    stopAll() {},
  }
}

register("drums", "synth", makeDrumSynth())

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

// ── Guitar : Synth ─────────────────────────────────────────────────
// PolySynth(MonoSynth) with a sweeping filter envelope. We'd love to
// use Tone.PluckSynth (real Karplus-Strong), but it's implemented on
// AudioWorkletNode which the browser only allows in secure contexts
// (HTTPS / localhost) — broken on LAN dev.

export type ChordName = "C" | "Am" | "Dm" | "G" | "E" | "Em" | "F" | "B7"

export const CHORDS: Record<ChordName, string[]> = {
  C: ["C3", "E3", "G3", "C4", "E4"],
  Am: ["A2", "E3", "A3", "C4", "E4"],
  Dm: ["D3", "A3", "D4", "F4"],
  G: ["G2", "B2", "D3", "G3", "B3", "G4"],
  E: ["E2", "B2", "E3", "G#3", "B3", "E4"],
  Em: ["E2", "B2", "E3", "G3", "B3", "E4"],
  F: ["F2", "C3", "F3", "A3", "C4", "F4"],
  B7: ["B2", "D#3", "A3", "B3", "D#4", "F#4"],
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
    play(chord) {
      const notes = CHORDS[chord as ChordName]
      if (!notes) return
      ensure()
      const now = Tone.now()
      // Strum: stagger ~12 ms per string.
      notes.forEach((note, i) => {
        poly!.triggerAttackRelease(note, "2n", now + i * 0.012)
      })
    },
    stopAll() {
      poly?.releaseAll()
    },
  }
}

register("guitar", "synth", makeGuitarSynth())

export { Tone }
