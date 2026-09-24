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

// Home: running models as cards, then the available GPUs as rows; the rest is one "all GPUs" away
const recipe = { id: 'q', name: 'Qwen3.8-27B', family: 'qwen', caps: {}, weights: [] }
const snap = {
  version: '1.0.0', week: 925200, total: 4210000,
  gpus: [{ key: 'a0', name: 'Arc Pro B70', hw: 'arc', vramGb: 32 }, { key: 'a1', name: 'Arc Pro B70', hw: 'arc', vramGb: 32 },
    { key: 'a2', name: 'Arc Pro B70', hw: 'arc', vramGb: 32 }, { key: 'n0', name: 'RTX 3090', hw: '3090', vramGb: 24 },
    { key: 'r0', name: 'Radeon RX 6600', hw: '', vramGb: 8 }],
  kinds: [{ hw: 'arc', name: 'Arc Pro B70', keys: ['a0', 'a1', 'a2'], free: ['a1', 'a2'], taken: [], recipe, groups: [{ id: 'q2', name: 'Qwen3.8-27B', cards: 2 }] },
    { hw: '3090', name: 'RTX 3090', keys: ['n0'], free: [], taken: ['n0'], recipe }],
  deployments: [{ id: 'd', name: 'Qwen3.8-27B', keys: ['a0'], state: 'ready', agent: 'pi', session: { all: { tokens: 10 } } }],
}
const home = model.build(snap, { view: 'home' })
assertDeepEqual(home.rows.map(r => r.type), ['run', 'sec', 'slot', 'slot', 'field'], 'local-ai home: running cards, then available GPUs, then all GPUs')
assertDeepEqual(home.rows.slice(2, 4).map(r => [r.label, r.run.action]), [['Arc Pro B70', 'run|q|a1'], ['Arc Pro B70', 'run|q|a2']], 'local-ai only free GPUs are listed, each running its model in one click')
assertDeepEqual([home.rows[4].label, home.rows[4].value, home.rows[4].action], ['all GPUs', '5', 'gpus'], 'local-ai the rest of the GPUs are one link away')
assertDeepEqual([home.stat, home.statLabel], ['4.2M', 'all time'], 'local-ai home shows all-time tokens as value and label')

// Opening a free GPU: run it, run one model across it and another free card of its kind, or its Config
const opened = model.build(snap, { view: 'home', open: 'gpu:a1' }).rows
assertDeepEqual(opened[3].items.map(a => a.action), ['run|q|a1', 'run|q2|a1,a2', 'kind|arc|a1'], 'local-ai a free GPU offers a group across free cards of its kind')

// All GPUs: every card as home's rows, free ones first; a busy one still opens to its Config
const all = model.build(snap, { view: 'gpus' }).rows
assertDeepEqual(all.slice(1).map(r => r.run ? r.run.action : r.note), ['run|q|a1', 'run|q|a2', 'running Qwen3.8-27B', 'in use by another program', 'no validated model yet'], 'local-ai the GPUs page lists every card and its state')
const held = model.build(snap, { view: 'gpus', open: 'gpu:n0' }).rows
assertDeepEqual([held[5].type, held[5].note, held[5].items.map(a => a.label + ' ' + a.action)], ['links', '24 GB', ['Config kind|3090|n0']], 'local-ai a card another program holds opens to its Config')

// A crashed model is an available GPU's row: run it again in one click, or open it for the reason, the log and dismiss
const crashed = Object.assign({}, snap, { deployments: [Object.assign({}, snap.deployments[0], { id: 'x', state: 'error', error: 'the engine stopped' })] })
const rows = model.build(crashed, { view: 'home', open: 'gpu:a0' }).rows
assertDeepEqual(rows.map(r => r.type), ['sec', 'slot', 'slot', 'slot', 'links', 'field'], 'local-ai a crashed model is a row after the free ones')
assertDeepEqual(rows[3].dismiss, 'stop|x', 'local-ai a crashed GPU is dismissed from its row in one click')
assertDeepEqual([rows[3].crashed, rows[3].run.action, rows[4].note, rows[4].items.map(a => a.action)], [true, 'again|x|a0', '32 GB\nthe engine stopped', ['again|x|a0', 'log', 'more|x', 'stop|x']], 'local-ai a crashed GPU runs again, shows why, opens its Config, or is dismissed (stopped)')
JS
