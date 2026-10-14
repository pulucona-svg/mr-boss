const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { parseDSpaceTitle, extractDateMetadata } = require('../lib/services/dspace_service');

console.log('--- RUNNING DSPACE SERVICE COMPILED UNIT TESTS ---');

// 1. Title parsing tests
console.log('\n[1] Testing title parsing...');
const testTitles = [
  {
    input: 'BOTA 222: Plant Anatomy & Physiology',
    expectedCode: 'BOTA 222',
    expectedName: 'Plant Anatomy & Physiology',
  },
  {
    input: 'COMP/COSC 111: Introduction to Programming',
    expectedCode: 'COMP/COSC 111',
    expectedName: 'Introduction to Programming',
  },
  {
    input: 'EDCI 311: Special Methods in English (2024)',
    expectedCode: 'EDCI 311',
    expectedName: 'Special Methods in English (2024)',
  },
  {
    input: 'HIST 121 African History to 1885',
    expectedCode: 'HIST 121',
    expectedName: 'African History to 1885',
  },
  {
    input: 'COMM 100 - Communication Skills',
    expectedCode: 'COMM 100',
    expectedName: 'Communication Skills',
  },
];

for (const t of testTitles) {
  const parsed = parseDSpaceTitle(t.input, '');
  assert.strictEqual(parsed.unitCode, t.expectedCode, `Unit code mismatch for "${t.input}"`);
  assert.strictEqual(parsed.unitName, t.expectedName, `Unit name mismatch for "${t.input}"`);
  console.log(`  ✓ "${t.input}" -> code="${parsed.unitCode}", name="${parsed.unitName}"`);
}

// 2. Date extraction tests
console.log('\n[2] Testing date extraction...');
const testDates = [
  { input: '2024-05-12', expectedDate: '2024-05-12', expectedYear: 2024 },
  { input: '2023-11', expectedDate: '2023-11', expectedYear: 2023 },
  { input: '2022', expectedDate: '2022', expectedYear: 2022 },
  { input: 'December 2021', expectedDate: 'December 2021', expectedYear: 2021 },
  { input: 'Invalid String', expectedDate: 'Invalid String', expectedYear: null },
  { input: '', expectedDate: '', expectedYear: null },
];

for (const d of testDates) {
  const itemData = {
    metadata: {
      'dc.date.issued': d.input ? [{ value: d.input }] : [],
    },
  };
  const result = extractDateMetadata(itemData);
  assert.strictEqual(result.publicationDate, d.expectedDate, `Date mismatch for "${d.input}"`);
  assert.strictEqual(result.publicationYear, d.expectedYear, `Year mismatch for "${d.input}"`);
  console.log(`  ✓ "${d.input}" -> date="${result.publicationDate}", year=${result.publicationYear}`);
}

// 3. Virtual users configuration tests
console.log('\n[3] Testing virtual users configuration...');
const { VIRTUAL_USER_ACCOUNTS } = require('../lib/config/virtual_users');
assert.strictEqual(VIRTUAL_USER_ACCOUNTS.length, 20, 'Expected exactly 20 virtual users');
const seenUids = new Set();
const seenEmails = new Set();

for (const user of VIRTUAL_USER_ACCOUNTS) {
  assert.ok(user.uid && user.uid.length > 5, `User ${user.email} missing valid UID`);
  assert.ok(user.email.endsWith('@virtual.mirrorlaikipia.ac.ke'), `User ${user.email} should have @virtual.mirrorlaikipia.ac.ke domain`);
  assert.ok(user.name && user.name.length > 3, `User ${user.email} missing name`);
  assert.ok(!seenUids.has(user.uid), `Duplicate UID found: ${user.uid}`);
  assert.ok(!seenEmails.has(user.email), `Duplicate email found: ${user.email}`);
  seenUids.add(user.uid);
  seenEmails.add(user.email);
}
console.log(`  ✓ All 20 virtual users verified with unique authoritative UIDs and @virtual.mirrorlaikipia.ac.ke accounts.`);

// 4. Curriculum lessons JSON verification
console.log('\n[4] Testing curriculum data bundle...');
const lessonsPath = path.resolve(__dirname, '../src/data/lessons.json');
assert.ok(fs.existsSync(lessonsPath), 'lessons.json must exist in functions/src/data/');
let raw = fs.readFileSync(lessonsPath, 'utf8');
if (raw.charCodeAt(0) === 0xfeff) raw = raw.slice(1);
const lessons = JSON.parse(raw);
assert.ok(Array.isArray(lessons) && lessons.length > 100, `Expected at least 100 curriculum units, got ${lessons.length}`);
console.log(`  ✓ lessons.json contains ${lessons.length} curriculum units.`);

// Check lookup of sample units
const compUnits = lessons.filter((l) => {
  const code = l['Unit Code'] || l['unitCode'] || '';
  return code.startsWith('COMP');
});
assert.ok(compUnits.length > 0, 'Expected COMP units in curriculum');
console.log(`  ✓ Verified curriculum contains ${compUnits.length} Computer Science units.`);

console.log('\n>>> ALL BACKEND DSPACE SERVICE UNIT TESTS PASSED SUCCESSFULLY! <<<\n');
