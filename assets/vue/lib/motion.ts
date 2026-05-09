// Motion tokens for the chamber. Use these instead of magic numbers
// in flash timers so the visual feedback stays consistent across
// instruments. The values are tuned to the physical character of
// the sound each pad makes:
//
//   tight    percussive, instantaneous (drums)
//   medium   pitched single notes + quick strums (keyboard, bass,
//            guitar)
//   long     sustained ambient that rings for a while (pad)
//
// `remoteDelta` extends the flash for *remote* hits so they stay
// visible long enough to register through whatever network jitter
// the broadcast picked up on the way over.

export const FLASH_MS = {
  tight: 120,
  medium: 200,
  long: 450,
} as const

export const REMOTE_FLASH_DELTA_MS = 80
