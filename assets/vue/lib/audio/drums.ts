// Drum engines — three style flavors (Synth / 808 / Acoustic), each
// a top-down resynthesis of a full kit (kick / snare / hihats /
// crashes / ride / toms). Side-effect module: importing it from
// DrumPad.vue registers all three engines into the audio.ts registry
// at module load. Lazy-chunked: ships only when DrumPad is mounted.
//
// Sharing across the three styles:
//   * `getCymbalReverb()` — a single Freeverb send for crash cymbals
//     across all flavors. Lazy-init so anechoic chambers never
//     allocate the reverb.
//   * No state shared across flavors otherwise — each `makeDrum*()`
//     keeps its own voices + scheduler.

// Named imports — see audio.ts for the rationale; pulls only the
// Tone modules drums actually need so Vite can tree-shake the rest.
import { Freeverb, MembraneSynth, MetalSynth, NoiseSynth, now as toneNow, Synth } from "tone"
import {
  getChamberBus,
  register,
  registerInternalFx,
  type DrumName,
  type InstrumentEngine,
} from "../audio"

// Shared "overhead room" reverb for the crash cymbals across all
// three drum styles. Plain MetalSynth on its own sounds like a tight
// bell-hit at the centre of the cymbal — the user gets the "ping"
// but not the spreading wash you hear when a real cymbal is struck
// on the edge. Adding a parallel reverb send on the crash signal
// gives that wide bloom without smearing the dry attack. Lazy-init
// + singleton so we don't allocate a reverb per style.
let cymbalReverb: Freeverb | null = null
function getCymbalReverb(): Freeverb {
  if (cymbalReverb) return cymbalReverb
  cymbalReverb = new Freeverb({
    roomSize: 0.85,
    dampening: 3000,
  }).connect(getChamberBus())
  cymbalReverb.wet.value = 0.5
  // Bypassed entirely when chamber is anechoic.
  registerInternalFx(cymbalReverb.wet)
  return cymbalReverb
}

