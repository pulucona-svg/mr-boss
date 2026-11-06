/**
 * test_semantic_thumbnail_prompts.js
 * 
 * Offline test suite for semantic prompt construction in ThumbnailSearchService.
 * Validates that the AI image generation prompts interpret the COMPLETE academic unit name
 * as an integrated subject rather than isolating polysemous keywords.
 * 
 * Verifies the 6 key academic course examples:
 * 1. "Structure of English" -> Linguistics, grammar, syntax, NOT architectural construction.
 * 2. "Introduction to Computer Networks" -> Enterprise networking, routers, patch cables, NOT generic PC.
 * 3. "Principles of Financial Accounting" -> Accounting ledgers, balance sheets, calculators, NOT generic cash.
 * 4. "Environmental Health" -> Public health, water sampling, epidemiology, NOT syringe/pure wilderness.
 * 5. "Literary Criticism" -> Literature study carrel, classic books, critical reading, NOT courtroom critique.
 * 6. "Organizational Theory" -> Business school conference, strategic planning binders, NOT mechanical gears.
 * 
 * Ensures:
 * - Complete title preserved without truncation.
 * - Explicit whole-subject semantic interpretation directives present.
 * - Polysemous disambiguation guidance included.
 * - Negative constraints strictly intact (zero text, no words/letters/numbers/logos).
 * - Aspect ratio remains 16:9 widescreen landscape.
 * - Titles never enclosed in literal double quotes (avoids diffusion model typography render).
 * - Zero external API requests, zero quota consumption.
 */

const assert = require("assert");
const { ThumbnailSearchService } = require("./lib/thumbnail_search_service");

console.log("=== SEMANTIC THUMBNAIL PROMPT INTERPRETATION TEST SUITE ===\n");

let passed = 0;
let failed = 0;

function runTest(name, fn) {
  try {
    fn();
    console.log(`[PASS] ${name}`);
    passed++;
  } catch (err) {
    console.error(`[FAIL] ${name}: ${err.message}`);
    failed++;
  }
}

// -------------------------------------------------------------
// Test Case 1: "Structure of English"
// -------------------------------------------------------------
runTest('Example 1: "Structure of English" resolves to linguistics/language and instructs complete subject reasoning', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Structure of English",
    courseCode: "ENG 211",
    materialType: "Notes",
    topic: "Structure of English",
  });

  // 1. Complete title presence
  assert(prompt.includes("Structure of English"), "Prompt must include full title 'Structure of English'");
  assert(prompt.includes("ENG 211"), "Prompt must include course code 'ENG 211'");
  
  // 2. No literal double quotes wrapping title
  assert(!prompt.includes('"Structure of English"'), "Title must not be wrapped in literal double quotes");

  // 3. Whole-subject semantic interpretation section
  assert(prompt.includes("[ACADEMIC SUBJECT & SEMANTIC INTERPRETATION]"), "Prompt must have semantic interpretation header");
  assert(prompt.includes("UNIFIED SUBJECT INTERPRETATION: Interpret the complete unit title (Structure of English) as one cohesive, integrated academic subject"), "Must instruct unified interpretation");
  assert(prompt.includes("Never select an isolated keyword or ignore parts of the title"), "Must forbid isolated keyword selection");

  // 4. Disambiguation against architectural interpretation
  assert(prompt.includes("structure"), "Disambiguation directive must mention 'structure'");
  assert(prompt.includes("never as unrelated architectural construction"), "Must warn against architectural misinterpretation");

  // 5. Appropriate scene selection (linguistics / language learning)
  assert(/language|linguistics|transcription|dictionary|phonetic/i.test(prompt), "Visual scene must relate to linguistics or language study");
  assert(!/construction site|bridge|skyscraper|building concrete/i.test(prompt), "Must not depict building construction");

  // 6. Mandatory negative constraints and composition
  assert(prompt.includes("[MANDATORY NEGATIVE CONSTRAINTS - STRICTLY NO TEXT]"), "Negative constraints section must exist");
  assert(prompt.includes("MANDATORY REQUIREMENT: ABSOLUTELY ZERO TEXT"), "Must require zero text");
  assert(prompt.includes("16:9 widescreen landscape framing"), "Must maintain 16:9 widescreen framing");
});

