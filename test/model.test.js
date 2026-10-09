"use strict"

// Unit tests for Model.js, the widget's pure formatting layer. Run with
// `node --test test/model.test.js`, or through test/run.sh.
//
// Model.js is loaded by QML with `import "Model.js" as Model`, so it is plain
// top-level function declarations rather than a module: evaluate it in a fresh
// VM context and pull the functions off that context.

const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const modelPath = path.join(__dirname, "..", "Model.js")
const context = vm.createContext({})
vm.runInContext(fs.readFileSync(modelPath, "utf8"), context, { filename: modelPath })

const { safeParse, kickoffClock, minutesUntil, dayLabel, barLabel, eventHeadline } = context

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// kickoffClock() and dayLabel() work in local time, so expectations are built
// from local Date parts and converted to ISO rather than written as UTC text.
function localIso(daysFromToday, hours, minutes = 0) {
  const now = new Date()
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysFromToday, hours, minutes, 0).toISOString()
}

test("dayLabel: today is not prefixed", () => {
  assert.equal(dayLabel(localIso(0, 12)), "")
})

test("dayLabel: tomorrow and later fixtures get a relative day", () => {
  assert.equal(dayLabel(localIso(1, 17)), "Tomorrow ")
  const inThreeDays = localIso(3, 17)
  assert.equal(dayLabel(inThreeDays), WEEKDAYS[new Date(inThreeDays).getDay()] + " ")
})

test("dayLabel: unusable kickoffs produce no prefix", () => {
  assert.equal(dayLabel(""), "")
  assert.equal(dayLabel(undefined), "")
  assert.equal(dayLabel("not a date"), "")
})

test("barLabel: a match tomorrow is distinguishable from one today", () => {
  assert.equal(barLabel({ next_match: { team: "Viking", kickoff: localIso(1, 17) } }), "Viking Tomorrow 17:00")
})

test("barLabel: a kickoff inside 15 minutes announces the kickoff", () => {
  const soon = new Date(Date.now() + 10 * 60 * 1000).toISOString()
  assert.equal(barLabel({ next_match: { team: "Viking", kickoff: soon } }), "Kickoff " + kickoffClock(soon))
})

test("barLabel: a live match shows the score and minute", () => {
  assert.equal(
    barLabel({ live_match: { team: "Brann", team_score: 2, opponent_score: 1, elapsed: 67 } }),
    "Brann 2-1 67'",
  )
})

test("barLabel: nothing to show yields an empty label", () => {
  assert.equal(barLabel({}), "")
})

test("kickoffClock: zero-padded local time, empty for bad input", () => {
  assert.equal(kickoffClock(localIso(2, 9, 5)), "09:05")
  assert.equal(kickoffClock(""), "")
  assert.equal(kickoffClock("nope"), "")
})

test("minutesUntil: null for unusable input", () => {
  assert.equal(minutesUntil(null), null)
  assert.equal(minutesUntil("nope"), null)
})

test("eventHeadline: names the event type", () => {
  assert.equal(eventHeadline({ type: "Goal" }), "Goal")
  assert.equal(eventHeadline({ type: "Goal", detail: "Own Goal" }), "Own goal")
  assert.equal(eventHeadline({ type: "Card", detail: "Yellow Card" }), "Yellow Card")
  assert.equal(eventHeadline({ type: "subst" }), "Substitution")
  assert.equal(eventHeadline({}), "Event")
})

test("safeParse: only JSON objects survive", () => {
  // Safe to compare as text: safeParse runs inside the VM context, so its
  // objects come from that realm's Object.prototype and deepEqual's
  // prototype check would reject them.
  assert.equal(JSON.stringify(safeParse('{"a":1}')), '{"a":1}')
  assert.equal(JSON.stringify(safeParse("null")), "{}")
  assert.equal(JSON.stringify(safeParse("nope")), "{}")
  assert.equal(JSON.stringify(safeParse("")), "{}")
})
