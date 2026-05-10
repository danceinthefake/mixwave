import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount, flushPromises } from "@vue/test-utils"
import { nextTick } from "vue"

const {
  playMock,
  stopAllMock,
  preloadMock,
  ensureStartedMock,
  pushEventMock,
} = vi.hoisted(() => ({
  playMock: vi.fn(),
  stopAllMock: vi.fn(),
  preloadMock: vi.fn(),
  ensureStartedMock: vi.fn().mockResolvedValue(undefined),
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

import KeyboardPad from "@/instruments/KeyboardPad.vue"

describe("KeyboardPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    preloadMock.mockClear()
    ensureStartedMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders three octaves of keys plus style chips", () => {
    const wrapper = mount(KeyboardPad, { props: { remoteHit: null } })
    const text = wrapper.text()

    // Default visible window is C3..C6.
    expect(text).toContain("C3")
    expect(text).toContain("C5")
    expect(text).toContain("C6")
    for (const style of ["Synth", "Lead", "Grand"]) {
      expect(text).toContain(style)
    }
  })

  it("clicking a white key plays keyboard/<style>/<note> + pushes the LV event", async () => {
    const wrapper = mount(KeyboardPad, { props: { remoteHit: null } })

    // Find a white key whose label matches a known pitch+octave the
    // default window contains. C4 is in C3..C6.
    const c4 = wrapper
      .findAll("button")
      .find((b) => b.text().includes("C4"))

    expect(c4).toBeDefined()
    await c4!.trigger("pointerdown")

    expect(ensureStartedMock).toHaveBeenCalled()
    expect(playMock).toHaveBeenCalledWith("keyboard", "synth", "C4")
    expect(pushEventMock).toHaveBeenCalledWith("note", {
      instrument: "keyboard",
      style: "synth",
      note: "C4",
    })
  })

  it("octave shift cuts held notes via stopAll", async () => {
    const wrapper = mount(KeyboardPad, { props: { remoteHit: null } })

    const plus = wrapper.findAll("button").find((b) => b.text().trim() === "+")!
    await plus.trigger("click")
    await flushPromises()
    await nextTick()

    // shiftOctave() calls stopAll on the previous flavor before
    // changing the visible window. The window-change side is
    // exercised by integration / browser testing; here we just
    // confirm the audio side-effect.
    expect(stopAllMock).toHaveBeenCalledWith("keyboard", "synth")
  })

  it("switching to Grand stops the previous engine and preloads samples", async () => {
    const wrapper = mount(KeyboardPad, { props: { remoteHit: null } })

    const grand = wrapper.findAll("button").find((b) => b.text().trim() === "Grand")!
    await grand.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("keyboard", "synth")
    expect(preloadMock).toHaveBeenCalledWith("keyboard", "piano")
  })
})
