<script setup lang="ts">
// Sticky bottom hint during :voting — shows how many votes the
// current user has left of their 3-dot allocation (spec §5).
// Cards themselves enforce the cap; this panel is just feedback.

import { computed } from "vue"

const props = defineProps<{
  votes_remaining: number
  vote_cap: number
}>()

const spent = computed(() => props.vote_cap - props.votes_remaining)
const allSpent = computed(() => props.votes_remaining === 0)
</script>

<template>
  <div
    class="sticky bottom-2 z-10 rounded-xl border bg-card/95 backdrop-blur px-4 py-2.5 flex items-center gap-3 shadow-sm"
    role="status"
    aria-live="polite"
  >
    <div class="flex items-center gap-1.5" aria-hidden="true">
      <span
        v-for="n in vote_cap"
        :key="n"
        class="size-2.5 rounded-full"
        :class="n <= spent ? 'bg-accent-bass' : 'bg-muted'"
      ></span>
    </div>
    <p class="text-sm font-medium tabular-nums">{{ spent }}/{{ vote_cap }} votes spent</p>
    <p v-if="allSpent" class="text-xs text-muted-foreground italic ml-auto">
      Tap a vote chip again to withdraw and re-spend.
    </p>
  </div>
</template>
