// Vitest test setup. Loaded before each test file via the
// vitest.config.mjs setupFiles option (we don't currently use
// that — but if we ever need a global setup, this is where it
// goes).
//
// Why no global Tone mock here: tests that import from
// "@/lib/audio" mock Tone per-test via vi.mock so the noise stays
// near where it's actually used. Tests that don't need audio
// don't pay the mocking cost.

export {}
