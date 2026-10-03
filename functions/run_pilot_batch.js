const fs = require("fs");
const path = require("path");
const { EnvConfig } = require("./lib/config/env_config");
const { FluxThumbnailProvider } = require("./lib/providers/image_generation/flux_thumbnail_provider");
const { GeminiThumbnailProvider } = require("./lib/providers/image_generation/gemini_thumbnail_provider");
const { ThumbnailSearchService } = require("./lib/thumbnail_search_service");

const pilotResources = [
  // TECHNOLOGY — 5
  {
    id: "tech_1_comp_111",
    category: "Technology",
    courseCode: "COMP 111",
    title: "Intro to Computer Applications",
    materialType: "Notes",
    topic: "Word Processing, Spreadsheets, and Operating Environments",
    description: "Foundational computer applications for university study"
  },
  {
    id: "tech_2_comp_210",
    category: "Technology",
    courseCode: "COMP 210",
    title: "Data Structures & Algorithms",
    materialType: "Notes",
    topic: "Binary Trees, Sorting Algorithms, and Graph Theory",
    description: "Core algorithms and abstract data structures"
  },
  {
    id: "tech_3_bict_221",
    category: "Technology",
    courseCode: "BICT 221",
    title: "Operating Systems Principles",
    materialType: "Notes",
    topic: "Kernel Architecture, Process Scheduling, and Virtual Memory",
    description: "Theoretical and practical operating systems design"
  },
  {
    id: "tech_4_comp_320",
    category: "Technology",
    courseCode: "COMP 320",
    title: "Database Management Systems",
    materialType: "Notes",
    topic: "Relational Data Modeling, SQL Queries, and Normalization",
    description: "Database design, administration, and implementation"
  },
  {
    id: "tech_5_bict_315",
    category: "Technology",
    courseCode: "BICT 315",
    title: "Computer Networks",
    materialType: "Notes",
    topic: "OSI Reference Model, TCP/IP, Routing Protocols, and Switching",
    description: "Data communications and enterprise network architectures"
  },

  // NON-TECHNOLOGY — 3
  {
    id: "nontech_6_bcom_101",
    category: "Non-Technology",
    courseCode: "BCOM 101",
    title: "Financial Accounting",
    materialType: "Notes",
    topic: "Double-Entry Bookkeeping, Financial Statements, and Ledgers",
    description: "Principles of commercial financial accounting and reporting"
  },
  {
    id: "nontech_7_math_120",
    category: "Non-Technology",
    courseCode: "MATH 120",
    title: "Calculus I",
    materialType: "Notes",
    topic: "Differential Calculus, Limits, Continuity, and Applications",
    description: "Single-variable differential and integral calculus"
  },
  {
    id: "nontech_8_agri_210",
    category: "Non-Technology",
    courseCode: "AGRI 210",
    title: "Crop Production & Soil Science",
    materialType: "Notes",
    topic: "Soil Fertility, Agronomic Field Trials, and Plant Nutrition",
    description: "Scientific agronomy and crop cultivation methodologies"
  },

  // SIMILAR-UNIT PAIRS — 3 pairs (6 units)
  // Pair 1: COMP 101 vs COMP 102
  {
    id: "pair_9a_comp_101",
    category: "Similar Pair 1 (Programming)",
    pairGroup: "Pair 1",
    courseCode: "COMP 101",
    title: "Introduction to Programming in Python",
    materialType: "Notes",
    topic: "Control Structures, Functions, and Basic Scripting",
    description: "Introductory procedural programming with Python"
  },
  {
    id: "pair_9b_comp_102",
    category: "Similar Pair 1 (Programming)",
    pairGroup: "Pair 1",
    courseCode: "COMP 102",
    title: "Object Oriented Programming in Java",
    materialType: "Notes",
    topic: "Encapsulation, Inheritance, Polymorphism, and Classes",
    description: "Object-oriented software development and class hierarchies"
  },

  // Pair 2: ECON 101 vs ECON 102
  {
    id: "pair_10a_econ_101",
    category: "Similar Pair 2 (Economics)",
    pairGroup: "Pair 2",
    courseCode: "ECON 101",
    title: "Introduction to Microeconomics",
    materialType: "Notes",
    topic: "Consumer Utility, Supply and Demand Equilibrium, Price Elasticity",
    description: "Microeconomic behavior of individuals and commercial firms"
  },
  {
    id: "pair_10b_econ_102",
    category: "Similar Pair 2 (Economics)",
    pairGroup: "Pair 2",
    courseCode: "ECON 102",
    title: "Introduction to Macroeconomics",
    materialType: "Notes",
    topic: "National Income, GDP, Inflation, Monetary and Fiscal Policy",
    description: "Macroeconomic systems, banking, and international trade"
  },

  // Pair 3: MATH 211 vs MATH 212
  {
    id: "pair_11a_math_211",
    category: "Similar Pair 3 (Mathematics)",
    pairGroup: "Pair 3",
    courseCode: "MATH 211",
    title: "Linear Algebra",
    materialType: "Notes",
    topic: "Matrix Algebra, Determinants, Vector Spaces, and Eigenvalues",
    description: "Linear systems and finite-dimensional vector spaces"
  },
  {
    id: "pair_11b_math_212",
    category: "Similar Pair 3 (Mathematics)",
    pairGroup: "Pair 3",
    courseCode: "MATH 212",
    title: "Multivariable Calculus",
    materialType: "Notes",
    topic: "Partial Derivatives, Multiple Integrals, and Vector Fields",
    description: "Calculus in multiple dimensions and vector field integration"
  }
];

