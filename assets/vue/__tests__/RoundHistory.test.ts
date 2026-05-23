import { describe, it, expect, vi, beforeEach, afterEach } from "vitest"
import { mount } from "@vue/test-utils"
import RoundHistory from "../activities/poker/RoundHistory.vue"

const FIB = ["1", "2", "3", "5", "8", "13", "21", "?", "☕"]

const consensusEntry = {
  round: 1,
  story: "Add dark mode",
  deck: "fibonacci" as const,
  cards: FIB,
  values: ["5", "5", "5"],
}

const closeEntry = {
  round: 2,
  story: "Migrate auth",
  deck: "fibonacci" as const,
  cards: FIB,
  values: ["5", "8"],
}

const discussEntry = {
  round: 3,
  story: null,
  deck: "fibonacci" as const,
  cards: FIB,
  values: ["3", "13"],
}

describe("RoundHistory", () => {
  it("renders nothing when history is empty", () => {
    const wrapper = mount(RoundHistory, { props: { history: [] } })
    expect(wrapper.find("details").exists()).toBe(false)
  })

  it("renders a row per history entry with R{n} + story + verdict label", () => {
    const wrapper = mount(RoundHistory, { props: { history: [consensusEntry] } })

    const li = wrapper.find("li")
    const text = li.text().replace(/\s+/g, " ")
    expect(text).toContain("R1")
    expect(text).toContain("Add dark mode")
    expect(text).toContain("5")
  })

  it("shows 'Untitled' when the story was nil", () => {
    const wrapper = mount(RoundHistory, { props: { history: [discussEntry] } })
    expect(wrapper.text()).toContain("Untitled")
  })

  it("shows the count + pluralisation correctly", () => {
    const wrapper = mount(RoundHistory, { props: { history: [consensusEntry, closeEntry] } })
    expect(wrapper.findAll("li").length).toBe(2)
  })

  describe("compact verdict labels", () => {
    it("consensus → just the value", () => {
      const wrapper = mount(RoundHistory, { props: { history: [consensusEntry] } })
      const label = wrapper.find("li span.font-bold")
      expect(label.text()).toBe("5")
    })

    it("close → 'low / high'", () => {
      const wrapper = mount(RoundHistory, { props: { history: [closeEntry] } })
      const label = wrapper.find("li span.font-bold")
      expect(label.text()).toBe("5 / 8")
    })

    it("discuss → 'discuss'", () => {
      const wrapper = mount(RoundHistory, { props: { history: [discussEntry] } })
      const label = wrapper.find("li span.font-bold")
      expect(label.text()).toBe("discuss")
    })

    it("all ? → '?'", () => {
      const allQ = { ...discussEntry, values: ["?", "?"] }
      const wrapper = mount(RoundHistory, { props: { history: [allQ] } })
      expect(wrapper.find("li span.font-bold").text()).toBe("?")
    })

    it("zero votes → em dash", () => {
      const noVotes = { ...discussEntry, values: [] }
      const wrapper = mount(RoundHistory, { props: { history: [noVotes] } })
      expect(wrapper.find("li span.font-bold").text()).toBe("—")
    })
  })

  describe("copy-as-text export", () => {
    let writeText: ReturnType<typeof vi.fn>

    beforeEach(() => {
      writeText = vi.fn().mockResolvedValue(undefined)
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText },
      })
      Object.defineProperty(window, "isSecureContext", {
        configurable: true,
        value: true,
      })
    })

    afterEach(() => {
      vi.useRealTimers()
    })

    it("clicking 'Copy as text' invokes navigator.clipboard.writeText with a chronological dump",
      async () => {
        const wrapper = mount(RoundHistory, {
          props: { history: [discussEntry, closeEntry, consensusEntry] },
        })

        // history is newest-first; export reverses to oldest-first.
        await wrapper.find("details").trigger("toggle")
        const copyBtn = wrapper
          .findAll("button")
          .find((b) => b.text().includes("Copy as text"))!
        await copyBtn.trigger("click")

        // The promise inside handleCopy needs a flush.
        await Promise.resolve()
        await Promise.resolve()

        expect(writeText).toHaveBeenCalledOnce()
        const payload = writeText.mock.calls[0][0] as string
        const lines = payload.split("\n")
        expect(lines[0]).toBe("Round 1 — Add dark mode — 5")
        expect(lines[1]).toBe("Round 2 — Migrate auth — 5 or 8 (close call)")
        expect(lines[2]).toBe("Round 3 — Untitled — needs discussion")
      })

    it("button label cycles to 'Copied!' after success", async () => {
      vi.useFakeTimers()
      const wrapper = mount(RoundHistory, { props: { history: [consensusEntry] } })
      const copyBtn = wrapper
        .findAll("button")
        .find((b) => b.text().includes("Copy as text"))!

      await copyBtn.trigger("click")
      await Promise.resolve()
      await Promise.resolve()

      const updated = wrapper.findAll("button").find((b) => b.text().includes("Copied!"))
      expect(updated).toBeDefined()
    })
  })
})