// -------------------------------------------------------------
// Test Case 2: "Introduction to Computer Networks"
// -------------------------------------------------------------
runTest('Example 2: "Introduction to Computer Networks" resolves to network infrastructure and holistic concept', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Introduction to Computer Networks",
    courseCode: "COMP 220",
    materialType: "Notes",
    topic: "Introduction to Computer Networks",
  });

  assert(prompt.includes("Introduction to Computer Networks"), "Prompt must include full title");
  assert(!prompt.includes('"Introduction to Computer Networks"'), "Title must not be in literal double quotes");
  assert(prompt.includes("UNIFIED SUBJECT INTERPRETATION: Interpret the complete unit title (Introduction to Computer Networks) as one cohesive, integrated academic subject"), "Unified subject instruction");

  // Disambiguation for 'network'
  assert(prompt.includes("network"), "Disambiguation directive must mention 'network'");

  // Visual scene must focus on enterprise networking/switches/cables, not just generic standalone PC
  assert(/switch|router|ethernet|patch|telecommunication|server/i.test(prompt), "Visual scene must contain enterprise networking elements");

  // Quality and constraints
  assert(prompt.includes("ABSOLUTELY ZERO TEXT"), "Must enforce zero text");
  assert(prompt.includes("16:9 widescreen landscape framing"), "Must enforce 16:9 landscape");
});

// -------------------------------------------------------------
// Test Case 3: "Principles of Financial Accounting"
// -------------------------------------------------------------
runTest('Example 3: "Principles of Financial Accounting" resolves to accounting desk & holistic financial reporting', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Principles of Financial Accounting",
    courseCode: "BCOM 101",
    materialType: "Notes",
    topic: "Principles of Financial Accounting",
  });

  assert(prompt.includes("Principles of Financial Accounting"), "Prompt must include full title");
  assert(!prompt.includes('"Principles of Financial Accounting"'), "Title must not be in literal double quotes");
  assert(prompt.includes("UNIFIED SUBJECT INTERPRETATION"), "Must contain unified interpretation instruction");
  assert(prompt.includes("HOLISTIC WORD RELATIONSHIP REASONING"), "Must contain holistic word relationship instruction");

  // Visual scene must represent authentic accounting desk
  assert(/balance sheet|calculator|ledger|audit|financial/i.test(prompt), "Visual scene must depict accounting/auditing environment");

  assert(prompt.includes("ABSOLUTELY ZERO TEXT"), "Must enforce zero text");
  assert(prompt.includes("Authentic professional editorial photography"), "Must specify photographic realism");
});

// -------------------------------------------------------------
// Test Case 4: "Environmental Health"
// -------------------------------------------------------------
runTest('Example 4: "Environmental Health" bridges environmental science and public health', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Environmental Health",
    courseCode: "HLTH 214",
    materialType: "Notes",
    topic: "Environmental Health",
  });

  assert(prompt.includes("Environmental Health"), "Prompt must include full title");
  assert(!prompt.includes('"Environmental Health"'), "Title must not be in literal double quotes");
  assert(prompt.includes("UNIFIED SUBJECT INTERPRETATION: Interpret the complete unit title (Environmental Health) as one cohesive, integrated academic subject"), "Unified subject instruction");

  // Disambiguation guidance
  assert(prompt.includes("intended higher education curriculum context"), "Must identify higher education context");

  // Scene should reflect health/environmental science
  assert(/environmental|water sampling|field research|health|epidemiol|clinical/i.test(prompt), "Scene must represent environmental science or health");

  assert(prompt.includes("ABSOLUTELY ZERO TEXT"), "Zero text requirement");
  assert(prompt.includes("16:9 widescreen landscape framing"), "16:9 framing");
});