// ── Drums : Synth ──────────────────────────────────────────────────
// Existing kit: MembraneSynth (kick), NoiseSynth (snare), MetalSynth
// (hi-hat / open hat / crash). Per-voice schedule tracking keeps
// rapid retriggers from tripping Tone's "strictly greater" assertion.
function makeDrumSynth(): InstrumentEngine {
  let kick: MembraneSynth | null = null
  let snare: NoiseSynth | null = null
  let hihat: MetalSynth | null = null
  let openHat: MetalSynth | null = null
  let hihatPedal: MetalSynth | null = null
  let crash: MetalSynth | null = null
  let ride: MetalSynth | null = null
  let tomHigh: MembraneSynth | null = null
  let tomMid: MembraneSynth | null = null
  let tomFloor: MembraneSynth | null = null

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
    kick = new MembraneSynth({
      pitchDecay: 0.05,
      octaves: 10,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.4, sustain: 0.01, release: 1.4 },
    }).connect(getChamberBus())

    snare = new NoiseSynth({
      noise: { type: "white" },
      envelope: { attack: 0.001, decay: 0.13, sustain: 0 },
    }).connect(getChamberBus())

    hihat = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.1, release: 0.01 },
      harmonicity: 5.1,
      modulationIndex: 32,
      resonance: 4000,
      octaves: 1.5,
    }).connect(getChamberBus())
    hihat.volume.value = -6

    openHat = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.5, release: 0.4 },
      harmonicity: 5.1,
      modulationIndex: 32,
      resonance: 4000,
      octaves: 1.5,
    }).connect(getChamberBus())
    openHat.volume.value = -6

    // Foot-chick: cymbals snapping closed against each other. Even
    // tighter envelope than the closed-stick hihat, less harmonic
    // content, and noticeably quieter — the foot-only chick is a
    // grace note in real drumming, not a primary voice.
    hihatPedal = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.05, release: 0.01 },
      harmonicity: 4.0,
      modulationIndex: 18,
      resonance: 3000,
      octaves: 1.0,
    }).connect(getChamberBus())
    hihatPedal.volume.value = -14

    crash = new MetalSynth({
      envelope: { attack: 0.001, decay: 1.5, release: 1.5 },
      harmonicity: 8.0,
      modulationIndex: 60,
      resonance: 8000,
      octaves: 0.5,
    }).connect(getChamberBus())
    crash.volume.value = -12
    crash.connect(getCymbalReverb())

    // Ride — brighter ping than crash, less inharmonic, shorter
    // wash. Skips the reverb send so rhythmic ride patterns stay
    // tight.
    ride = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.8, release: 0.6 },
      harmonicity: 9.0,
      modulationIndex: 35,
      resonance: 6000,
      octaves: 0.7,
    }).connect(getChamberBus())
    ride.volume.value = -10

    // Toms — MembraneSynth tuned high/mid/low so the three drums
    // have distinct pitches and read as separate kit pieces.
    tomHigh = new MembraneSynth({
      pitchDecay: 0.04,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.4, sustain: 0, release: 0.5 },
    }).connect(getChamberBus())

    tomMid = new MembraneSynth({
      pitchDecay: 0.04,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.5, sustain: 0, release: 0.6 },
    }).connect(getChamberBus())

    tomFloor = new MembraneSynth({
      pitchDecay: 0.05,
      octaves: 5,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.7, sustain: 0, release: 0.8 },
    }).connect(getChamberBus())
  }

  function schedule(name: DrumName): number {
    const candidate = toneNow()
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
  let kick: MembraneSynth | null = null
  let snareNoise: NoiseSynth | null = null
  let snareBody: Synth | null = null
  let hihat: MetalSynth | null = null
  let openHat: MetalSynth | null = null
  let hihatPedal: MetalSynth | null = null
  let crash: MetalSynth | null = null
  let ride: MetalSynth | null = null
  let tomHigh: MembraneSynth | null = null
  let tomMid: MembraneSynth | null = null
  let tomFloor: MembraneSynth | null = null

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
    kick = new MembraneSynth({
      pitchDecay: 0.08,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 1.2, sustain: 0, release: 1.2 },
    }).connect(getChamberBus())

    snareNoise = new NoiseSynth({
      noise: { type: "white" },
      envelope: { attack: 0.001, decay: 0.18, sustain: 0 },
    }).connect(getChamberBus())
    snareNoise.volume.value = -2

    snareBody = new Synth({
      oscillator: { type: "triangle" },
      envelope: { attack: 0.001, decay: 0.08, sustain: 0, release: 0.05 },
    }).connect(getChamberBus())
    snareBody.volume.value = -10

    hihat = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.05, release: 0.01 },
      harmonicity: 12,
      modulationIndex: 50,
      resonance: 8000,
      octaves: 1.0,
    }).connect(getChamberBus())
    hihat.volume.value = -8

    openHat = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.4, release: 0.3 },
      harmonicity: 12,
      modulationIndex: 50,
      resonance: 8000,
      octaves: 1.0,
    }).connect(getChamberBus())
    openHat.volume.value = -8

    hihatPedal = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.04, release: 0.01 },
      harmonicity: 8,
      modulationIndex: 30,
      resonance: 6000,
      octaves: 0.8,
    }).connect(getChamberBus())
    hihatPedal.volume.value = -16

    crash = new MetalSynth({
      envelope: { attack: 0.001, decay: 2.5, release: 2.5 },
      harmonicity: 10,
      modulationIndex: 60,
      resonance: 4000,
      octaves: 0.8,
    }).connect(getChamberBus())
    crash.volume.value = -14
    crash.connect(getCymbalReverb())

    ride = new MetalSynth({
      envelope: { attack: 0.001, decay: 1.0, release: 0.8 },
      harmonicity: 11,
      modulationIndex: 40,
      resonance: 5000,
      octaves: 0.8,
    }).connect(getChamberBus())
    ride.volume.value = -12

    // 808-style toms: longer pitch envelope and decay than synth,
    // so they boom rather than thud.
    tomHigh = new MembraneSynth({
      pitchDecay: 0.06,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.7, sustain: 0, release: 0.7 },
    }).connect(getChamberBus())

    tomMid = new MembraneSynth({
      pitchDecay: 0.07,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.9, sustain: 0, release: 0.9 },
    }).connect(getChamberBus())

    tomFloor = new MembraneSynth({
      pitchDecay: 0.08,
      octaves: 6,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 1.2, sustain: 0, release: 1.2 },
    }).connect(getChamberBus())
  }

  function schedule(name: DrumName): number {
    const candidate = toneNow()
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
  let kick: MembraneSynth | null = null
  let snareNoise: NoiseSynth | null = null
  let snareBody: MembraneSynth | null = null
  let hihat: MetalSynth | null = null
  let openHat: MetalSynth | null = null
  let hihatPedal: MetalSynth | null = null
  let crash: MetalSynth | null = null
  let ride: MetalSynth | null = null
  let tomHigh: MembraneSynth | null = null
  let tomMid: MembraneSynth | null = null
  let tomFloor: MembraneSynth | null = null

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
    kick = new MembraneSynth({
      pitchDecay: 0.03,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.28, sustain: 0, release: 0.5 },
    }).connect(getChamberBus())

    snareNoise = new NoiseSynth({
      noise: { type: "pink" },
      envelope: { attack: 0.001, decay: 0.18, sustain: 0 },
    }).connect(getChamberBus())
    snareNoise.volume.value = -4

    snareBody = new MembraneSynth({
      pitchDecay: 0.02,
      octaves: 2,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.15, sustain: 0, release: 0.2 },
    }).connect(getChamberBus())
    snareBody.volume.value = -10

    hihat = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.08, release: 0.01 },
      harmonicity: 4.0,
      modulationIndex: 28,
      resonance: 5000,
      octaves: 1.5,
    }).connect(getChamberBus())
    hihat.volume.value = -8

    openHat = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.6, release: 0.5 },
      harmonicity: 4.0,
      modulationIndex: 28,
      resonance: 5000,
      octaves: 1.5,
    }).connect(getChamberBus())
    openHat.volume.value = -8

    hihatPedal = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.06, release: 0.01 },
      harmonicity: 3.5,
      modulationIndex: 20,
      resonance: 4000,
      octaves: 1.2,
    }).connect(getChamberBus())
    hihatPedal.volume.value = -16

    crash = new MetalSynth({
      envelope: { attack: 0.001, decay: 1.8, release: 1.5 },
      harmonicity: 6.0,
      modulationIndex: 50,
      resonance: 7000,
      octaves: 0.5,
    }).connect(getChamberBus())
    crash.volume.value = -14
    crash.connect(getCymbalReverb())

    ride = new MetalSynth({
      envelope: { attack: 0.001, decay: 0.9, release: 0.7 },
      harmonicity: 7.0,
      modulationIndex: 32,
      resonance: 5500,
      octaves: 0.6,
    }).connect(getChamberBus())
    ride.volume.value = -10

    // Acoustic toms: shorter and tighter than 808 but with enough
    // body to read as drum hits rather than blips.
    tomHigh = new MembraneSynth({
      pitchDecay: 0.03,
      octaves: 3,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.3, sustain: 0, release: 0.4 },
    }).connect(getChamberBus())

    tomMid = new MembraneSynth({
      pitchDecay: 0.04,
      octaves: 3,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.4, sustain: 0, release: 0.5 },
    }).connect(getChamberBus())

    tomFloor = new MembraneSynth({
      pitchDecay: 0.05,
      octaves: 4,
      oscillator: { type: "sine" },
      envelope: { attack: 0.001, decay: 0.6, sustain: 0, release: 0.7 },
    }).connect(getChamberBus())
  }

  function schedule(name: DrumName): number {
    const candidate = toneNow()
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
