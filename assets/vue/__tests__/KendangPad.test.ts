import { describe, it, expect, vi, beforeEach } from "vitest"
import { mount } from "@vue/test-utils"

// vi.mock is hoisted to the top of the file before any imports
// run, so local variables aren't yet defined when the factory
// executes. vi.hoisted lets us share spies between the factory
// and the test body without that race.
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
  preload: vi.fn(),
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import KendangPad from "@/instruments/KendangPad.vue"

describe("KendangPad", () => {
  beforeEach(() => {
    playMock.mockClear()
    stopAllMock.mockClear()
    ensureStartedMock.mockClear()
    pushEventMock.mockClear()
  })

  it("renders one button per pad sound", () => {
    const wrapper = mount(KendangPad, { props: { remoteHit: null } })
    // Six tones + two style buttons.
    const buttons = wrapper.findAll("button")
    expect(buttons.length).toBeGreaterThanOrEqual(6 + 2)

    // Each pad label should appear somewhere in the rendered output.
    for (const label of ["Dang", "Tut", "Dut", "Tak", "Tung", "Pak"]) {
      expect(wrapper.text()).toContain(label)
    }
  })

  it("clicking a pad triggers play() with kendang/<style>/<sound>", async () => {
    const wrapper = mount(KendangPad, { props: { remoteHit: null } })
    const dang = wrapper
      .findAll("button")
      .find((b) => b.text().includes("Dang"))!

    await dang.trigger("pointerdown")

    expect(ensureStartedMock).toHaveBeenCalled()
    expect(playMock).toHaveBeenCalledWith("kendang", "synth", "dang")
  })

  it("clicking a pad pushes a 'note' LV event with the matching payload", async () => {
    const wrapper = mount(KendangPad, { props: { remoteHit: null } })
    const tut = wrapper
      .findAll("button")
      .find((b) => b.text().includes("Tut"))!

    await tut.trigger("pointerdown")

    expect(pushEventMock).toHaveBeenCalledWith("note", {
      instrument: "kendang",
      style: "synth",
      note: "tut",
    })
  })

  it("switching style stops the previous engine and changes the active flavor", async () => {
    const wrapper = mount(KendangPad, { props: { remoteHit: null } })

    const wood = wrapper
      .findAll("button")
      .find((b) => b.text().trim() === "Wood")!

    await wood.trigger("click")

    expect(stopAllMock).toHaveBeenCalledWith("kendang", "synth")

    // Subsequent pad hits should use the new style.
    const dang = wrapper
      .findAll("button")
      .find((b) => b.text().includes("Dang"))!
    await dang.trigger("pointerdown")

    expect(playMock).toHaveBeenLastCalledWith("kendang", "wood", "dang")
  })
})
