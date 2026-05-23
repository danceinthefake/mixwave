import { describe, it, expect } from "vitest"
import { computeVerdict } from "../activities/poker/verdict"

const FIB = ["1", "2", "3", "5", "8", "13", "21", "?", "☕"]
const TSHIRT = ["XS", "S", "M", "L", "XL", "?"]

describe("computeVerdict", () => {
  describe("trivial cases", () => {
    it("returns :none for zero votes", () => {
      expect(computeVerdict([], FIB)).toEqual({ kind: "none" })
    })

    it("returns :single for a single vote regardless of value", () => {
      expect(computeVerdict(["5"], FIB)).toEqual({ kind: "single", value: "5" })
      expect(computeVerdict(["?"], FIB)).toEqual({ kind: "single", value: "?" })
    })
  })

  describe("unanimous votes", () => {
    it("returns :consensus when everyone picked the same numeric card", () => {
      expect(computeVerdict(["5", "5", "5"], FIB)).toEqual({ kind: "consensus", value: "5" })
    })

    it("returns :all_question when everyone picked ?", () => {
      expect(computeVerdict(["?", "?"], FIB)).toEqual({ kind: "all_question" })
    })

    it("returns :all_coffee when everyone picked ☕", () => {
      expect(computeVerdict(["☕", "☕", "☕"], FIB)).toEqual({ kind: "all_coffee" })
    })

    it("works for t-shirt deck consensus too", () => {
      expect(computeVerdict(["M", "M", "M"], TSHIRT)).toEqual({ kind: "consensus", value: "M" })
    })
  })

  describe("mixed grading + meta votes", () => {
    it("treats ?/☕ as meta and reports consensus on the numeric majority", () => {
      // Everyone who picked a number picked 5; the ? is a meta-vote.
      expect(computeVerdict(["5", "5", "?"], FIB)).toEqual({ kind: "consensus", value: "5" })
    })

    it("returns :discuss when only ? and ☕ are present but they disagree", () => {
      expect(computeVerdict(["?", "☕"], FIB)).toEqual({ kind: "discuss" })
    })
  })

  describe("close calls (adjacent in deck order)", () => {
    it("flags 5+8 in Fibonacci as close", () => {
      expect(computeVerdict(["5", "8"], FIB)).toEqual({
        kind: "close",
        low: "5",
        high: "8",
      })
    })

    it("flags M+L in t-shirt as close", () => {
      expect(computeVerdict(["M", "L"], TSHIRT)).toEqual({
        kind: "close",
        low: "M",
        high: "L",
      })
    })

    it("strips ?/☕ before checking adjacency", () => {
      expect(computeVerdict(["5", "8", "?"], FIB)).toEqual({
        kind: "close",
        low: "5",
        high: "8",
      })
    })
  })

  describe("wide spread", () => {
    it("returns :discuss when values are more than one step apart", () => {
      expect(computeVerdict(["3", "13"], FIB)).toEqual({ kind: "discuss" })
    })

    it("returns :discuss when three values span multiple deck steps", () => {
      expect(computeVerdict(["2", "5", "13"], FIB)).toEqual({ kind: "discuss" })
    })
  })
})
