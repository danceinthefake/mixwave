import { describe, it, expect, vi, afterEach } from "vitest"

const { pushEventMock } = vi.hoisted(() => ({
  pushEventMock: vi.fn(),
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import { mount, enableAutoUnmount } from "@vue/test-utils"
import RetroCard from "../activities/retro/RetroCard.vue"
import type { RetroCard as RetroCardT } from "../activities/retro/RetroBoard.vue"

enableAutoUnmount(afterEach)

function baseCard(overrides: Partial<RetroCardT> = {}): RetroCardT {
  return {
    id: "card1",
    retro_column_id: "c1",
    body: "Pairing helped",
    author_user_id: "u1",
    author_alias: "host-alias",
    author_display_name: null,
    vote_count: 0,
    reactions: [],
    comments: [],
    ...overrides,
  }
}

const baseProps = {
  card: baseCard(),
  phase: "brainstorm" as const,
  brainstorm_visible: false,
  is_mine: true,
  current_user_id: "u1",
  tally: 0,
  is_my_vote: false,
  votes_remaining: 3,
  is_host: false,
  is_discussing: false,
  tied_actions: [],
}

describe("RetroCard", () => {
  afterEach(() => {
    pushEventMock.mockReset()
  })

  it("renders card body + author", () => {
    const w = mount(RetroCard, { props: baseProps })
    expect(w.text()).toContain("Pairing helped")
    expect(w.text()).toContain("host-alias")
  })

  it("renders both alias and display_name in two-piece pattern when both present", () => {
    const w = mount(RetroCard, {
      props: {
        ...baseProps,
        card: baseCard({
          author_alias: "alex",
          author_display_name: "Brave Otter 12",
        }),
      },
    })
    expect(w.text()).toContain("alex")
    expect(w.text()).toContain("Brave Otter 12")
    expect(w.text()).toContain("·")
  })

  it("renders single label when alias and display_name are the same", () => {
    // Anon user with no alias set: alias_or_name snapshot fell
    // back to display_name, so both fields hold the same value.
    // No "· …" tail in that case.
    const w = mount(RetroCard, {
      props: {
        ...baseProps,
        card: baseCard({
          author_alias: "Brave Otter 12",
          author_display_name: "Brave Otter 12",
        }),
      },
    })
    const text = w.text()
    expect(text).toContain("Brave Otter 12")
    expect(text.match(/Brave Otter 12/g)?.length).toBe(1)
  })

  it("renders single label when author_display_name is null (legacy card)", () => {
    const w = mount(RetroCard, {
      props: {
        ...baseProps,
        card: baseCard({
          author_alias: "host-alias",
          author_display_name: null,
        }),
      },
    })
    expect(w.text()).toContain("host-alias")
    // No "· " separator
    expect(w.text()).not.toContain(" · ")
  })

  it("vote button visible only in :voting", () => {
    for (const phase of ["brainstorm", "reveal", "discuss", "archived"] as const) {
      const w = mount(RetroCard, { props: { ...baseProps, phase } })
      expect(w.find("[aria-label*='Vote']").exists()).toBe(false)
      expect(w.find("[aria-label*='Withdraw']").exists()).toBe(false)
    }
    const w = mount(RetroCard, { props: { ...baseProps, phase: "voting" } })
    expect(w.find("[aria-label='Vote for this card']").exists()).toBe(true)
  })

  it("pushes retro_vote on click when not voted", async () => {
    const w = mount(RetroCard, { props: { ...baseProps, phase: "voting" } })
    await w.get("[aria-label='Vote for this card']").trigger("click")
    expect(pushEventMock).toHaveBeenCalledWith("retro_vote", { card_id: "card1" })
  })

  it("pushes retro_withdraw_vote when already voted", async () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "voting", is_my_vote: true },
    })
    await w.get("[aria-label='Withdraw vote']").trigger("click")
    expect(pushEventMock).toHaveBeenCalledWith("retro_withdraw_vote", { card_id: "card1" })
  })

  it("vote button disabled at cap when not yet voted on this card", () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "voting", votes_remaining: 0, is_my_vote: false },
    })
    const btn = w.get("[aria-label='Vote for this card']")
    expect(btn.attributes("disabled")).toBeDefined()
  })

  it("vote button still enabled at cap if this card is already mine (to allow unvote)", () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "voting", votes_remaining: 0, is_my_vote: true },
    })
    const btn = w.get("[aria-label='Withdraw vote']")
    expect(btn.attributes("disabled")).toBeUndefined()
  })

  it("edit/delete affordances appear only on :brainstorm + own card", () => {
    const own = mount(RetroCard, { props: { ...baseProps, phase: "brainstorm", is_mine: true } })
    expect(own.find("button[aria-label='Edit card']").exists()).toBe(true)
    expect(own.find("button[aria-label='Delete card']").exists()).toBe(true)

    const theirs = mount(RetroCard, {
      props: { ...baseProps, phase: "brainstorm", is_mine: false },
    })
    expect(theirs.find("button[aria-label='Edit card']").exists()).toBe(false)

    const reveal = mount(RetroCard, { props: { ...baseProps, phase: "reveal", is_mine: true } })
    expect(reveal.find("button[aria-label='Edit card']").exists()).toBe(false)
  })

  it("discussing card gets a highlight ring", () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "discuss", is_discussing: true },
    })
    expect(w.find("article").classes()).toContain("ring-2")
    expect(w.find("article").classes()).toContain("ring-accent-bass")
  })

  it("non-discussing card has no highlight ring", () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "discuss", is_discussing: false },
    })
    expect(w.find("article").classes()).not.toContain("ring-2")
  })

  it("host click in :discuss pushes retro_set_discussing", async () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "discuss", is_host: true },
    })
    await w.get("article").trigger("click")
    expect(pushEventMock).toHaveBeenCalledWith("retro_set_discussing", { card_id: "card1" })
  })

  it("non-host click in :discuss does nothing", async () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "discuss", is_host: false },
    })
    await w.get("article").trigger("click")
    expect(pushEventMock).not.toHaveBeenCalled()
  })

  it("renders tied action items nested below card body during :discuss", () => {
    const w = mount(RetroCard, {
      props: {
        ...baseProps,
        phase: "discuss",
        tied_actions: [
          {
            id: "a1",
            source_card_id: "card1",
            body: "Investigate the flaky test",
            assignee_alias: "alex",
            due_date: null,
            completed: false,
          },
        ],
      },
    })
    expect(w.text()).toContain("Investigate the flaky test")
    expect(w.text()).toContain("@alex")
  })

  it("no nested actions section in :brainstorm even if tied_actions provided", () => {
    // tied_actions only renders during :discuss / :archived.
    const w = mount(RetroCard, {
      props: {
        ...baseProps,
        phase: "brainstorm",
        tied_actions: [
          {
            id: "a1",
            source_card_id: "card1",
            body: "Should not appear",
            assignee_alias: null,
            due_date: null,
            completed: false,
          },
        ],
      },
    })
    expect(w.text()).not.toContain("Should not appear")
  })

  it("static count chip appears in :discuss when tally > 0", () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "discuss", tally: 5 },
    })
    // Chip text contains the count + a bullet — assert on the count alone.
    expect(w.text()).toContain("5")
    expect(w.find("span.tabular-nums").exists()).toBe(true)
  })

  it("static count chip hidden when tally is 0", () => {
    const w = mount(RetroCard, {
      props: { ...baseProps, phase: "discuss", tally: 0 },
    })
    // No tabular-numbered span for the vote chip — the reaction
    // strip's emoji counts only render when count > 0, so with
    // a clean baseProps card the only tabular-nums element
    // would be the vote chip if it existed. Asserting on its
    // absence directly avoids tangling with reaction-strip
    // buttons that also live on the card.
    expect(w.findAll("span.tabular-nums").length).toBe(0)
  })
})
