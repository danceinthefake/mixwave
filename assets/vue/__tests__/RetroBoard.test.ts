import { describe, it, expect, vi, afterEach } from "vitest"

const { pushEventMock } = vi.hoisted(() => ({
  pushEventMock: vi.fn(),
}))

vi.mock("live_vue", () => ({
  useLiveVue: () => ({ pushEvent: pushEventMock }),
}))

import { mount, enableAutoUnmount } from "@vue/test-utils"
import RetroBoard from "../activities/retro/RetroBoard.vue"
import type { RetroSession } from "../activities/retro/RetroBoard.vue"

enableAutoUnmount(afterEach)

function makeSession(overrides: Partial<RetroSession> = {}): RetroSession {
  return {
    id: "s1",
    title: null,
    status: "setup",
    voting_enabled: false,
    columns: [
      { id: "c1", name: "Good", position: 0 },
      { id: "c2", name: "Bad", position: 1 },
      { id: "c3", name: "Start", position: 2 },
      { id: "c4", name: "Thanks", position: 3 },
    ],
    cards: [],
    action_items: [],
    ...overrides,
  }
}

const baseProps = {
  chamber_slug: "abc",
  session: null as RetroSession | null,
  tallies: {},
  my_votes: [],
  current_user_id: "u1",
  current_user_alias: "host-alias",
  is_host: true,
}

describe("RetroBoard", () => {
  afterEach(() => {
    pushEventMock.mockReset()
  })

  it("shows 'Start retro' button for host with no session", () => {
    const w = mount(RetroBoard, { props: { ...baseProps, session: null } })
    const btn = w.get("button")
    expect(btn.text()).toBe("Start retro")
    btn.trigger("click")
    expect(pushEventMock).toHaveBeenCalledWith("retro_start_session", {})
  })

  it("shows 'Waiting for the host' message for non-host with no session", () => {
    const w = mount(RetroBoard, { props: { ...baseProps, session: null, is_host: false } })
    expect(w.text()).toContain("Waiting for the host")
  })

  it("renders RetroSetup during :setup phase", () => {
    const w = mount(RetroBoard, { props: { ...baseProps, session: makeSession() } })
    expect(w.text()).toContain("Column names")
  })

  it("renders 4 columns during :brainstorm", () => {
    const session = makeSession({ status: "brainstorm" })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const columnHeaders = w.findAll("h2")
    // 1 header in main h1 + 4 column headers = 5; filter to column headers only
    const columnNames = columnHeaders.filter((h) =>
      ["Good", "Bad", "Start", "Thanks"].includes(h.text()),
    )
    expect(columnNames.length).toBe(4)
  })

  it("renders face-down placeholders for hidden cards during :brainstorm", () => {
    const session = makeSession({
      status: "brainstorm",
      cards: [
        {
          id: "card-mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
        },
        {
          id: "card-theirs-1",
          retro_column_id: "c1",
          body: "their card 1",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
        },
        {
          id: "card-theirs-2",
          retro_column_id: "c1",
          body: "their card 2",
          author_user_id: "u3",
          author_alias: "other",
          vote_count: 0,
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    // 1 real card (mine) + 2 face-down silhouettes (theirs)
    const placeholders = w.findAll(
      "[aria-label='Hidden card from another participant — reveals together']",
    )
    expect(placeholders.length).toBe(2)
    expect(w.text()).toContain("my card")
    expect(w.text()).not.toContain("their card 1")
  })

  it("no placeholders outside :brainstorm even when others have cards", () => {
    const session = makeSession({
      status: "reveal",
      cards: [
        {
          id: "card-theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const placeholders = w.findAll(
      "[aria-label='Hidden card from another participant — reveals together']",
    )
    expect(placeholders.length).toBe(0)
    // their card is now visible
    expect(w.text()).toContain("their card")
  })

  it("hides others' cards during :brainstorm but counts them", () => {
    const session = makeSession({
      status: "brainstorm",
      cards: [
        {
          id: "card-mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
        },
        {
          id: "card-theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("my card")
    expect(w.text()).not.toContain("their card")
    // Total count badge shows 2
    expect(w.html()).toContain(">2<")
  })

  it("shows all cards during :reveal", () => {
    const session = makeSession({
      status: "reveal",
      cards: [
        {
          id: "card-mine",
          retro_column_id: "c1",
          body: "my card",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 0,
        },
        {
          id: "card-theirs",
          retro_column_id: "c1",
          body: "their card",
          author_user_id: "u2",
          author_alias: "them",
          vote_count: 0,
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("my card")
    expect(w.text()).toContain("their card")
  })

  it("renders RetroVotingPanel during :voting", () => {
    const session = makeSession({ status: "voting", voting_enabled: true })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("0/3 votes spent")
  })

  it("renders RetroDiscussPanel during :discuss", () => {
    const session = makeSession({ status: "discuss" })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    expect(w.text()).toContain("Action items")
  })

  it("sorts cards by vote_count desc in :discuss", () => {
    const session = makeSession({
      status: "discuss",
      cards: [
        {
          id: "low",
          retro_column_id: "c1",
          body: "low priority",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 1,
        },
        {
          id: "high",
          retro_column_id: "c1",
          body: "high priority",
          author_user_id: "u1",
          author_alias: "me",
          vote_count: 5,
        },
      ],
    })
    const w = mount(RetroBoard, { props: { ...baseProps, session } })
    const html = w.html()
    expect(html.indexOf("high priority")).toBeLessThan(html.indexOf("low priority"))
  })
})
