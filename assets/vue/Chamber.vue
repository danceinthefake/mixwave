<script setup lang="ts">
// The single Vue island for the chamber. Owns:
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

import { computed, onMounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
// Named imports for tree-shake. See assets/vue/lib/audio.ts for
// the full rationale.
import { context as toneContext } from "tone"
import DrumPad from "@/instruments/DrumPad.vue"
import KeyboardPad from "@/instruments/KeyboardPad.vue"
import GuitarPad from "@/instruments/GuitarPad.vue"
import BassPad from "@/instruments/BassPad.vue"
import SynthPad from "@/instruments/SynthPad.vue"
import SulingPad from "@/instruments/SulingPad.vue"
import KendangPad from "@/instruments/KendangPad.vue"
import PokerBoard from "@/activities/poker/PokerBoard.vue"
import {
  ensureStarted,
  play,
  preload,
  setMasterVolume,
  setChamberKind,
  startRecording,
  stopRecording,
  type ChamberKind,
  type DrumName,
  type ChordName,
} from "@/lib/audio"

const props = defineProps<{
  current_instrument: "drums" | "keyboard" | "guitar" | "bass" | "pad" | "suling" | "kendang"
  chamber_kind: ChamberKind
  // Used to name the audio file the user downloads from the
  // "Download audio" button — title is preferred, slug is the
  // always-present fallback. Server already truncates title to
  // 80 chars and trims whitespace.
  chamber_title?: string | null
  chamber_slug: string
  // Which activity this chamber hosts. Gates the music-only UI
  // (tap-to-enter audio gate, FX bus, master volume). Defaults
  // to "music" so legacy chambers without the column behave
  // identically to v3.
  activity: "music" | "poker"
  // How many people are presently in the chamber. Used by music
  // mode to render the "Quiet here — start a chord…" hint when
  // the user is alone, mirroring the poker board's
  // "Waiting for the team" empty state.
  presence_count?: number
  // Poker-specific props. `poker_session` is `null` for music
  // chambers; PokerBoard.vue renders an empty state in that case.
  // The LV derives `poker_session` per-user (filters vote values
  // during :voting so only the current user's own card travels
  // to the client).
  poker_session?: import("./activities/poker/PokerBoard.vue").PokerSession | null
  poker_participants?: import("./activities/poker/PokerBoard.vue").Participant[]
  current_user_id?: string
  is_host?: boolean
}>()

// Apply the chamber's audio character whenever the LiveView
// updates the prop (creator changing the kind, or a remote
// :chamber_updated broadcast). The setter is idempotent;
// calling it with the same value is a cheap no-op.
//
// Crucially this is NOT { immediate: true } — that would fire
// during SSR setup, which calls into Tone.js and tries to build
// an AudioContext that doesn't exist on Node. The initial apply
// happens in onMounted below, after we know we're on the client.
//
// Also gated on activity: poker chambers never play audio, so
// touching the FX bus would needlessly wake the AudioContext.
watch(
  () => props.chamber_kind,
  (kind) => {
    if (props.activity === "music" && kind) setChamberKind(kind)
  },
)

const live = useLiveVue()

type StrumPhase = "press" | "release"
type RemoteNote =
  | { instrument: "drums"; style: string; note: DrumName }
  | { instrument: "keyboard"; style: string; note: string }
  | {
      instrument: "guitar"
      style: string
      chord: ChordName
      octave_offset?: number
      phase?: StrumPhase
      up_strum?: boolean
    }
  | { instrument: "bass"; style: string; note: string }
  | { instrument: "pad"; style: string; chord: ChordName; octave_offset?: number }
  | { instrument: "suling"; style: string; note: string }
  | { instrument: "kendang"; style: string; note: string }

// Latest remote hit, broadcast down to whichever pad is currently
// mounted so it can flash the matching button. New object on every
// hit (timestamped) so Vue's watcher always re-fires, even if two
// rapid hits target the same note.
type RemoteHit = { instrument: string; note: string; t: number }
const lastRemoteHit = ref<RemoteHit | null>(null)

// Master output volume slider. Persisted per-user in localStorage —
// each browser remembers where you set it last.
//
// localStorage and Tone.js are browser-only; live_vue runs this
// `<script setup>` on the server too via SSR. Defer to onMounted
// (client-only) for the initial read + Tone.Destination call.
const VOLUME_KEY = "mixchamb:volume"
const volume = ref(80)

watch(volume, (v) => {
  // The watch only fires from user interaction with the slider —
  // never during SSR — so localStorage and Tone are safe here.
  setMasterVolume(v / 100)
  localStorage.setItem(VOLUME_KEY, String(v))
})

onMounted(() => {
  // Skip Tone.js bootstrap for non-music chambers — they never
  // play sound, so building an AudioContext or reading the
  // volume slider is wasted work.
  if (props.activity !== "music") return

  // Initial apply of the chamber's audio character. Has to live
  // here (not in a watch with immediate: true) because Tone.js
  // builds an AudioContext on first use and there's no such thing
  // on the SSR side.
  if (props.chamber_kind) setChamberKind(props.chamber_kind)

  const stored = Number.parseInt(localStorage.getItem(VOLUME_KEY) ?? "80", 10)
  if (Number.isFinite(stored)) {
    volume.value = Math.max(0, Math.min(100, stored))
  }
  setMasterVolume(volume.value / 100)
  // If the AudioContext is already running (e.g., the user
  // navigated here from another page where they interacted),
  // skip the gate.
  if (toneContext?.state === "running") {
    audioReady.value = true
  }
})

// Tap-to-enter overlay: browsers won't let AudioContext start until
// the user makes a gesture on the page. Without this gate, an
// incoming remote note that arrives before the local user has tapped
// anything tries to start the context from inside an event handler
// that the browser doesn't count as a gesture, gets blocked, and
// silently fails. The overlay forces a real click before any audio
// can be played.
const audioReady = ref(false)

async function enterChamber() {
  await ensureStarted()
  audioReady.value = true
}

// Headline copy on the audio gate. Music chambers get the
// jamming-flavoured prompt; poker rooms get a poker-table
// metaphor. Sub-line + button label are activity-neutral so
// they don't need to branch. The gate itself isn't optional in
// poker — the reveal chime needs an unlocked AudioContext too,
// and a late joiner who never voted before the host hit Reveal
// would otherwise miss the cue entirely.
const gateHeading = computed(() =>
  props.activity === "music" ? "Tap to start jamming" : "Tap to take a seat",
)

// Replay-last-30s. Vue requests a burst from LV; LV pushes back the
// note buffer with offsets; we schedule each via setTimeout from
// "now". Local-only — others don't hear our replay.
type ReplayEvent = {
  instrument: string
  style: string
  note?: string
  chord?: string
  octave_offset?: number
  phase?: StrumPhase
  up_strum?: boolean
  offset_ms: number
}

const isReplaying = ref(false)
const isCapturing = ref(false)
const lastRecording = ref<{
  blob: Blob
  createdAt: Date
  durationMs: number
} | null>(null)
let captureStartedAt: number | null = null
let replayTimers: number[] = []

function startReplay() {
  if (isReplaying.value) return
  isReplaying.value = true
  live.pushEvent("request_replay", {})
}

function stopReplay() {
  for (const id of replayTimers) window.clearTimeout(id)
  replayTimers = []
  isReplaying.value = false
}

live.handleEvent("replay_burst", async ({ events }: { events: ReplayEvent[] }) => {
  // Cancel any in-flight replay before scheduling the new one.
  for (const id of replayTimers) window.clearTimeout(id)
  replayTimers = []

  if (!events || events.length === 0) {
    isReplaying.value = false
    return
  }

  await ensureStarted()

  // Preload every (instrument, style) referenced in the replay
  // BEFORE we schedule individual notes. Sampler-based voices
  // (piano, acoustic guitar, suling) throw "buffer is either not
  // set or not loaded" if triggered while their samples are
  // still in flight, and an unhandled rejection mid-replay
  // tends to silently drop later timers along with it.
  const uniqueVoices = new Set<string>()
  for (const e of events) {
    uniqueVoices.add(`${e.instrument}|${e.style ?? "synth"}`)
  }
  await Promise.all(
    Array.from(uniqueVoices).map((key) => {
      const [inst, style] = key.split("|")
      return preload(inst, style)
    }),
  )

  for (const e of events) {
    const id = window.setTimeout(() => {
      // guitar + pad carry chord; everything else carries note.
      const note = e.chord ?? e.note
      if (!note) return
      const opts = e.phase ? { phase: e.phase, upStrum: e.up_strum } : undefined
      try {
        play(e.instrument, e.style ?? "synth", note, e.octave_offset ?? 0, opts)
      } catch (err) {
        // Don't let one bad note (sampler not loaded etc.) kill
        // the rest of the replay.
        console.warn("replay play() threw:", err)
      }
    }, e.offset_ms)
    replayTimers.push(id)
  }

  // Mark replay finished a bit after the last scheduled event.
  const tail = events[events.length - 1].offset_ms
  const doneId = window.setTimeout(() => {
    isReplaying.value = false
  }, tail + 200)
  replayTimers.push(doneId)
})

// Audio capture is now tied to the REC toggle in the chamber, not
// to replay. The creator's LV push_events here when they flip the
// chamber-level REC button; non-creators never receive these.
live.handleEvent("start_audio_capture", async () => {
  if (isCapturing.value) return
  await ensureStarted()
  try {
    await startRecording()
    isCapturing.value = true
    captureStartedAt = Date.now()
  } catch (err) {
    console.warn("startRecording failed:", err)
  }
})

live.handleEvent("stop_audio_capture", async () => {
  if (!isCapturing.value) return
  isCapturing.value = false
  const startedAt = captureStartedAt
  captureStartedAt = null
  const blob = await stopRecording()
  if (blob && blob.size > 0) {
    lastRecording.value = {
      blob,
      createdAt: new Date(),
      // Wall-clock between start and stop. Tone.Recorder doesn't
      // expose the recording's actual duration, and decoding the
      // blob to count samples is expensive; this is close enough
      // for a label.
      durationMs: startedAt ? Date.now() - startedAt : 0,
    }
  }
})

live.handleEvent("clear_audio_capture", () => {
  lastRecording.value = null
})

function downloadLastRecording() {
  const rec = lastRecording.value
  if (!rec) return

  const url = URL.createObjectURL(rec.blob)
  const a = document.createElement("a")
  a.href = url
  a.download = recordingFilename(rec.blob, rec.createdAt)
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  // Hold the URL until next tick so the download has a chance to
  // start before we revoke; firefox is picky about this.
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  // Let the LV clear its has_pending_audio flag so a subsequent
  // Start Recording doesn't trip the overwrite confirm.
  live.pushEvent("audio_downloaded", {})
}

// Maps the MIME type Tone.Recorder produced to a sensible
// filename extension. MediaRecorder commonly emits audio/ogg
// on Firefox, audio/webm on Chrome, audio/mp4 on Safari.
function extensionFor(mime: string): string {
  if (mime.includes("mp4")) return "mp4"
  if (mime.includes("ogg")) return "ogg"
  return "webm"
}

// Build the download filename. Prefer the chamber title (if set
// and non-empty) over the slug. Strip everything except alnum,
// dash, and underscore so the name is filesystem-safe across
// platforms.
function recordingFilename(blob: Blob, createdAt: Date): string {
  const stem =
    (props.chamber_title?.trim() || props.chamber_slug)
      .toLowerCase()
      .replace(/\s+/g, "-")
      .replace(/[^a-z0-9_-]/g, "")
      .slice(0, 60) || "jam"

  const stamp = createdAt.toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-")

  return `mixchamb-${stem}-${stamp}.${extensionFor(blob.type)}`
}

function formatDuration(ms: number): string {
  const totalSec = Math.max(0, Math.round(ms / 1000))
  const min = Math.floor(totalSec / 60)
  const sec = totalSec % 60
  return `${min}:${sec.toString().padStart(2, "0")}`
}

function formatBytes(n: number): string {
  if (n < 1024) return `${n} B`
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`
  return `${(n / 1024 / 1024).toFixed(1)} MB`
}

// Cross-instrument audio: every user hears every other user with the
// sender's chosen style, no matter which pad *they* have on screen.
live.handleEvent("play_remote_note", async (payload: RemoteNote) => {
  await ensureStarted()
  // Drums + keyboard + bass carry `note`; guitar + pad carry `chord`.
  // Normalize to a single string for the engine + the remote-flash
  // signal. octave_offset applies to chord-based instruments;
  // phase ("press" / "release") applies to guitar only.
  const note = "chord" in payload ? payload.chord : payload.note
  const octaveOffset = "octave_offset" in payload ? (payload.octave_offset ?? 0) : 0
  const phase = "phase" in payload ? payload.phase : undefined
  const upStrum = "up_strum" in payload ? payload.up_strum : undefined
  const opts = phase ? { phase, upStrum } : undefined
  play(payload.instrument, payload.style ?? "synth", note, octaveOffset, opts)
  // Only flash on press, not on release — release events would
  // double-flash the pad otherwise.
  if (phase !== "release") {
    lastRemoteHit.value = { instrument: payload.instrument, note, t: Date.now() }
  }
})
</script>

<template>
  <!-- Tap-to-enter overlay. Covers everything until the user makes
       a real gesture on the page so the browser will let
       AudioContext start. Without this, the first remote-note event
       (which arrives in a non-gesture context) can't play and we
       lose audio for whatever happened before the local user
       tapped anything themselves. -->
  <Transition
    enter-active-class="transition-all duration-300 ease-out"
    leave-active-class="transition-all duration-300 ease-in"
    enter-from-class="opacity-0 scale-95"
    leave-to-class="opacity-0 scale-95"
  >
    <div
      v-if="!audioReady"
      @click="enterChamber"
      class="fixed inset-0 z-50 flex items-center justify-center backdrop-blur-md bg-background/80 cursor-pointer select-none"
    >
      <div class="flex flex-col items-center gap-6 text-center px-4">
        <!-- Logo with the brand-coloured halo behind it, same
             treatment the landing hero uses. The mark itself
             carries no filter (per UI.md "Logo › Don'ts"); the
             halo sits on a lower stacking layer. -->
        <div class="relative">
          <div
            aria-hidden="true"
            class="absolute inset-0 -m-8 rounded-full blur-2xl opacity-60 brand-glow"
          >
          </div>
          <img src="/images/logo.svg" alt="" class="relative size-20" />
        </div>
        <div class="space-y-1">
          <h2 class="text-3xl font-bold tracking-tight font-display brand-gradient-text">
            {{ gateHeading }}
          </h2>
          <p class="text-sm text-muted-foreground">
            Browsers need a gesture before audio can play
          </p>
        </div>
        <button
          class="px-6 py-2.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 hover:-translate-y-px hover:shadow-md transition-all cursor-pointer font-medium"
        >
          Enter chamber
        </button>
      </div>
    </div>
  </Transition>

  <div v-if="props.activity === 'music'" class="space-y-4">
    <!-- Top control strip: replay + master volume. Floating-bar
         look matches the bottom dock for visual consistency. -->
    <div class="flex justify-end">
      <div
        class="flex items-center gap-3 rounded-xl border bg-card/60 backdrop-blur-sm px-3 py-1.5 shadow-sm"
      >
        <button
          @click="isReplaying ? stopReplay() : startReplay()"
          :class="[
            'px-2.5 py-1 text-xs rounded-md transition-colors cursor-pointer',
            isReplaying
              ? 'bg-destructive/10 text-destructive'
              : 'text-muted-foreground hover:bg-accent hover:text-foreground',
          ]"
        >
          {{ isReplaying ? "Stop replay" : "↩ Replay 30s" }}
        </button>

        <!-- Download audio. Visible after Stop recording; stays
             visible until the user clicks Reset Recording or
             starts a new recording (and lets it finish). -->
        <button
          v-if="lastRecording"
          @click="downloadLastRecording"
          class="px-2.5 py-1 text-xs rounded-md text-foreground bg-primary/10 hover:bg-primary/20 transition-colors cursor-pointer flex items-center gap-1.5"
          :title="`${lastRecording.blob.type} • ${recordingFilename(lastRecording.blob, lastRecording.createdAt)}`"
        >
          <span>⬇ Download audio</span>
          <span class="text-muted-foreground tabular-nums">
            · {{ formatDuration(lastRecording.durationMs) }} ·
            {{ formatBytes(lastRecording.blob.size) }}
          </span>
        </button>

        <!-- Pulsing red dot while a recordable replay is captured.
             Lets the user know audio is being grabbed without
             cluttering the bar with extra copy. -->
        <span
          v-if="isCapturing"
          class="inline-flex items-center gap-1.5 px-2 text-xs text-red-500"
        >
          <span class="size-2 rounded-full bg-red-500 animate-pulse"></span>
          Capturing…
        </span>

        <div class="w-px h-5 bg-border"></div>

        <span class="text-xs uppercase tracking-wider text-muted-foreground">Vol</span>
        <input
          v-model.number="volume"
          type="range"
          min="0"
          max="100"
          class="brand-gradient-slider w-28"
        />
        <span class="text-xs tabular-nums font-mono text-muted-foreground w-9 text-right">
          {{ volume }}%
        </span>
      </div>
    </div>

    <!-- Inline empty-state hint when the player is alone in the
         chamber. Mirrors the poker board's "Waiting for the team"
         hint; copy matches the UI.md voice "Empty / error states"
         entry verbatim. Drops itself the moment a second person
         joins. -->
    <p
      v-if="(props.presence_count ?? 0) <= 1"
      class="text-sm text-muted-foreground italic text-center"
    >
      Quiet here — start a chord and someone'll join.
    </p>

    <!-- Per-instrument scope wrapper overrides --ring so the
         keyboard-focus outline on whichever pad is active picks
         up the matching instrument accent (see app.css
         pad-scope-* utilities). -->
    <div :class="`pad-scope-${current_instrument}`">
      <DrumPad v-if="current_instrument === 'drums'" :remote-hit="lastRemoteHit" />
      <KeyboardPad v-else-if="current_instrument === 'keyboard'" :remote-hit="lastRemoteHit" />
      <GuitarPad v-else-if="current_instrument === 'guitar'" :remote-hit="lastRemoteHit" />
      <BassPad v-else-if="current_instrument === 'bass'" :remote-hit="lastRemoteHit" />
      <SynthPad v-else-if="current_instrument === 'pad'" :remote-hit="lastRemoteHit" />
      <SulingPad v-else-if="current_instrument === 'suling'" :remote-hit="lastRemoteHit" />
      <KendangPad v-else-if="current_instrument === 'kendang'" :remote-hit="lastRemoteHit" />
    </div>
  </div>

  <PokerBoard
    v-else-if="props.activity === 'poker'"
    :chamber_slug="props.chamber_slug"
    :chamber_title="props.chamber_title"
    :poker_session="props.poker_session ?? null"
    :poker_participants="props.poker_participants ?? []"
    :current_user_id="props.current_user_id ?? ''"
    :is_host="props.is_host ?? false"
  />
</template>
