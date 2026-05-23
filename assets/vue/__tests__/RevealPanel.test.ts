import { describe, it, expect } from "vitest"
import { mount } from "@vue/test-utils"
import RevealPanel from "../activities/poker/RevealPanel.vue"

const FIB = ["1", "2", "3", "5", "8", "13", "21", "?", "☕"]
const TSHIRT = ["XS", "S", "M", "L", "XL", "?"]

const base = {
  deck: "fibonacci" as const,
  cards: FIB,
  votes: {} as Record<string, string>,
  participants: [],
}

describe("RevealPanel", () => {
  it("shows the 'no votes' empty state when nobody voted", () => {
    const wrapper = mount(RevealPanel, { props: base })
    expect(wrapper.text()).toContain("No votes were cast")
  })

  describe("verdict headline", () => {
    it("renders Consensus when everyone agrees", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "5", b: "5", c: "5" } },
      })
      expect(wrapper.text()).toContain("Consensus: 5")
    })

    it("renders Close call for adjacent deck values", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "5", b: "8" } },
      })
      expect(wrapper.text()).toContain("Close call")
      expect(wrapper.text()).toContain("5")
      expect(wrapper.text()).toContain("8")
    })

    it("renders 'Wide range — discuss' for spread votes", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "3", b: "13" } },
      })
      expect(wrapper.text()).toContain("Wide range")
      expect(wrapper.text()).toContain("discuss")
    })

    it("renders 'One vote in' for a single voter", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "8" } },
      })
      expect(wrapper.text()).toContain("One vote in: 8")
    })

    it("calls out 'Everyone wants clarification' when all picked ?", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "?", b: "?" } },
      })
      expect(wrapper.text()).toContain("Everyone wants clarification")
    })

    it("calls out 'Time for a break' when all picked ☕", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "☕", b: "☕" } },
      })
      expect(wrapper.text()).toContain("Time for a break")
    })
  })

  describe("distribution + stats", () => {
    it("renders one bar per unique vote value", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "5", b: "5", c: "8" } },
      })
      const rows = wrapper.findAll("ul li")
      expect(rows).toHaveLength(2)
    })

    it("shows Average + Median for numeric decks", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "5", b: "8" } },
      })
      const text = wrapper.text()
      expect(text).toContain("Average:")
      expect(text).toContain("Median:")
    })

    it("computes average correctly with non-integer result", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "5", b: "8" } },
      })
      // (5+8)/2 = 6.5
      expect(wrapper.text()).toContain("6.5")
    })

    it("excludes ?/☕ from numeric stats", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, votes: { a: "5", b: "5", c: "?" } },
      })
      // Average is just over the numeric values: (5+5)/2 = 5
      expect(wrapper.text()).toMatch(/Average:\s*5/)
    })

    it("t-shirt deck gets Mode only — no Average / Median", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, deck: "tshirt", cards: TSHIRT, votes: { a: "M", b: "L", c: "M" } },
      })
      const text = wrapper.text()
      expect(text).not.toContain("Average:")
      expect(text).not.toContain("Median:")
      expect(text).toContain("Mode:")
    })

    it("Mode is the most-frequent value", () => {
      const wrapper = mount(RevealPanel, {
        props: { ...base, deck: "tshirt", cards: TSHIRT, votes: { a: "M", b: "L", c: "M" } },
      })
      // Distribution sorts mode (M, count 2) first
      expect(wrapper.text()).toMatch(/Mode:\s*M/)
    })
  })
})
