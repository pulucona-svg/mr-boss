const assert = require("assert");
const { ThumbnailSearchService } = require("./lib/thumbnail_search_service");

// 1. Five Computer/IT-Related Units
const itUnits = [
  { courseCode: "COMP 111", title: "Introduction to Computer Applications", materialType: "Notes", topic: "Word Processing and Spreadsheets" },
  { courseCode: "COMP 210", title: "Data Structures and Algorithms", materialType: "Notes", topic: "Binary Trees and Sorting" },
  { courseCode: "BICT 221", title: "Operating Systems Principles", materialType: "Notes", topic: "Process Scheduling and Memory Management" },
  { courseCode: "COMP 320", title: "Database Management Systems", materialType: "Notes", topic: "Relational Schema and SQL" },
  { courseCode: "BICT 315", title: "Computer Networks and Data Communication", materialType: "Notes", topic: "OSI Model and Routing" },
];

// 2. Five Non-Technology Units
const nonItUnits = [
  { courseCode: "BCOM 101", title: "Principles of Financial Accounting", materialType: "Notes", topic: "Ledgers and Trial Balance" },
  { courseCode: "MATH 120", title: "Calculus I", materialType: "Notes", topic: "Derivatives and Limits" },
  { courseCode: "AGRI 210", title: "Crop Production and Soil Science", materialType: "Notes", topic: "Agronomic Field Trials" },
  { courseCode: "LAWS 101", title: "Introduction to Constitutional Law", materialType: "Notes", topic: "Separation of Powers" },
  { courseCode: "CHEM 201", title: "Organic Chemistry Laboratory Practical", materialType: "Lab Manual", topic: "Volumetric Titration and Distillation" },
];

// 3. Five Pairs of Semantically Similar Units
const similarPairs = [
  {
    category: "Computer Programming",
    unitA: { courseCode: "COMP 101", title: "Introduction to Programming in Python", materialType: "Notes", topic: "Control Structures and Functions" },
    unitB: { courseCode: "COMP 102", title: "Object Oriented Programming in Java", materialType: "Notes", topic: "Classes, Objects and Polymorphism" }
  },
  {
    category: "Networking & Security",
    unitA: { courseCode: "BICT 321", title: "Network Security and Cryptography", materialType: "Notes", topic: "Public Key Encryption and Firewalls" },
    unitB: { courseCode: "COMP 325", title: "Wireless Networks and Telecommunications", materialType: "Notes", topic: "Cellular Systems and Antennas" }
  },
  {
    category: "Economics",
    unitA: { courseCode: "ECON 101", title: "Introduction to Microeconomics", materialType: "Notes", topic: "Supply, Demand and Market Equilibrium" },
    unitB: { courseCode: "ECON 102", title: "Introduction to Macroeconomics", materialType: "Notes", topic: "GDP, Inflation and Monetary Policy" }
  },
  {
    category: "Mathematics",
    unitA: { courseCode: "MATH 211", title: "Linear Algebra", materialType: "Notes", topic: "Vector Spaces and Eigenvalues" },
    unitB: { courseCode: "MATH 212", title: "Multivariable Calculus", materialType: "Notes", topic: "Multiple Integrals and Vector Fields" }
  },
  {
    category: "Health & Medical",
    unitA: { courseCode: "NURS 201", title: "Fundamentals of Nursing Practice", materialType: "Notes", topic: "Patient Vital Signs and Bedside Care" },
    unitB: { courseCode: "ANAT 202", title: "Human Anatomy and Physiology", materialType: "Notes", topic: "Musculoskeletal and Circulatory Systems" }
  }
];

function extractSection(prompt, sectionName) {
  const regex = new RegExp(`\\[${sectionName}\\]:\\s*([\\s\\S]*?)(?=\\n\\n\\[|$)`);
  const match = prompt.match(regex);
  return match ? match[1].trim() : "";
}

console.log("===============================================================");
console.log("=== CONTROLLED TEST SET 1: 5 COMPUTER / IT UNITS ===");
console.log("===============================================================\n");

