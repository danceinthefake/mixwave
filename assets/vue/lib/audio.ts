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

export { Tone }
