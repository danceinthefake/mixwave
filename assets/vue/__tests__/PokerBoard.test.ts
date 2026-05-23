import { describe, it, expect, vi, beforeEach } from "vitest"

// Mocks must be defined before importing the component under test.
const { pushEventMock, playRevealMock } = vi.hoisted(() => ({
  pushEventMock: vi.fn(),
  playRevealMock: vi.fn(),
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

vi.mock("../lib/audio", () => ({
  playReveal: playRevealMock,
}))

import { mount, flushPromises, enableAutoUnmount } from "@vue/test-utils"
import { nextTick } from "vue"
import { afterEach } from "vitest"

// Unmount every mounted component after each test so window-level
// keydown listeners from previous PokerBoards don't bleed into the
// next test (the keyboard-shortcut handler attaches on the window).
enableAutoUnmount(afterEach)
import PokerBoard from "../activities/poker/PokerBoard.vue"

const FIB = ["1", "2", "3", "5", "8", "13", "21", "?", "☕"]

const baseSession = {
  status: "voting" as const,
  deck: "fibonacci" as const,
  cards: FIB,
  story: null as string | null,
  round: 1,
  my_vote: null as string | null,
  voted_user_ids: [] as string[],
  votes: {} as Record<string, string>,
  history: [],
  queue: [] as string[],
}

const u1 = { user_id: "u1", display_name: "alice-droll-01", alias: null }
const u2 = { user_id: "u2", display_name: "beto-bandel-02", alias: null }

const baseProps = {
  chamber_slug: "abc123",
  chamber_title: null,
  poker_session: baseSession,
  poker_participants: [u1, u2],
  current_user_id: "u1",
  is_host: true,
}

beforeEach(() => {
  pushEventMock.mockClear()
  playRevealMock.mockClear()
})

describe("PokerBoard", () => {
  describe("vote casting", () => {
    it("clicking a card pushes poker_vote with the card", async () => {
      const wrapper = mount(PokerBoard, { props: baseProps })

      const cardButtons = wrapper
        .findAll("button")
        .filter((b) => /^[0-9?☕]/.test(b.text().trim()))
      await cardButtons[0].trigger("click")

      expect(pushEventMock).toHaveBeenCalledWith("poker_vote", { card: "1" })
    })

    it("clicking the same card again withdraws (poker_withdraw_vote)", async () => {
      const wrapper = mount(PokerBoard, {
        props: { ...baseProps, poker_session: { ...baseSession, my_vote: "5" } },
      })

      const five = wrapper.findAll("button").find((b) => b.text().trim().startsWith("5"))!
      await five.trigger("click")

      expect(pushEventMock).toHaveBeenCalledWith("poker_withdraw_vote", {})
    })

    it("does not push during :revealed status", async () => {
      const wrapper = mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: { ...baseSession, status: "revealed", flipped: true },
        },
      })
      // CardDeck isn't rendered during revealed — no cards to click.
      const cardButtons = wrapper
        .findAll("button")
        .filter((b) => /^[0-9?☕]/.test(b.text().trim()))
      expect(cardButtons).toHaveLength(0)
    })
  })

  describe("host actions emitted via pushEvent", () => {
    it("Reveal click pushes poker_reveal", async () => {
      const wrapper = mount(PokerBoard, { props: baseProps })
      const reveal = wrapper.findAll("button").find((b) => b.text().startsWith("Reveal"))!
      await reveal.trigger("click")
      expect(pushEventMock).toHaveBeenCalledWith("poker_reveal", {})
    })

    it("non-host clicking Reveal would no-op — but HostControls is hidden", () => {
      const wrapper = mount(PokerBoard, { props: { ...baseProps, is_host: false } })
      const reveal = wrapper.findAll("button").find((b) => b.text().startsWith("Reveal"))
      expect(reveal).toBeUndefined()
    })

    it("Re-vote + Next round emit during :revealed", async () => {
      const wrapper = mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: { ...baseSession, status: "revealed" },
        },
      })

      const revote = wrapper.findAll("button").find((b) => b.text().startsWith("Re-vote"))!
      await revote.trigger("click")
      expect(pushEventMock).toHaveBeenCalledWith("poker_revote", {})

      const next = wrapper.findAll("button").find((b) => b.text().startsWith("Next round"))!
      await next.trigger("click")
      expect(pushEventMock).toHaveBeenCalledWith("poker_next_round", {})
    })

    it("Save backlog pushes poker_set_queue with the textarea lines", async () => {
      const wrapper = mount(PokerBoard, { props: baseProps })
      await wrapper.find("textarea").setValue("one\ntwo")
      const save = wrapper.findAll("button").find((b) => b.text() === "Save backlog")!
      await save.trigger("click")
      expect(pushEventMock).toHaveBeenCalledWith("poker_set_queue", { queue: ["one", "two"] })
    })
  })

  describe("reveal moment", () => {
    it("flips immediately when mounted in :revealed (late joiner)", async () => {
      const wrapper = mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: {
            ...baseSession,
            status: "revealed",
            voted_user_ids: ["u1"],
            votes: { u1: "5" },
          },
        },
      })

      await nextTick()
      // is-revealed should be on the (only voted) silhouette.
      expect(wrapper.findAll(".is-revealed")).toHaveLength(1)
      // No chime since the user wasn't here for the transition.
      expect(playRevealMock).not.toHaveBeenCalled()
    })

    it("plays the chime + lags the flip when status transitions voting → revealed",
      async () => {
        vi.useFakeTimers()
        const wrapper = mount(PokerBoard, { props: baseProps })

        // Transition to revealed.
        await wrapper.setProps({
          poker_session: {
            ...baseSession,
            status: "revealed",
            voted_user_ids: ["u1"],
            votes: { u1: "5" },
          },
        })

        // Chime fires immediately, flip is still pending.
        expect(playRevealMock).toHaveBeenCalledOnce()
        expect(wrapper.findAll(".is-revealed")).toHaveLength(0)

        // Advance past the suspense.
        vi.advanceTimersByTime(900)
        await wrapper.vm.$nextTick()
        expect(wrapper.findAll(".is-revealed")).toHaveLength(1)

        vi.useRealTimers()
      })

    it("resets flipped when status transitions back to :voting", async () => {
      const wrapper = mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: {
            ...baseSession,
            status: "revealed",
            voted_user_ids: ["u1"],
            votes: { u1: "5" },
          },
        },
      })
      await nextTick()
      expect(wrapper.findAll(".is-revealed")).toHaveLength(1)

      await wrapper.setProps({
        poker_session: { ...baseSession, status: "voting" },
      })
      await nextTick()

      expect(wrapper.findAll(".is-revealed")).toHaveLength(0)
    })
  })

  describe("keyboard shortcuts", () => {
    it("number key 4 votes the 4th deck card (Fibonacci index 3 = '5')", async () => {
      mount(PokerBoard, { props: baseProps, attachTo: document.body })

      const evt = new KeyboardEvent("keydown", { key: "4" })
      window.dispatchEvent(evt)
      await flushPromises()

      expect(pushEventMock).toHaveBeenCalledWith("poker_vote", { card: "5" })
    })

    it("Escape during :voting withdraws when there's an active vote", async () => {
      mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: { ...baseSession, my_vote: "5" },
        },
        attachTo: document.body,
      })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }))
      await flushPromises()

      expect(pushEventMock).toHaveBeenCalledWith("poker_withdraw_vote", {})
    })

    it("R (lowercase) reveals when host + voting", async () => {
      mount(PokerBoard, { props: baseProps, attachTo: document.body })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "r" }))
      await flushPromises()

      expect(pushEventMock).toHaveBeenCalledWith("poker_reveal", {})
    })

    it("N during :revealed (host) advances", async () => {
      mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: { ...baseSession, status: "revealed" },
        },
        attachTo: document.body,
      })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "n" }))
      await flushPromises()

      expect(pushEventMock).toHaveBeenCalledWith("poker_next_round", {})
    })

    it("E during :revealed (host) re-votes", async () => {
      mount(PokerBoard, {
        props: {
          ...baseProps,
          poker_session: { ...baseSession, status: "revealed" },
        },
        attachTo: document.body,
      })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "e" }))
      await flushPromises()

      expect(pushEventMock).toHaveBeenCalledWith("poker_revote", {})
    })

    it("Ctrl/Cmd-key combos are ignored (don't steal browser shortcuts)", async () => {
      mount(PokerBoard, { props: baseProps, attachTo: document.body })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "r", ctrlKey: true }))
      window.dispatchEvent(new KeyboardEvent("keydown", { key: "4", metaKey: true }))
      await flushPromises()

      expect(pushEventMock).not.toHaveBeenCalled()
    })

    it("auto-repeat events are ignored", async () => {
      mount(PokerBoard, { props: baseProps, attachTo: document.body })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "4", repeat: true }))
      await flushPromises()

      expect(pushEventMock).not.toHaveBeenCalled()
    })

    it("non-host's R press is a no-op", async () => {
      mount(PokerBoard, {
        props: { ...baseProps, is_host: false },
        attachTo: document.body,
      })

      window.dispatchEvent(new KeyboardEvent("keydown", { key: "r" }))
      await flushPromises()

      expect(pushEventMock).not.toHaveBeenCalled()
    })
  })

  describe("empty state", () => {
    it("shows the waiting-for-team hint when alone + fresh", () => {
      const wrapper = mount(PokerBoard, {
        props: { ...baseProps, poker_participants: [u1] },
      })
      expect(wrapper.text()).toContain("Waiting for the team")
    })

    it("hides the waiting hint once a second participant joins", () => {
      const wrapper = mount(PokerBoard, { props: baseProps })
      expect(wrapper.text()).not.toContain("Waiting for the team")
    })
  })
})
