const admin = require('firebase-admin');

const serviceAccountPath = 'C:\\Users\\Hp i7\\Documents\\mirror Laikipia3\\mirror_laikipia\\backend\\credentials\\firebase-service-account.json';
const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();
const functions = require('./lib/index.js');

async function testHelpAndSupport() {
  console.log('\n======================================================');
  console.log('--- TESTING HELP & SUPPORT DYNAMIC GEMINI PIPELINE ---');
  console.log('======================================================\n');

  const testMessage = "How do I upload notes and view them offline in Mirror Laikipia?";
  console.log(`[HELP_REQUEST] Incoming request message: "${testMessage}"`);

  const mockRequest = {
    data: {
      message: testMessage,
      history: []
    },
    auth: { uid: 'test_student_user_123' }
  };

  try {
    const res = await functions.askGeminiHelpSupport.run(mockRequest);
    console.log('\n[HELP_RESPONSE_RECEIVED]:');
    console.log(JSON.stringify(res, null, 2));
    if (res && res.success && res.reply) {
      console.log('\n✅ SUCCESS: Help & Support dynamically connected and returned real Gemini response!');
      console.log(`AI Answer:\n${res.reply}`);
    } else {
      console.error('FAILED: Help & Support returned error:', res);
    }
  } catch (err) {
    console.error('EXCEPTION in Help & Support:', err);
  }
}

async function testAsyncBackgroundThumbnailQueue() {
  console.log('\n=============================================================================');
  console.log('--- TESTING ASYNCHRONOUS BACKGROUND THUMBNAIL QUEUE (INSTANT UPLOAD FLOW) ---');
  console.log('=============================================================================\n');

  const testMaterials = [
    { unitName: "Intro' to Quantum Chemistry", materialType: "Notes", catType: null, unitCode: "CHEM 301" },
    { unitName: "Organic Chemistry", materialType: "Notes", catType: null, unitCode: "CHEM 211" },
    { unitName: "Human Anatomy", materialType: "Lab Practical", catType: null, unitCode: "ANAT 101" },
    { unitName: "Data Structures", materialType: "CATs", catType: "CAT 1", unitCode: "COMP 210" },
    { unitName: "Operating Systems", materialType: "Exams", catType: "Main Exam", unitCode: "COMP 312" },
    { unitName: "Microbiology", materialType: "Practical Manual", catType: null, unitCode: "BIOL 220" },
  ];

  const results = [];

  for (let i = 0; i < testMaterials.length; i++) {
    const mat = testMaterials[i];
    console.log(`\n------------------------------------------------------------------`);
    console.log(`--- INSTANT UPLOAD #${i + 1}: Unit: "${mat.unitName}" (${mat.materialType}) ---`);
    console.log(`------------------------------------------------------------------`);

    // 1. User uploads material -> Published immediately with thumbnailStatus = 'pending' and thumbnailUrl = ''
    const docRef = await db.collection("resources").add({
      title: mat.unitName,
      unitName: mat.unitName,
      unitCode: mat.unitCode,
      type: mat.materialType,
      catType: mat.catType,
      thumbnailUrl: "",
      thumbnailId: "",
      thumbnailStatus: "pending",
      uploadDate: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`[INSTANT_UPLOAD_SUCCESS] Material published immediately to Firestore document ID: "${docRef.id}" (thumbnailStatus: "pending", thumbnailUrl: null)`);

    // 2. Asynchronous background queue picks up document
    console.log(`[ASYNC_QUEUE_PROCESSING] Background worker processing thumbnail generation for document "${docRef.id}"...`);
    const mockRequest = {
      data: { resourceId: docRef.id },
      auth: { uid: 'test_uploader_456' }
    };

    await functions.processThumbnailJob.run(mockRequest);

    // Fetch updated Firestore document to verify completed ImageKit URL
    const updatedSnap = await docRef.get();
    const updatedData = updatedSnap.data();

    console.log(`[FIRESTORE_REALTIME_UPDATE] Updated Status: "${updatedData.thumbnailStatus}", ImageKit URL: "${updatedData.thumbnailUrl}"`);

    results.push({
      uploadNumber: i + 1,
      docId: docRef.id,
      unitName: mat.unitName,
      materialType: mat.materialType,
      thumbnailStatus: updatedData.thumbnailStatus,
      thumbnailUrl: updatedData.thumbnailUrl,
      thumbnailId: updatedData.thumbnailId,
    });
  }

  console.log('\n==================================================================');
  console.log('--- SUMMARY OF ASYNCHRONOUS BACKGROUND THUMBNAIL QUEUE ---');
  console.log('==================================================================\n');
  console.table(results);

  const completedResults = results.filter(r => r.thumbnailStatus === 'completed');
  const uniqueUrls = new Set(completedResults.map(r => r.thumbnailUrl));

  console.log(`Total Uploads Completed: ${completedResults.length} / 6`);
  console.log(`Total Unique ImageKit URLs: ${uniqueUrls.size} / ${completedResults.length}`);

  if (completedResults.length === 6 && uniqueUrls.size === 6) {
    console.log('\n✅ PASS: ALL UPLOADS COMPLETED INSTANTLY, BACKGROUND QUEUE GENERATED 6 UNIQUE IMAGEKIT THUMBNAILS WITH ZERO FALLBACKS!');
  } else {
    console.log('\n⚠️ PARTIAL RESULT: Inspect summary table above.');
  }
}

async function runAll() {
  await testHelpAndSupport();
  await testAsyncBackgroundThumbnailQueue();
  process.exit(0);
}

runAll();
