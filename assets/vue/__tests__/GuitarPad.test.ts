import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount } from "@vue/test-utils"

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

import GuitarPad from "@/instruments/GuitarPad.vue"

describe("GuitarPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    preloadMock.mockClear()
    ensureStartedMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders the chord pad + style chips", () => {
    const wrapper = mount(GuitarPad, { props: { remoteHit: null } })
    const text = wrapper.text()

    for (const chord of ["C", "Am", "Dm", "Em", "G"]) {
      expect(text).toContain(chord)
    }
    for (const style of ["Synth", "Electric", "Rock", "Mandolin"]) {
      expect(text).toContain(style)
    }
  })

  it("pointerdown plays the press phase + pushes the matching LV event", async () => {
    const wrapper = mount(GuitarPad, { props: { remoteHit: null } })

    // Each chord button contains the name in its first <div>, plus
    // a fingering diagram + kbd; .text() blends them all, so match
    // on the first div instead.
    const c = wrapper
      .findAll("button")
      .find((b) => b.find("div").exists() && b.find("div").text().trim() === "C")!

    await c.trigger("pointerdown")

    expect(playMock).toHaveBeenCalledWith(
      "guitar",
      "synth",
      "C",
      0,
      expect.objectContaining({ phase: "press" }),
    )
    expect(pushEventMock).toHaveBeenCalledWith("note", {
      instrument: "guitar",
      style: "synth",
      chord: "C",
      octave_offset: 0,
      phase: "press",
    })
  })

  it("pointerup plays the release phase", async () => {
    const wrapper = mount(GuitarPad, { props: { remoteHit: null } })
    const c = wrapper
      .findAll("button")
      .find((b) => b.find("div").exists() && b.find("div").text().trim() === "C")!

    await c.trigger("pointerdown")
    await c.trigger("pointerup")

    const releaseCalls = playMock.mock.calls.filter(
      ([, , , , opts]) => opts && opts.phase === "release",
    )
    expect(releaseCalls.length).toBe(1)

    const releasePushes = pushEventMock.mock.calls.filter(
      ([_event, payload]) => payload.phase === "release",
    )
    expect(releasePushes.length).toBe(1)
    expect(releasePushes[0][1]).toMatchObject({
      instrument: "guitar",
      chord: "C",
      phase: "release",
    })
  })

  it("octave shift propagates to subsequent strums", async () => {
    const wrapper = mount(GuitarPad, { props: { remoteHit: null } })

    const plus = wrapper.findAll("button").find((b) => b.text().trim() === "+")!
    await plus.trigger("click")

    const c = wrapper
      .findAll("button")
      .find((b) => b.find("div").exists() && b.find("div").text().trim() === "C")!
    await c.trigger("pointerdown")

    expect(playMock).toHaveBeenLastCalledWith(
      "guitar",
      "synth",
      "C",
      1,
      expect.any(Object),
    )
  })

  it("switching style stops the previous engine and preloads the new one", async () => {
    const wrapper = mount(GuitarPad, { props: { remoteHit: null } })

    const electric = wrapper.findAll("button").find((b) => b.text().trim() === "Electric")!
    await electric.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("guitar", "synth")
    expect(preloadMock).toHaveBeenCalledWith("guitar", "electric")
  })
})
