import { test, expect } from "@playwright/test"
import type { Page } from "@playwright/test"
import { openRoom, bodyText } from "./helpers"

const canvasHasInk = (p: Page) =>
  p.evaluate(() => {
    const c = document.querySelector("canvas") as HTMLCanvasElement | null
    if (!c) return false
    const d = c.getContext("2d")!.getImageData(0, 0, c.width, c.height).data
    for (let i = 0; i < d.length; i += 4)
      if (d[i] < 250 || d[i + 1] < 250 || d[i + 2] < 250) return true
    return false
  })

async function drawLine(p: Page) {
  const c = p.locator("canvas")
  await c.waitFor({ state: "visible" })
  let box = await c.boundingBox()
  for (let t = 0; t < 10 && !box; t++) {
    await p.waitForTimeout(100)
    box = await c.boundingBox()
  }
  if (!box) throw new Error("pictionary: canvas never laid out")
  const y = box.y + box.height / 2
  await p.mouse.move(box.x + box.width * 0.2, y)
  await p.mouse.down()
  for (let i = 1; i <= 8; i++)
    await p.mouse.move(box.x + box.width * (0.2 + 0.07 * i), y + Math.sin(i) * 25)
  await p.mouse.up()
  await p.waitForTimeout(300)
}

test("pictionary: draw streams, guesses score + lock out, reveal, rotate", async ({ browser }) => {
  const room = await openRoom(browser, "minigame", 3)
  const all = room.pages
  const [host] = all

  try {
    // Lobby (Pictionary pre-selected). 1 round keeps it short.
    await host.locator("select").last().selectOption("1")
    await host.getByRole("button", { name: "Start game" }).click()
    await host.waitForTimeout(700)

    // Whoever's offered word choices is the drawer.
    let drawer: Page | undefined
    for (const p of all)
      if (
        await p
          .getByText("Pick a word to draw")
          .isVisible()
          .catch(() => false)
      )
        drawer = p
    expect(drawer).toBeTruthy()
    const guessers = all.filter((p) => p !== drawer)

    const choice = drawer!.locator("text=Pick a word to draw").locator("xpath=following::button[1]")
    const word = (await choice.innerText()).trim()
    await choice.click()
    await drawer!.waitForTimeout(400)

    // Drawer sees the word; guessers don't.
    await expect(drawer!.getByText(word, { exact: false }).first()).toBeVisible()
    expect((await bodyText(guessers[0])).toLowerCase()).not.toContain(word.toLowerCase())

    // Strokes replay to both guessers.
    await drawLine(drawer!)
    await guessers[0].waitForTimeout(300)
    expect(await canvasHasInk(guessers[0])).toBe(true)
    expect(await canvasHasInk(guessers[1])).toBe(true)

    // Guesser 1 guesses right → locked out + scored.
    await guessers[0].locator('input[placeholder="Type your guess…"]').fill(word)
    await guessers[0].getByRole("button", { name: "Guess" }).click()
    await guessers[0].waitForTimeout(500)
    expect(await guessers[0].locator("input[disabled]").count()).toBeGreaterThan(0)

    // Guesser 2's feed announces it without leaking the word.
    const feed = await bodyText(guessers[1])
    expect(feed).toContain("guessed it")
    const line = feed.split("\n").find((l) => l.includes("guessed it")) ?? ""
    expect(line.toLowerCase()).not.toContain(word.toLowerCase())

    // Guesser 2 guesses → every non-drawer in → reveal; word shown to all.
    await guessers[1].locator('input[placeholder="Type your guess…"]').fill(word)
    await guessers[1].getByRole("button", { name: "Guess" }).click()
    await expect(guessers[0].getByText(word, { exact: false }).first()).toBeVisible({
      timeout: 8000,
    })

    // Next rotates the drawer.
    await host.getByRole("button", { name: "Next" }).click()
    await host.waitForTimeout(800)
    let drawer2: Page | undefined
    for (const p of all)
      if (
        await p
          .getByText("Pick a word to draw")
          .isVisible()
          .catch(() => false)
      )
        drawer2 = p
    expect(drawer2 && drawer2 !== drawer).toBeTruthy()

    expect(room.errors, room.errors.join("\n")).toEqual([])
  } finally {
    await room.close()
  }
})
