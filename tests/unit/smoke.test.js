'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load.js');

test('carrega app.js e expõe money()', () => {
  assert.ok(load().money(1234.5).includes('1.234,50'));
});
