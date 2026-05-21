import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount } from "@vue/test-utils"

const { playMock, stopAllMock, ensureStartedMock, pushEventMock } = vi.hoisted(() => ({
  playMock: vi.fn(),
  stopAllMock: vi.fn(),
  ensureStartedMock: vi.fn().mockResolvedValue(undefined),
  pushEventMock: vi.fn(),
}))

vi.mock("@/lib/audio", () => ({
  ensureStarted: ensureStartedMock,
  play: playMock,
  stopAll: stopAllMock,
}))

// DrumPad.vue side-effect-imports the drum engine module so its
// engines register into the audio.ts map at mount time. In tests we
// don't want any real Tone.js engine wiring — stub it as a no-op.
vi.mock("@/lib/audio/drums", () => ({}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import DrumPad from "@/instruments/DrumPad.vue"

describe("DrumPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    ensureStartedMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders the kit pieces from the drummer-eye layout", () => {
    const wrapper = mount(DrumPad, { props: { remoteHit: null } })
    const text = wrapper.text()

    for (const piece of ["Snare", "Hi-hat", "Floor Tom", "Ride", "Bass L", "Bass R"]) {
      expect(text).toContain(piece)
    }
  })

  it("hitting Snare plays drums/<style>/snare and pushes the note", async () => {
    const wrapper = mount(DrumPad, { props: { remoteHit: null } })

    const snare = wrapper.findAll("button").find((b) => b.text().includes("Snare"))!

    await snare.trigger("pointerdown")

    expect(playMock).toHaveBeenCalledWith("drums", "synth", "snare")
    expect(pushEventMock).toHaveBeenCalledWith("note", {
      instrument: "drums",
      style: "synth",
      note: "snare",
    })
  })

  it("the throne is decorative — clicking it doesn't trigger a play", async () => {
    const wrapper = mount(DrumPad, { props: { remoteHit: null } })

    const throne = wrapper.findAll("button").find((b) => b.text().includes("Throne"))!

    await throne.trigger("pointerdown")

    expect(playMock).not.toHaveBeenCalled()
    expect(pushEventMock).not.toHaveBeenCalled()
  })

  it("Bass L and Bass R both trigger the kick drum", async () => {
    const wrapper = mount(DrumPad, { props: { remoteHit: null } })

    const bassL = wrapper.findAll("button").find((b) => b.text().includes("Bass L"))!
    const bassR = wrapper.findAll("button").find((b) => b.text().includes("Bass R"))!

    await bassL.trigger("pointerdown")
    await bassR.trigger("pointerdown")

    const kickHits = playMock.mock.calls.filter(([, , drum]) => drum === "kick")
    expect(kickHits.length).toBe(2)
  })

  it("style switch cuts the previous flavor's tail", async () => {
    const wrapper = mount(DrumPad, { props: { remoteHit: null } })

    const acoustic = wrapper.findAll("button").find((b) => b.text().trim() === "Acoustic")!

    await acoustic.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("drums", "synth")
  })
})
