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

import SynthPad from "@/instruments/SynthPad.vue"

describe("SynthPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    ensureStartedMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders the chord buttons + style chips", () => {
    const wrapper = mount(SynthPad, { props: { remoteHit: null } })
    const text = wrapper.text()

    for (const chord of ["C", "Am", "Em", "G"]) {
      expect(text).toContain(chord)
    }
    for (const style of ["Warm", "Bell", "Sweep"]) {
      expect(text).toContain(style)
    }
  })

  it("hitting a chord plays pad/<style>/<chord> with octave 0 and pushes the LV event", async () => {
    const wrapper = mount(SynthPad, { props: { remoteHit: null } })

    // The chord-name <div> is the button's first child; the kbd
    // shortcut also lives inside the button so b.text() blends
    // both. Match on the first div instead.
    const c = wrapper
      .findAll("button")
      .find((b) => b.find("div").exists() && b.find("div").text().trim() === "C")!

    await c.trigger("pointerdown")

    expect(playMock).toHaveBeenCalledWith("pad", "warm", "C", 0)
    expect(pushEventMock).toHaveBeenCalledWith("note", {
      instrument: "pad",
      style: "warm",
      chord: "C",
      octave_offset: 0,
    })
  })

  it("octave shift propagates to subsequent hits", async () => {
    const wrapper = mount(SynthPad, { props: { remoteHit: null } })

    const plus = wrapper.findAll("button").find((b) => b.text().trim() === "+")!
    await plus.trigger("click")

    const c = wrapper
      .findAll("button")
      .find((b) => b.find("div").exists() && b.find("div").text().trim() === "C")!
    await c.trigger("pointerdown")

    expect(playMock).toHaveBeenLastCalledWith("pad", "warm", "C", 1)
    expect(pushEventMock).toHaveBeenLastCalledWith("note", {
      instrument: "pad",
      style: "warm",
      chord: "C",
      octave_offset: 1,
    })
  })

  it("style switch stops the previous engine", async () => {
    const wrapper = mount(SynthPad, { props: { remoteHit: null } })

    const bell = wrapper.findAll("button").find((b) => b.text().trim() === "Bell")!
    await bell.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("pad", "warm")
  })
})
