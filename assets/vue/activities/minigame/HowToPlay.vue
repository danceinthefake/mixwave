<script setup lang="ts">
// Collapsible per-game rules (mirrors the retro board's "How retros
// work"). Closed by default. Shown to the host in the lobby and to
// everyone once a game is in progress.

defineProps<{ game: string }>()
</script>

<template>
  <details class="rounded-lg border bg-card/40 group">
    <summary
      class="cursor-pointer px-3 py-2 text-xs font-medium text-muted-foreground hover:text-foreground flex items-center justify-between"
    >
      <span>How to play {{ game === "gartic_phone" ? "Gartic Phone" : "Pictionary" }}</span>
      <span aria-hidden="true" class="group-open:rotate-90 transition-transform">›</span>
    </summary>

    <div
      v-if="game === 'gartic_phone'"
      class="px-4 pb-3 pt-1 text-xs text-muted-foreground space-y-2 leading-relaxed"
    >
      <p>
        A drawing-telephone game — everyone plays every round at once on their own private screen.
      </p>
      <ol class="space-y-1.5 list-decimal pl-5">
        <li>
          <span class="font-semibold text-foreground">Write</span> — everyone types a secret word or
          phrase to kick off their own book.
        </li>
        <li>
          <span class="font-semibold text-foreground">Draw</span> — your book passes to the next
          player, who draws the phrase they're handed (no peeking at others').
        </li>
        <li>
          <span class="font-semibold text-foreground">Describe</span> — the next player sees only
          that drawing and writes what they think it is. Draw → describe → draw… around the room.
        </li>
        <li>
          <span class="font-semibold text-foreground">Album</span> — once every book has gone all
          the way around, the host flips through each one start to finish. Watch how far it drifted.
        </li>
      </ol>
      <p class="pt-1">
        <span class="font-semibold text-foreground">Tip:</span>
        there's a timer per step — if you run out, whatever you've got is submitted.
      </p>
    </div>

    <div v-else class="px-4 pb-3 pt-1 text-xs text-muted-foreground space-y-2 leading-relaxed">
      <p>Live draw-and-guess. One person draws each turn; everyone else guesses in the feed.</p>
      <ol class="space-y-1.5 list-decimal pl-5">
        <li>
          <span class="font-semibold text-foreground">Draw</span> — the drawer picks one of three
          words and sketches it on the shared canvas. They can't type.
        </li>
        <li>
          <span class="font-semibold text-foreground">Guess</span> — everyone else races the timer
          in the guess feed. Blanks show the length; letters reveal as time drains.
        </li>
        <li>
          <span class="font-semibold text-foreground">Score</span> — faster correct guesses score
          more (50–100); the drawer scores for each person who gets it.
        </li>
        <li>
          <span class="font-semibold text-foreground">Rotate</span> — the drawer changes each turn;
          play through the set number of rounds, high score wins.
        </li>
      </ol>
      <p class="pt-1">
        <span class="font-semibold text-foreground">Tip:</span>
        a near-miss guess gets a private "so close!" — keep trying variations.
      </p>
    </div>
  </details>
</template>