for (const u of itUnits) {
  const p = ThumbnailSearchService.buildImagePrompt(u);
  const scene = extractSection(p, "VISUAL SCENE & OBJECTS");
  const comp = extractSection(p, "COMPOSITION & LIGHTING");
  const style = extractSection(p, "STYLE & RENDER QUALITY");

  console.log(`Course: [${u.courseCode}] ${u.title}`);
  console.log(`Scene : ${scene}`);
  console.log(`Comp  : ${comp}`);
  console.log(`Style : ${style.slice(0, 100)}...\n`);

  assert(scene.toLowerCase().includes("photograph"), "Must be photographic");
  assert(!scene.toLowerCase().includes("neon"), "Must not contain neon in visual scene");
  assert(!scene.toLowerCase().includes("luminous"), "Must not contain luminous data pathways");
  assert(!scene.toLowerCase().includes("3d scientific visualization"), "Must not contain 3D scientific visualization");
  assert(!style.toLowerCase().includes("3d scientific visualization"), "Style must not contain 3D scientific visualization");
  assert(style.toLowerCase().includes("authentic professional editorial photography"), "Style must specify authentic professional editorial photography");
}

console.log("===============================================================");
console.log("=== CONTROLLED TEST SET 2: 5 NON-TECHNOLOGY UNITS ===");
console.log("===============================================================\n");

for (const u of nonItUnits) {
  const p = ThumbnailSearchService.buildImagePrompt(u);
  const scene = extractSection(p, "VISUAL SCENE & OBJECTS");
  const comp = extractSection(p, "COMPOSITION & LIGHTING");
  const style = extractSection(p, "STYLE & RENDER QUALITY");

  console.log(`Course: [${u.courseCode}] ${u.title}`);
  console.log(`Scene : ${scene}`);
  console.log(`Comp  : ${comp}\n`);

  assert(scene.toLowerCase().includes("photograph"), "Must be photographic");
  assert(!scene.toLowerCase().includes("3d global economic sphere"), "Must not contain 3D global economic sphere");
  assert(!scene.toLowerCase().includes("geometric coordinate manifolds"), "Must not contain geometric coordinate manifolds");
}

console.log("===============================================================");
console.log("=== CONTROLLED TEST SET 3: 5 PAIRS OF SIMILAR UNITS ===");
console.log("===============================================================\n");

for (let i = 0; i < similarPairs.length; i++) {
  const pair = similarPairs[i];
  const pA = ThumbnailSearchService.buildImagePrompt(pair.unitA);
  const pB = ThumbnailSearchService.buildImagePrompt(pair.unitB);

  const sceneA = extractSection(pA, "VISUAL SCENE & OBJECTS");
  const sceneB = extractSection(pB, "VISUAL SCENE & OBJECTS");
  const compA = extractSection(pA, "COMPOSITION & LIGHTING");
  const compB = extractSection(pB, "COMPOSITION & LIGHTING");

  console.log(`PAIR ${i + 1} [${pair.category}]:`);
  console.log(`  Unit A [${pair.unitA.courseCode}] ${pair.unitA.title}`);
  console.log(`    Scene: ${sceneA}`);
  console.log(`    Comp : ${compA}`);
  console.log(`  Unit B [${pair.unitB.courseCode}] ${pair.unitB.title}`);
  console.log(`    Scene: ${sceneB}`);
  console.log(`    Comp : ${compB}`);
  console.log(`  --> Scene Distinct? ${sceneA !== sceneB}`);
  console.log(`  --> Comp Distinct?  ${compA !== compB}`);
  console.log(`  --> Prompts Distinct? ${pA !== pB}\n`);

  assert.notStrictEqual(sceneA, sceneB, "Scenes must be distinct between similar units");
  assert.notStrictEqual(pA, pB, "Full prompts must be distinct between similar units");
}

console.log("===============================================================");
console.log("ALL CONTROLLED VALIDATION TESTS PASSED WITH 100% SUCCESS!");
console.log("===============================================================");
