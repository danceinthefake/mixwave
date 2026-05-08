<script setup lang="ts">
// Always-mounted invisible Vue island. Owns the single
// `play_remote_note` handler for the whole page so users hear every
// other player's instrument regardless of which pad *they* have on
// screen — that's "everyone hears everyone."
//
// StudioLive already filters self-events server-side, so this only
// fires for *other* users' notes. Pads themselves play their own
// taps locally and only push (no handleEvent on the pad side).

import { useLiveVue } from "live_vue"
import {
  ensureStarted,
  playDrum,
  playKey,
  playChord,
  type DrumName,
  type ChordName,
} from "@/lib/audio"

const live = useLiveVue()

type RemoteNote =
  | { instrument: "drums"; note: DrumName }
  | { instrument: "keyboard"; note: string }
  | { instrument: "guitar"; chord: ChordName }

live.handleEvent("play_remote_note", async (payload: RemoteNote) => {
  await ensureStarted()
  switch (payload.instrument) {
    case "drums":
      playDrum(payload.note)
      break
    case "keyboard":
      playKey(payload.note)
      break
    case "guitar":
      playChord(payload.chord)
      break
  }
})
</script>

<template>
  <span class="hidden" aria-hidden="true" />
</template>
