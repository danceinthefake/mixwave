import { describe, it, expect } from "vitest"
import { cn, isTypingInForm } from "../lib/utils"

describe("cn", () => {
  it("merges plain strings", () => {
    expect(cn("px-2", "py-1")).toBe("px-2 py-1")
  })

  it("resolves Tailwind conflicts in favour of the last value", () => {
    // tailwind-merge collapses px-2 + px-4 to just px-4
    expect(cn("px-2", "px-4")).toBe("px-4")
  })

  it("drops falsy values via clsx semantics", () => {
    expect(cn("a", false && "b", null, undefined, "c")).toBe("a c")
  })
})

describe("isTypingInForm", () => {
  // Build a fake KeyboardEvent-ish shape — only `target` is read.
  function evt(target: HTMLElement | null): KeyboardEvent {
    return { target } as unknown as KeyboardEvent
  }

  it("returns false when there's no target", () => {
    expect(isTypingInForm(evt(null))).toBe(false)
  })

  it("returns true for INPUT, TEXTAREA, SELECT", () => {
    expect(isTypingInForm(evt(document.createElement("input")))).toBe(true)
    expect(isTypingInForm(evt(document.createElement("textarea")))).toBe(true)
    expect(isTypingInForm(evt(document.createElement("select")))).toBe(true)
  })

  it("returns false for non-form elements", () => {
    expect(isTypingInForm(evt(document.createElement("button")))).toBe(false)
    expect(isTypingInForm(evt(document.createElement("div")))).toBe(false)
  })

  it("returns true for contenteditable elements", () => {
    const div = document.createElement("div")
    div.contentEditable = "true"
    expect(isTypingInForm(evt(div))).toBe(true)
  })
})
