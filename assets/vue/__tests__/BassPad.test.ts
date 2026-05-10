import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount } from "@vue/test-utils"

const { playMock, stopAllMock, ensureStartedMock, pushEventMock } = vi.hoisted(
  () => ({
    playMock: vi.fn(),
    stopAllMock: vi.fn(),
    ensureStartedMock: vi.fn().mockResolvedValue(undefined),
    pushEventMock: vi.fn(),
  }),
)

vi.mock("@/lib/audio", () => ({
  ensureStarted: ensureStartedMock,
  play: playMock,
  stopAll: stopAllMock,
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import BassPad from "@/instruments/BassPad.vue"

describe("BassPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    ensureStartedMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders the four-string fretboard with style chips", () => {
    const wrapper = mount(BassPad, { props: { remoteHit: null } })
    const text = wrapper.text()

    // Standard 4-string bass tuning labels (lowest to highest).
    for (const string of ["E", "A", "D", "G"]) {
      expect(text).toContain(string)
    }
    for (const style of ["Synth", "Sub", "Slap"]) {
      expect(text).toContain(style)
    }
  })

  it("hitting a fret plays bass/<style>/<note> + pushes the LV event", async () => {
    const wrapper = mount(BassPad, { props: { remoteHit: null } })

    // Pick any fret button — they're rendered as <button>s inside
    // the fretboard grid. Take the first interactive one whose
    // text matches a pitch+octave.
    const fretButton = wrapper
      .findAll("button")
      .find((b) => /^[A-G]#?\d?$/.test(b.text().trim()) && b.text().trim().length >= 1)

    expect(fretButton).toBeDefined()

    await fretButton!.trigger("pointerdown")

    expect(ensureStartedMock).toHaveBeenCalled()
    expect(playMock).toHaveBeenCalledWith(
      "bass",
      "synth",
      expect.any(String),
    )

    expect(pushEventMock).toHaveBeenCalledWith(
      "note",
      expect.objectContaining({
        instrument: "bass",
        style: "synth",
      }),
    )
  })

  it("style switch stops the previous engine", async () => {
    const wrapper = mount(BassPad, { props: { remoteHit: null } })

    const slap = wrapper.findAll("button").find((b) => b.text().trim() === "Slap")!
    await slap.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("bass", "synth")

    // Next hit should use the new style.
    const fretButton = wrapper
      .findAll("button")
      .find((b) => /^[A-G]#?\d?$/.test(b.text().trim()) && b.text().trim().length >= 1)!

    await fretButton.trigger("pointerdown")
    expect(playMock).toHaveBeenLastCalledWith(
      "bass",
      "slap",
      expect.any(String),
    )
  })
})
