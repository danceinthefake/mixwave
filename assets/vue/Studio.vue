<script setup lang="ts">
// The single Vue island for the studio. Owns:
//   - cross-instrument audio receiver (remote players' notes)
//   - the active instrument pad (rendered via v-if from a prop)
//
// Why one island instead of three?
// live_vue 1.2's destroyed() hook *defers* `app.unmount()` until the
// next `phx:page-loading-stop` event — see hooks.ts:78. That event
// only fires on full-page navigation, not on WebSocket-driven LV
// re-renders. So if we have <.DrumPad /> swapping to <.GuitarPad />
// at the HEEX level, each swap leaves the previous Vue app alive
// forever, with its keydown listeners still attached to window.
// After a few switches every keystroke fires multiple instruments
// at once.
//
// Wrapping the pads in a single Vue island fixes it: v-if is pure
// Vue, so the inner pad's onUnmounted properly fires on switch and
// AbortController + stopAllX run as designed.

import { useLiveVue } from "live_vue"
import DrumPad from "@/instruments/DrumPad.vue"
import KeyboardPad from "@/instruments/KeyboardPad.vue"
import GuitarPad from "@/instruments/GuitarPad.vue"
import { ensureStarted, play, type DrumName, type ChordName } from "@/lib/audio"

defineProps<{
  current_instrument: "drums" | "keyboard" | "guitar"
}>()

const live = useLiveVue()

type RemoteNote =
  | { instrument: "drums"; style: string; note: DrumName }
  | { instrument: "keyboard"; style: string; note: string }
  | { instrument: "guitar"; style: string; chord: ChordName }

// Cross-instrument audio: every user hears every other user with the
// sender's chosen style, no matter which pad *they* have on screen.
live.handleEvent("play_remote_note", async (payload: RemoteNote) => {
  await ensureStarted()
  // Drums + keyboard carry `note`; guitar carries `chord`. Normalize
  // to a single string for the engine.
  const note = payload.instrument === "guitar" ? payload.chord : payload.note
  play(payload.instrument, payload.style ?? "synth", note)
})
</script>

<template>
  <DrumPad v-if="current_instrument === 'drums'" />
  <KeyboardPad v-else-if="current_instrument === 'keyboard'" />
  <GuitarPad v-else-if="current_instrument === 'guitar'" />
</template>
