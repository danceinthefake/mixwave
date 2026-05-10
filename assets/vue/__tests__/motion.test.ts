import { describe, it, expect } from "vitest"

import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "@/lib/motion"

describe("motion tokens", () => {
  it("FLASH_MS exposes tight / medium / long durations", () => {
    expect(FLASH_MS.tight).toBeGreaterThan(0)
    expect(FLASH_MS.medium).toBeGreaterThan(FLASH_MS.tight)
    expect(FLASH_MS.long).toBeGreaterThan(FLASH_MS.medium)
  })

  it("REMOTE_FLASH_DELTA_MS is non-zero so remote flashes outlive local ones", () => {
    expect(REMOTE_FLASH_DELTA_MS).toBeGreaterThan(0)
  })
})