async function runPilot() {
  const outputDir = path.join(__dirname, "pilot_output");
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  const workers = EnvConfig.getFluxWorkerConfigs();
  const geminiProvider = new GeminiThumbnailProvider();

  console.log("=================================================================");
  console.log("=== STARTING CONTROLLED REAL-IMAGE PILOT BATCH (14 UNITS) ===");
  console.log(`=== Flux Workers Available: ${workers.length} | Gemini Fallback Available ===`);
  console.log("=================================================================\n");

  const manifest = [];

  for (let i = 0; i < pilotResources.length; i++) {
    const res = pilotResources[i];
    console.log(`\n-----------------------------------------------------------------`);
    console.log(`[${i + 1}/${pilotResources.length}] Processing ${res.courseCode}: ${res.title}`);
    console.log(`Category: ${res.category}`);

    const prompt = ThumbnailSearchService.buildImagePrompt({
      title: res.title,
      courseCode: res.courseCode,
      materialType: res.materialType,
      topic: res.topic,
      description: res.description
    });

    const sceneMatch = prompt.match(/\[VISUAL SCENE & OBJECTS\]:\s*([^\n]+)/);
    const compMatch = prompt.match(/\[COMPOSITION & LIGHTING\]:\s*([^\n]+)/);
    console.log(`Scene: ${sceneMatch ? sceneMatch[1] : ""}`);
    console.log(`Comp : ${compMatch ? compMatch[1] : ""}`);

    let generated = null;
    let providerName = "";
    let modelUsed = "";
    let workerId = "";
    let durationMs = 0;
    const startTime = Date.now();

    // Try Flux Workers in round-robin / fallback order
    for (let w = 0; w < workers.length; w++) {
      const workerConfig = workers[(i + w) % workers.length];
      try {
        const flux = new FluxThumbnailProvider(workerConfig);
        console.log(`Attempting Flux worker: ${workerConfig.workerId}...`);
        const fluxRes = await flux.generateImage(prompt, {
          title: res.title,
          courseCode: res.courseCode
        });
        if (fluxRes && fluxRes.imageBuffer && fluxRes.imageBuffer.length > 0) {
          generated = fluxRes;
          providerName = "Flux.2 Dev";
          modelUsed = fluxRes.modelUsed;
          workerId = workerConfig.workerId;
          durationMs = Date.now() - startTime;
          console.log(`Flux worker ${workerConfig.workerId} succeeded in ${durationMs}ms (${fluxRes.imageBuffer.length} bytes)`);
          break;
        }
      } catch (err) {
        console.warn(`Worker ${workerConfig.workerId} failed: ${err.message}. Trying next...`);
        // Slight pause between worker retries if capacity error
        await new Promise((r) => setTimeout(r, 1000));
      }
    }

    // Secondary fallback: Gemini
    if (!generated) {
      console.log(`All Flux workers busy/failed. Falling back to Gemini...`);
      try {
        const geminiRes = await geminiProvider.generateImage(prompt, {
          title: res.title,
          courseCode: res.courseCode
        });
        if (geminiRes && geminiRes.imageBuffer && geminiRes.imageBuffer.length > 0) {
          generated = geminiRes;
          providerName = "Gemini";
          modelUsed = geminiRes.modelUsed;
          workerId = "gemini-api";
          durationMs = Date.now() - startTime;
          console.log(`Gemini succeeded in ${durationMs}ms (${geminiRes.imageBuffer.length} bytes)`);
        }
      } catch (gemErr) {
        console.error(`Gemini also failed: ${gemErr.message}`);
      }
    }

    if (generated) {
      const ext = generated.mimeType.includes("png") ? "png" : "jpg";
      const fileName = `${res.id}.${ext}`;
      const filePath = path.join(outputDir, fileName);
      fs.writeFileSync(filePath, generated.imageBuffer);

      manifest.push({
        id: res.id,
        courseCode: res.courseCode,
        title: res.title,
        category: res.category,
        pairGroup: res.pairGroup || null,
        success: true,
        provider: providerName,
        model: modelUsed,
        workerId: workerId,
        durationMs: durationMs,
        bytes: generated.imageBuffer.length,
        fileName: fileName,
        filePath: filePath,
        promptScene: sceneMatch ? sceneMatch[1] : "",
        promptComp: compMatch ? compMatch[1] : ""
      });
      console.log(`Saved isolated image to: ${filePath}`);
    } else {
      manifest.push({
        id: res.id,
        courseCode: res.courseCode,
        title: res.title,
        category: res.category,
        pairGroup: res.pairGroup || null,
        success: false,
        error: "All providers failed"
      });
      console.error(`FAILED to generate image for ${res.courseCode}`);
    }

    // 1.5s rate-limit pause between pilot calls to be gentle on accounts
    await new Promise((r) => setTimeout(r, 1500));
  }

  const manifestPath = path.join(outputDir, "pilot_manifest.json");
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));

  console.log("\n=================================================================");
  console.log(`=== PILOT RUN COMPLETE: ${manifest.filter((m) => m.success).length}/${manifest.length} SUCCEEDED ===`);
  console.log(`Manifest written to: ${manifestPath}`);
  console.log("=================================================================\n");
}

runPilot().catch((err) => {
  console.error("Fatal error in pilot runner:", err);
  process.exit(1);
});