// -------------------------------------------------------------
// Test Case 5: "Literary Criticism"
// -------------------------------------------------------------
runTest('Example 5: "Literary Criticism" resolves to literary analysis, NOT courtroom or generic critic', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Literary Criticism",
    courseCode: "LIT 312",
    materialType: "Notes",
    topic: "Literary Criticism",
  });

  assert(prompt.includes("Literary Criticism"), "Prompt must include full title");
  assert(!prompt.includes('"Literary Criticism"'), "Title must not be in literal double quotes");
  assert(prompt.includes("UNIFIED SUBJECT INTERPRETATION: Interpret the complete unit title (Literary Criticism) as one cohesive, integrated academic subject"), "Unified subject instruction");

  // Visual scene should represent literature study room/classic books/hardcover volume
  assert(/literature|books|library|reading|journal/i.test(prompt), "Visual scene must represent academic literature study");
  assert(!/judge|gavel|courtroom|microphone|press conference/i.test(prompt), "Must not represent courtroom or press criticism");

  assert(prompt.includes("ABSOLUTELY ZERO TEXT"), "Zero text requirement");
  assert(prompt.includes("PURELY CONCEPTUAL GUIDANCE"), "Must state title is strictly conceptual guidance");
});

// -------------------------------------------------------------
// Test Case 6: "Organizational Theory"
// -------------------------------------------------------------
runTest('Example 6: "Organizational Theory" resolves to business management and institutional organization', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Organizational Theory",
    courseCode: "BCOM 230",
    materialType: "Notes",
    topic: "Organizational Theory",
  });

  assert(prompt.includes("Organizational Theory"), "Prompt must include full title");
  assert(!prompt.includes('"Organizational Theory"'), "Title must not be in literal double quotes");
  assert(prompt.includes("UNIFIED SUBJECT INTERPRETATION: Interpret the complete unit title (Organizational Theory) as one cohesive, integrated academic subject"), "Unified subject instruction");

  // Disambiguation directive specifically notes 'theory'
  assert(prompt.includes("theory"), "Disambiguation directive must mention 'theory'");

  // Visual scene should reflect business school / management study
  assert(/business|management|strategic|conference|meeting|planning/i.test(prompt), "Visual scene must depict business organization context");
  assert(!/cogs|gears|machinery|clockwork/i.test(prompt), "Must not depict mechanical gears");

  assert(prompt.includes("ABSOLUTELY ZERO TEXT"), "Zero text requirement");
  assert(prompt.includes("16:9 widescreen landscape framing"), "16:9 framing");
});

// -------------------------------------------------------------
// Test Case 7: All 6 Instructions Present in Semantic Section
// -------------------------------------------------------------
runTest('All 6 semantic instructions are systematically integrated into prompt', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Advanced Database Architecture",
    courseCode: "COMP 410",
  });

  assert(prompt.includes("1. UNIFIED SUBJECT INTERPRETATION"), "Rule 1 must be present");
  assert(prompt.includes("2. DISCIPLINE & CONTEXT IDENTIFICATION"), "Rule 2 must be present");
  assert(prompt.includes("3. HOLISTIC WORD RELATIONSHIP REASONING"), "Rule 3 must be present");
  assert(prompt.includes("4. AVOID POLYSEMOUS MISINTERPRETATIONS"), "Rule 4 must be present");
  assert(prompt.includes("5. COHESIVE VISUAL EMBODIMENT"), "Rule 5 must be present");
  assert(prompt.includes("6. PURELY CONCEPTUAL GUIDANCE"), "Rule 6 must be present");
});

// -------------------------------------------------------------
// Test Case 8: Section Order and Structure
// -------------------------------------------------------------
runTest('Section ordering preserves backwards compatibility and validator parser', () => {
  const prompt = ThumbnailSearchService.buildImagePrompt({
    title: "Data Communications",
    courseCode: "COMP 222",
  });

  const sections = [
    "[ACADEMIC SUBJECT & SEMANTIC INTERPRETATION]:",
    "[VISUAL SCENE & OBJECTS]:",
    "[ACADEMIC RELEVANCE]:",
    "[COMPOSITION & LIGHTING]:",
    "[STYLE & RENDER QUALITY]:",
    "[MANDATORY NEGATIVE CONSTRAINTS - STRICTLY NO TEXT]:"
  ];

  let lastIdx = -1;
  for (const s of sections) {
    const idx = prompt.indexOf(s);
    assert(idx !== -1, `Section header '${s}' must be present in prompt`);
    assert(idx > lastIdx, `Section '${s}' must appear in proper sequence`);
    lastIdx = idx;
  }
});

console.log(`\n========================================`);
console.log(`TEST SUMMARY: ${passed} passed, ${failed} failed`);
console.log(`========================================\n`);

if (failed > 0) {
  process.exit(1);
}
