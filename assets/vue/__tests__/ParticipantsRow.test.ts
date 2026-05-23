import { describe, it, expect } from "vitest"
import { mount } from "@vue/test-utils"
import ParticipantsRow from "../activities/poker/ParticipantsRow.vue"

type P = { user_id: string; display_name: string; alias: string | null }

const alice: P = { user_id: "u1", display_name: "alice-droll-01", alias: null }
const beto: P = { user_id: "u2", display_name: "beto-bandel-02", alias: null }
const citra: P = { user_id: "u3", display_name: "citra-keren-03", alias: "Citra" }

const base = {
  participants: [alice, beto, citra],
  status: "voting" as const,
  flipped: false,
  voted_user_ids: [] as string[],
  votes: {} as Record<string, string>,
  current_user_id: "u1",
}

describe("ParticipantsRow", () => {
  describe("voted count + silhouettes", () => {
    it("shows 0 / N voted at start", () => {
      const wrapper = mount(ParticipantsRow, { props: base })
      expect(wrapper.text()).toMatch(/0\s*\/\s*3\s+voted/)
    })

    it("flips silhouettes to is-voted as users vote", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: ["u1", "u2"] },
      })
      expect(wrapper.findAll(".card-silhouette.is-voted")).toHaveLength(2)
      expect(wrapper.findAll(".card-silhouette.is-empty")).toHaveLength(1)
    })

    it("renders the alias when set, falls back to display_name", () => {
      const wrapper = mount(ParticipantsRow, { props: base })
      const text = wrapper.text()
      expect(text).toContain("alice-droll-01")
      expect(text).toContain("Citra") // alias preferred
    })

    it("tags the current user with '(you)'", () => {
      const wrapper = mount(ParticipantsRow, { props: base })
      const aliceLi = wrapper.findAll("li")[0]
      expect(aliceLi.text()).toContain("(you)")
    })
  })

  describe("waiting-on hint", () => {
    it("hides when nobody has voted", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: [] },
      })
      expect(wrapper.text()).not.toContain("Waiting on")
    })

    it("hides when everyone has voted", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: ["u1", "u2", "u3"] },
      })
      expect(wrapper.text()).not.toContain("Waiting on")
    })

    it("hides during :revealed status", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, status: "revealed", voted_user_ids: ["u1"] },
      })
      expect(wrapper.text()).not.toContain("Waiting on")
    })

    it("lists a single non-voter by name", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: ["u1", "u3"] },
      })
      expect(wrapper.text()).toContain("Waiting on beto-bandel-02")
    })

    it("lists two non-voters joined by 'and'", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: ["u1"] },
      })
      expect(wrapper.text()).toMatch(/Waiting on beto-bandel-02 and Citra/)
    })

    it("renders self as 'you' in the list", () => {
      // u1 hasn't voted but is the current user.
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: ["u2", "u3"] },
      })
      expect(wrapper.text()).toContain("Waiting on you")
    })

    it("collapses to a count past three non-voters", () => {
      const four = [
        alice,
        beto,
        citra,
        { user_id: "u4", display_name: "danu-bandel-04", alias: null },
      ]
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, participants: four, voted_user_ids: [] },
      })
      // Zero voted, so hint shouldn't show
      expect(wrapper.text()).not.toContain("Waiting on")

      const wrapper2 = mount(ParticipantsRow, {
        props: { ...base, participants: four, voted_user_ids: ["u1"] },
      })
      // Wait — 4 participants, 1 voted, 3 non-voters → still names ("you and 2 others" not used; we list all 3)
      expect(wrapper2.text()).toMatch(/Waiting on /)

      const five = [
        alice,
        beto,
        citra,
        { user_id: "u4", display_name: "danu-bandel-04", alias: null },
        { user_id: "u5", display_name: "ery-bandel-05", alias: null },
      ]
      const wrapper3 = mount(ParticipantsRow, {
        props: { ...base, participants: five, voted_user_ids: ["u1"] },
      })
      // 4 non-voters → count format
      expect(wrapper3.text()).toContain("Waiting on 4 players")
    })
  })

  describe("overdue dimming", () => {
    it("does not apply is-overdue when no votes yet", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: [] },
      })
      expect(wrapper.findAll(".is-overdue")).toHaveLength(0)
    })

    it("applies is-overdue to non-voters once someone votes", () => {
      const wrapper = mount(ParticipantsRow, {
        props: { ...base, voted_user_ids: ["u1"] },
      })
      expect(wrapper.findAll(".is-overdue")).toHaveLength(2)
    })

    it("does not apply is-overdue during :revealed", () => {
      const wrapper = mount(ParticipantsRow, {
        props: {
          ...base,
          status: "revealed",
          voted_user_ids: ["u1"],
        },
      })
      expect(wrapper.findAll(".is-overdue")).toHaveLength(0)
    })
  })

  describe("flip + reveal", () => {
    it("does not apply is-revealed when flipped is false", () => {
      const wrapper = mount(ParticipantsRow, {
        props: {
          ...base,
          status: "revealed",
          flipped: false,
          voted_user_ids: ["u1"],
          votes: { u1: "5" },
        },
      })
      expect(wrapper.findAll(".is-revealed")).toHaveLength(0)
    })

    it("applies is-revealed when flipped is true (only on voted users)", () => {
      const wrapper = mount(ParticipantsRow, {
        props: {
          ...base,
          status: "revealed",
          flipped: true,
          voted_user_ids: ["u1", "u2"],
          votes: { u1: "5", u2: "8" },
        },
      })
      expect(wrapper.findAll(".is-revealed")).toHaveLength(2)
    })

    it("renders vote values in card-front when status is revealed", () => {
      const wrapper = mount(ParticipantsRow, {
        props: {
          ...base,
          status: "revealed",
          flipped: true,
          voted_user_ids: ["u1"],
          votes: { u1: "13" },
        },
      })
      // 13 appears in the value span on the front face
      expect(wrapper.text()).toContain("13")
    })
  })
})
