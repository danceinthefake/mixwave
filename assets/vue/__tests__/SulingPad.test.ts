import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount } from "@vue/test-utils"

const { playMock, stopAllMock, ensureStartedMock, preloadMock, pushEventMock } =
  vi.hoisted(() => ({
    playMock: vi.fn(),
    stopAllMock: vi.fn(),
    ensureStartedMock: vi.fn().mockResolvedValue(undefined),
    preloadMock: vi.fn(),
    pushEventMock: vi.fn(),
  }))

vi.mock("@/lib/audio", () => ({
  ensureStarted: ensureStartedMock,
  play: playMock,
  stopAll: stopAllMock,
  preload: preloadMock,
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import SulingPad from "@/instruments/SulingPad.vue"

describe("SulingPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    ensureStartedMock.mockClear()
    preloadMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders 12 chromatic notes plus 3 style chips", () => {
    const wrapper = mount(SulingPad, { props: { remoteHit: null } })
    const text = wrapper.text()

    // Naturals + accidentals over one octave.
    for (const n of ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]) {
      expect(text).toContain(n)
    }
    for (const s of ["Synth", "Bamboo", "Sweet"]) {
      expect(text).toContain(s)
    }
  })

  it("clicking a note plays suling/<style>/<noteN>", async () => {
    const wrapper = mount(SulingPad, { props: { remoteHit: null } })

    // Match the C button (the "C" label without "C#") by exact text.
    const c = wrapper
      .findAll("button")
      .find((b) => b.text().trim().startsWith("C") && !b.text().includes("#"))!

    await c.trigger("pointerdown")

    expect(playMock).toHaveBeenCalledWith("suling", "synth", "C5")
    expect(pushEventMock).toHaveBeenCalledWith("note", {
      instrument: "suling",
      style: "synth",
      note: "C5",
    })
  })

  it("style switch stops the previous engine and preloads the new one", async () => {
    const wrapper = mount(SulingPad, { props: { remoteHit: null } })

    const bamboo = wrapper
      .findAll("button")
      .find((b) => b.text().trim() === "Bamboo")!

    await bamboo.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("suling", "synth")
    expect(preloadMock).toHaveBeenCalledWith("suling", "bamboo")
  })
})
