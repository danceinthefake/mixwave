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

export { Tone }
