#!/bin/bash

source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const model = requireFromRoot('shell/plugins/panels/local-ai/Model.js')
const hex = h => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255, a: 1 })
const lc = (text, bg) => Math.abs(model.apca(text, bg))

// APCA-W3 reference pairs
assert(Math.abs(model.apca(hex('#000000'), hex('#ffffff')) - 106.04) < 0.1, 'local-ai apca matches black on white')
assert(Math.abs(model.apca(hex('#ffffff'), hex('#000000')) + 107.88) < 0.1, 'local-ai apca matches white on black')
assert(Math.abs(model.apca(hex('#888888'), hex('#ffffff')) - 63.06) < 0.1, 'local-ai apca matches mid gray on white')

// Every theme keeps three readable tiers of text and visible lines, on both of the panel's backgrounds
const themes = { dark: ['#ffffff', '#161616', '#a55555'], omarchy: ['#cacccc', '#101315', '#a55555'], light: ['#1a1a1a', '#f4f1ea', '#c0392b'], dim: ['#8a8a8a', '#202020', '#aa4444'] }
Object.entries(themes).forEach(([name, [ink, bg, urgent]]) => {
  const surface = Object.assign(hex(ink), { a: 0.06 })
  const t = model.tones(hex(ink), hex(bg), surface, hex(urgent))
  ;[hex(bg), model.over(surface, hex(bg))].forEach((ground, i) => {
    const on = i ? 'card' : 'panel'
    assert(lc(t.ink, ground) >= model.LC.ink - 0.5, `local-ai ${name} ink reaches Lc ${model.LC.ink} on the ${on}`)
    assert(lc(t.value, ground) >= model.LC.value - 0.5, `local-ai ${name} values reach Lc ${model.LC.value} on the ${on}`)
    assert(lc(t.label, ground) >= model.LC.label - 0.5, `local-ai ${name} labels reach Lc ${model.LC.label} on the ${on}`)
    assert(lc(t.rule, ground) >= model.LC.rule - 0.5, `local-ai ${name} rules reach Lc ${model.LC.rule} on the ${on}`)
    assert(lc(t.alert, ground) >= model.LC.alert - 0.5, `local-ai ${name} alerts reach Lc ${model.LC.alert} on the ${on}`)
  })
  assert(lc(t.ink, hex(bg)) > lc(t.value, hex(bg)) && lc(t.value, hex(bg)) > lc(t.label, hex(bg)), `local-ai ${name} tiers stay in order`)
  assert(lc(hex(bg), t.ink) >= model.LC.value, `local-ai ${name} primary button text is readable on ink`)
})

// Home: running models first, then one list of the other cards under a heading
const recipe = { id: 'q', name: 'Qwen3.8-27B', family: 'qwen', caps: {}, weights: [] }
const snap = {
  version: '1.0.0', week: 925200,
  gpus: [{ key: 'a0', name: 'Arc Pro B70', vramGb: 32 }, { key: 'a1', name: 'Arc Pro B70', vramGb: 32 }, { key: 'n0', name: 'RTX 3090', vramGb: 24 }],
  kinds: [{ hw: 'arc', name: 'Arc Pro B70', keys: ['a0', 'a1'], free: ['a1'], taken: [], recipe }, { hw: '3090', name: 'RTX 3090', keys: ['n0'], free: [], taken: ['n0'], recipe }],
  deployments: [{ id: 'd', name: 'Qwen3.8-27B', keys: ['a0'], state: 'ready', agent: 'pi', session: { all: { tokens: 10 } } }],
  unsupported: [{ n: 1, name: 'Radeon RX 6600' }],
}
const home = model.build(snap, { view: 'home' })
assertDeepEqual(home.rows.map(r => r.type), ['run', 'sec', 'free', 'busy', 'busy'], 'local-ai home lists running models, then the other cards')
assertEqual(home.rows[2].label, '1 × Arc Pro B70', 'local-ai free card row names the card only')
assert(home.rows[3].warn && !home.rows[4].warn, 'local-ai only a card held by another program is a warning')
assertDeepEqual([home.stat, home.statLabel], ['925.2K', 'this week'], 'local-ai home splits the week into value and label')
JS
