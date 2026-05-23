import { describe, it, expect } from "vitest"
import { mount } from "@vue/test-utils"
import HostControls from "../activities/poker/HostControls.vue"

const base = {
  status: "voting" as const,
  deck: "fibonacci" as const,
  queue: [] as string[],
  has_votes: false,
}

describe("HostControls", () => {
  describe("primary action buttons", () => {
    it("renders Reveal during :voting", () => {
      const wrapper = mount(HostControls, { props: { ...base, status: "voting" } })
      const buttons = wrapper.findAll("button").map((b) => b.text())
      expect(buttons.some((t) => t.startsWith("Reveal"))).toBe(true)
      expect(buttons.some((t) => t.startsWith("Next round"))).toBe(false)
    })

    it("renders Re-vote + Next round during :revealed", () => {
      const wrapper = mount(HostControls, { props: { ...base, status: "revealed" } })
      const buttons = wrapper.findAll("button").map((b) => b.text())
      expect(buttons.some((t) => t.startsWith("Re-vote"))).toBe(true)
      expect(buttons.some((t) => t.startsWith("Next round"))).toBe(true)
      expect(buttons.some((t) => t.startsWith("Reveal"))).toBe(false)
    })

    it("clicking Reveal emits 'reveal'", async () => {
      const wrapper = mount(HostControls, { props: base })
      const reveal = wrapper.findAll("button").find((b) => b.text().startsWith("Reveal"))!
      await reveal.trigger("click")
      expect(wrapper.emitted("reveal")).toHaveLength(1)
    })

    it("clicking Re-vote / Next round emits the matching events", async () => {
      const wrapper = mount(HostControls, { props: { ...base, status: "revealed" } })
      const revote = wrapper.findAll("button").find((b) => b.text().startsWith("Re-vote"))!
      const next = wrapper.findAll("button").find((b) => b.text().startsWith("Next round"))!

      await revote.trigger("click")
      await next.trigger("click")

      expect(wrapper.emitted("revote")).toHaveLength(1)
      expect(wrapper.emitted("next-round")).toHaveLength(1)
    })
  })

  describe("deck picker", () => {
    it("renders all four deck options", () => {
      const wrapper = mount(HostControls, { props: base })
      const options = wrapper.findAll("option").map((o) => o.attributes("value"))
      expect(options).toEqual(["fibonacci", "modified_fibonacci", "tshirt", "pow2"])
    })

    it("disables the select when votes are in", () => {
      const wrapper = mount(HostControls, { props: { ...base, has_votes: true } })
      expect(wrapper.find("select").attributes("disabled")).toBeDefined()
      expect(wrapper.text()).toContain("Lock the round before switching decks.")
    })

    it("emits change-deck on selection", async () => {
      const wrapper = mount(HostControls, { props: base })
      await wrapper.find("select").setValue("tshirt")
      expect(wrapper.emitted("change-deck")?.[0]).toEqual(["tshirt"])
    })
  })

  describe("backlog editor", () => {
    it("renders 'No backlog loaded' summary when empty", () => {
      const wrapper = mount(HostControls, { props: { ...base, queue: [] } })
      expect(wrapper.text()).toContain("No backlog loaded")
    })

    it("shows count + plural with multiple items", () => {
      const wrapper = mount(HostControls, {
        props: { ...base, queue: ["a", "b", "c"] },
      })
      expect(wrapper.text()).toContain("3 stories queued")
    })

    it("shows singular with one item", () => {
      const wrapper = mount(HostControls, {
        props: { ...base, queue: ["only one"] },
      })
      expect(wrapper.text()).toContain("1 story queued")
    })

    it("pre-fills the textarea with the current queue (one per line)", () => {
      const wrapper = mount(HostControls, {
        props: { ...base, queue: ["one", "two", "three"] },
      })
      const ta = wrapper.find("textarea")
      expect((ta.element as HTMLTextAreaElement).value).toBe("one\ntwo\nthree")
    })

    it("Save backlog emits set-queue with newline-split lines", async () => {
      const wrapper = mount(HostControls, { props: base })
      await wrapper.find("textarea").setValue("first\nsecond\nthird")

      const save = wrapper.findAll("button").find((b) => b.text() === "Save backlog")!
      await save.trigger("click")

      expect(wrapper.emitted("set-queue")?.[0]).toEqual([["first", "second", "third"]])
    })

    it("Clear button only renders when queue is non-empty", () => {
      const empty = mount(HostControls, { props: { ...base, queue: [] } })
      expect(empty.findAll("button").map((b) => b.text())).not.toContain("Clear")

      const queued = mount(HostControls, { props: { ...base, queue: ["x"] } })
      expect(queued.findAll("button").map((b) => b.text())).toContain("Clear")
    })

    it("Clear emits set-queue with an empty list", async () => {
      const wrapper = mount(HostControls, { props: { ...base, queue: ["x", "y"] } })
      const clear = wrapper.findAll("button").find((b) => b.text() === "Clear")!
      await clear.trigger("click")
      expect(wrapper.emitted("set-queue")?.[0]).toEqual([[]])
    })
  })
})
