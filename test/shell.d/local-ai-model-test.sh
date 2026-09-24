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

// Home: working models first, then one row per GPU; cards of one kind sit under a header with their count
const recipe = { id: 'q', name: 'Qwen3.8-27B', family: 'qwen', caps: {}, weights: [] }
const snap = {
  version: '1.0.0', week: 925200, total: 4210000,
  gpus: [{ key: 'a0', name: 'Arc Pro B70', hw: 'arc', vramGb: 32 }, { key: 'a1', name: 'Arc Pro B70', hw: 'arc', vramGb: 32 },
    { key: 'n0', name: 'RTX 3090', hw: '3090', vramGb: 24 }, { key: 'r0', name: 'Radeon RX 6600', hw: '', vramGb: 8 }],
  kinds: [{ hw: 'arc', name: 'Arc Pro B70', keys: ['a0', 'a1'], free: ['a1'], taken: [], recipe }, { hw: '3090', name: 'RTX 3090', keys: ['n0'], free: [], taken: ['n0'], recipe }],
  deployments: [{ id: 'd', name: 'Qwen3.8-27B', keys: ['a0'], state: 'ready', agent: 'pi', session: { all: { tokens: 10 } } }],
}
const home = model.build(snap, { view: 'home' })
assertDeepEqual(home.rows.map(r => r.type), ['run', 'sec', 'slot', 'slot', 'slot', 'slot'], 'local-ai home lists working models, then one row per GPU')
assertDeepEqual(home.rows.slice(2).map(r => r.label), ['Arc Pro B70 #1', 'Arc Pro B70 #2', 'RTX 3090', 'Radeon RX 6600'], 'local-ai cards are numbered only when there are several of a kind')
assertEqual(home.rows[2].note, 'running Qwen3.8-27B', 'local-ai a GPU running a model says so')
assertDeepEqual([home.rows[3].hint, home.rows[3].open, home.rows[3].run.action], ['set up ›', 'kind|arc|a1', 'run|q|a1'], 'local-ai a free GPU can be set up or run on directly')
assert(home.rows[4].warn && !home.rows[5].warn, 'local-ai only a card held by another program is a warning')
assertEqual(home.rows[5].note, 'no validated model yet', 'local-ai a card with no model says so')
assertDeepEqual([home.stat, home.statLabel], ['4.2M', 'all time'], 'local-ai home shows all-time tokens as value and label')

// A crashed model is its GPU's row: run it again or dismiss it
const crashed = Object.assign({}, snap, { deployments: [Object.assign({}, snap.deployments[0], { id: 'x', state: 'error', error: 'the engine stopped' })] })
const rows = model.build(crashed, { view: 'home' }).rows
assertDeepEqual(rows.map(r => r.type), ['sec', 'slot', 'slot', 'slot', 'slot'], 'local-ai a crashed model is not a card')
assertDeepEqual([rows[1].hint, rows[1].crashed, rows[1].acts.map(a => a.action)], ['crashed', true, ['again|x|a0', 'stop|x']], 'local-ai a crashed GPU runs again or dismisses (stops) it')
JS
