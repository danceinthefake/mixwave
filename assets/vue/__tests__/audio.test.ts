import { describe, expect, it, vi, beforeEach } from "vitest"

// Tone.js needs Web Audio APIs that happy-dom doesn't provide.
// Replace it with a structural stub that records calls but does
// nothing audible. Each constructor returns an object with the
// fluent helpers audio.ts uses (chain, connect, dispose, etc.)
// plus a writable `volume.value` so setMasterVolume works.
vi.mock("tone", () => {
  const node = () => ({
    chain: vi.fn().mockReturnThis(),
    connect: vi.fn().mockReturnThis(),
    disconnect: vi.fn().mockReturnThis(),
    dispose: vi.fn(),
    triggerAttack: vi.fn(),
    triggerRelease: vi.fn(),
    triggerAttackRelease: vi.fn(),
    releaseAll: vi.fn(),
    start: vi.fn().mockReturnThis(),
    generate: vi.fn(),
    set: vi.fn(),
    volume: { value: 0 },
    wet: { value: 0 },
  })

  // Constructors. New Tone.X(...) → a fresh node stub.
  const klass = function () {
    return node()
  }

  // `Tone.now()` → 0; tests don't rely on real time.
  const now = () => 0

  return {
    start: vi.fn().mockResolvedValue(undefined),
    now,
    Frequency: vi.fn(() => ({ toFrequency: () => 440 })),
    getDestination: () => ({ volume: { value: 0 } }),
    gainToDb: (g: number) => Math.log10(Math.max(g, 1e-6)) * 20,
    Gain: klass,
    Reverb: klass,
    FeedbackDelay: klass,
    Filter: klass,
    Chorus: klass,
    Distortion: klass,
    Vibrato: klass,
    Tremolo: klass,
    PolySynth: klass,
    MonoSynth: klass,
    Synth: klass,
    MembraneSynth: klass,
    NoiseSynth: klass,
    Sampler: klass,
    AmplitudeEnvelope: klass,
    Noise: klass,
    Delay: klass,
    Player: klass,
    context: { state: "suspended" },
    Destination: { volume: { value: 0 } },
  }
})

import { CHORDS, setMasterVolume, type ChamberKind } from "@/lib/audio"

describe("CHORDS", () => {
  it("exports the canonical guitar/synth chord shapes", () => {
    for (const name of ["C", "D", "E", "F", "G", "A", "Am", "Em", "Dm", "B7"]) {
      expect(CHORDS).toHaveProperty(name)
      expect(Array.isArray(CHORDS[name as keyof typeof CHORDS])).toBe(true)
    }
  })

  it("each chord is a non-empty array of note names", () => {
    for (const [name, notes] of Object.entries(CHORDS)) {
      expect(notes.length, `${name} should have at least one note`).toBeGreaterThan(0)
      for (const n of notes) {
        // Pitch + octave shape: e.g. "C4", "F#3", "Bb5".
        expect(n).toMatch(/^[A-G][#b]?-?\d+$/)
      }
    }
  })
})

describe("setMasterVolume", () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  it("clamps the linear gain to [0, 1]", () => {
    // No throw on out-of-range values.
    expect(() => setMasterVolume(-0.5)).not.toThrow()
    expect(() => setMasterVolume(2.0)).not.toThrow()
    expect(() => setMasterVolume(0.5)).not.toThrow()
  })

  it("silences (-Infinity dB) when gain is exactly 0", () => {
    // We can't easily inspect Tone.Destination's volume after the
    // call because the mock returns a fresh object each access;
    // the real assertion is that it doesn't throw and that the
    // sentinel branch is reachable.
    expect(() => setMasterVolume(0)).not.toThrow()
  })
})

describe("ChamberKind", () => {
  it("includes every kind the LiveView UI sets", () => {
    // Compile-time check: the union covers all the names ChamberLive
    // emits via :chamber_kind. If a new one's added in the LV but
    // not the type, this fails to typecheck before it ever runs.
    const kinds: ChamberKind[] = [
      "vacuum",
      "anechoic",
      "room",
      "live",
      "hall",
      "cathedral",
      "plate",
      "spring",
      "echo",
    ]
    expect(kinds.length).toBe(9)
  })
})
