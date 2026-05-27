// Deterministic geometric identicon for a player, seeded by user_id.
// Mirrors the server-side algorithm in chamber_live.ex
// (player_identicon / identicon_data) byte-for-byte so a player's
// avatar is identical in the presence panel (HEEX) and the mini-game
// scoreboard (Vue). FNV-1a/32 over the seed's char codes; UUIDs are
// ASCII so JS char codes == the Elixir byte hash.

export type Identicon = {
  // Hue 0..359 — drives a permanent oklch colour per user.
  hue: number
  // Filled cells of a left-right symmetric 5x5 grid.
  cells: [number, number][]
}

export function identicon(seed: string): Identicon {
  let h = 2166136261 >>> 0
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i)
    h = Math.imul(h, 16777619) >>> 0
  }

  const hue = h % 360
  const cells: [number, number][] = []
  for (let y = 0; y < 5; y++) {
    for (let x = 0; x < 3; x++) {
      if ((h >>> (y * 3 + x)) & 1) {
        cells.push([x, y])
        if (x < 2) cells.push([4 - x, y])
      }
    }
  }

  return { hue, cells }
}
