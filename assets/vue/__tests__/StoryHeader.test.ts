import { describe, it, expect } from "vitest"
import { mount } from "@vue/test-utils"
import StoryHeader from "../activities/poker/StoryHeader.vue"

const base = {
  story: null as string | null,
  round: 1,
  queue_length: 0,
  next_in_queue: null as string | null,
  is_host: false,
}

describe("StoryHeader", () => {
  it("shows the round number", () => {
    const wrapper = mount(StoryHeader, { props: { ...base, round: 3 } })
    expect(wrapper.text()).toContain("Round 3")
  })

  it("falls back to the placeholder when story is nil", () => {
    const wrapper = mount(StoryHeader, { props: { ...base, story: null } })
    expect(wrapper.find("h2").text()).toContain("Click to set a story")
  })

  it("renders the story value when set", () => {
    const wrapper = mount(StoryHeader, { props: { ...base, story: "Migrate auth" } })
    expect(wrapper.find("h2").text()).toContain("Migrate auth")
  })

  it("non-host gets no edit cursor + clicking does nothing", async () => {
    const wrapper = mount(StoryHeader, { props: { ...base, is_host: false, story: "X" } })
    await wrapper.find("h2").trigger("click")
    expect(wrapper.find("input").exists()).toBe(false)
  })

  it("host clicks the h2 → input appears + on Enter emits update:story", async () => {
    const wrapper = mount(StoryHeader, { props: { ...base, is_host: true, story: "Old" } })

    await wrapper.find("h2").trigger("click")
    const input = wrapper.find("input")
    expect(input.exists()).toBe(true)
    expect((input.element as HTMLInputElement).value).toBe("Old")

    await input.setValue("New title")
    await input.trigger("keydown.enter")

    expect(wrapper.emitted("update:story")?.[0]).toEqual(["New title"])
  })

  it("host pressing Escape cancels without emitting", async () => {
    const wrapper = mount(StoryHeader, { props: { ...base, is_host: true, story: "Old" } })

    await wrapper.find("h2").trigger("click")
    await wrapper.find("input").setValue("Discarded")
    await wrapper.find("input").trigger("keydown.escape")

    expect(wrapper.emitted("update:story")).toBeUndefined()
    expect(wrapper.find("input").exists()).toBe(false)
  })

  it("does not emit when the edit was a no-op (value unchanged)", async () => {
    const wrapper = mount(StoryHeader, { props: { ...base, is_host: true, story: "Same" } })

    await wrapper.find("h2").trigger("click")
    await wrapper.find("input").trigger("keydown.enter")

    expect(wrapper.emitted("update:story")).toBeUndefined()
  })

  it("trims whitespace before emitting", async () => {
    const wrapper = mount(StoryHeader, { props: { ...base, is_host: true, story: "Old" } })

    await wrapper.find("h2").trigger("click")
    await wrapper.find("input").setValue("  trimmed  ")
    await wrapper.find("input").trigger("keydown.enter")

    expect(wrapper.emitted("update:story")?.[0]).toEqual(["trimmed"])
  })

  it("shows the 'Up next' preview only when queue is non-empty", () => {
    const empty = mount(StoryHeader, { props: { ...base, queue_length: 0 } })
    expect(empty.text()).not.toContain("Up next")

    const queued = mount(StoryHeader, {
      props: { ...base, queue_length: 3, next_in_queue: "Migrate auth" },
    })
    expect(queued.text()).toContain("Up next:")
    expect(queued.text()).toContain("Migrate auth")
    expect(queued.text()).toContain("2 more queued")
  })

  it("omits the 'N more queued' suffix when only one item is in the queue", () => {
    const wrapper = mount(StoryHeader, {
      props: { ...base, queue_length: 1, next_in_queue: "Last one" },
    })
    expect(wrapper.text()).toContain("Up next:")
    expect(wrapper.text()).toContain("Last one")
    expect(wrapper.text()).not.toContain("more queued")
  })
})
