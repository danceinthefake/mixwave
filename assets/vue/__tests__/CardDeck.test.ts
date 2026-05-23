import { describe, it, expect } from "vitest"
import { mount } from "@vue/test-utils"
import CardDeck from "../activities/poker/CardDeck.vue"

const FIB = ["1", "2", "3", "5", "8", "13", "21", "?", "☕"]

describe("CardDeck", () => {
  it("renders one button per deck card with the value as label", () => {
    const wrapper = mount(CardDeck, { props: { cards: FIB, selected: null } })

    const buttons = wrapper.findAll("button")
    expect(buttons).toHaveLength(FIB.length)
    expect(buttons.map((b) => b.text().split(/\s+/)[0])).toEqual(FIB)
  })

  it("renders a kbd chip with the index+1 for the first 9 cards only", () => {
    const wrapper = mount(CardDeck, { props: { cards: FIB, selected: null } })

    const kbds = wrapper.findAll("kbd")
    expect(kbds).toHaveLength(9)
    expect(kbds.map((k) => k.text())).toEqual(["1", "2", "3", "4", "5", "6", "7", "8", "9"])
  })

  it("marks the matching card with aria-pressed when selected", () => {
    const wrapper = mount(CardDeck, { props: { cards: FIB, selected: "5" } })

    const pressed = wrapper.findAll('button[aria-pressed="true"]')
    expect(pressed).toHaveLength(1)
    expect(pressed[0].text()).toContain("5")
  })

  it("emits 'pick' with the card value on click", async () => {
    const wrapper = mount(CardDeck, { props: { cards: FIB, selected: null } })

    await wrapper.findAll("button")[2].trigger("click")
    expect(wrapper.emitted("pick")?.[0]).toEqual(["3"])
  })

  it("shows the withdraw hint only when a card is selected", () => {
    const empty = mount(CardDeck, { props: { cards: FIB, selected: null } })
    expect(empty.text()).not.toContain("Voted")

    const picked = mount(CardDeck, { props: { cards: FIB, selected: "8" } })
    expect(picked.text()).toContain("Voted")
    expect(picked.text()).toContain("8")
  })
})
