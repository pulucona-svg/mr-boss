const fs = require('fs');
const path = require('path');
const ImageKit = require('imagekit');
const admin = require('firebase-admin');

// 1. Load env config
function loadEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx > 0) {
      const key = trimmed.substring(0, eqIdx).trim();
      let val = trimmed.substring(eqIdx + 1).trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      if (!process.env[key]) process.env[key] = val;
    }
  }
}

loadEnv(path.join(__dirname, '../.env'));
loadEnv(path.join(__dirname, '../.env.mirror-laikipia'));

// 2. Initialize Firebase Admin
const saPath = path.resolve(__dirname, '../../backend/credentials/firebase-service-account.json');
if (!fs.existsSync(saPath)) {
  console.error('Service account not found at:', saPath);
  process.exit(1);
}
const sa = JSON.parse(fs.readFileSync(saPath, 'utf8'));
admin.initializeApp({
  credential: admin.credential.cert(sa),
  projectId: sa.project_id || 'mirror-laikipia',
});
const db = admin.firestore();

// 3. Initialize ImageKit
const imagekit = new ImageKit({
  publicKey: process.env.IMAGEKIT_PUBLIC_KEY,
  privateKey: process.env.IMAGEKIT_PRIVATE_KEY,
  urlEndpoint: process.env.IMAGEKIT_URL_ENDPOINT,
});

const defaultAds = [
  {
    id: 'default_cyber',
    localFile: path.resolve(__dirname, '../../assets/ad_cyber.jpeg'),
    fileName: 'migrated_ad_cyber.jpeg',
    title: 'Davy Cybers 💻',
    subtitle: 'In need of professional cyber services? Worry no more, Davy Cybers we have got you covered.',
    contactUrl: 'https://wa.me/254108462492',
    color: 0xFF20C8FF,
  },
  {
    id: 'default_data',
    localFile: path.resolve(__dirname, '../../assets/ad_data.jpeg'),
    fileName: 'migrated_ad_data.jpeg',
    title: 'Manu Data 🌐',
    subtitle: 'Tired of expensive data plans? Worry no more, Manu Data Solutions we have got you covered.',
    contactUrl: 'https://wa.me/254108462492',
    color: 0xFF00A85A,
  },
  {
    id: 'default_snake',
    localFile: path.resolve(__dirname, '../../assets/ad_snake.jpeg'),
    fileName: 'migrated_ad_snake.jpeg',
    title: 'Snake Light 💡',
    subtitle: 'In need of snake light? Say less, we got you with an exclusive student discount.',
    contactUrl: 'https://wa.me/254108462492',
    color: 0xFFFF8A00,
  },
];

async function migrate() {
  console.log('[MIGRATE] Starting migration of default ads to ImageKit and Firestore manual_ads...');

  for (const ad of defaultAds) {
    console.log(`\n[MIGRATE] Processing "${ad.title}" (${ad.id})...`);
    if (!fs.existsSync(ad.localFile)) {
      console.error(`Local asset not found: ${ad.localFile}`);
      continue;
    }

    const fileBuffer = fs.readFileSync(ad.localFile);
    console.log(`[IMAGEKIT] Uploading ${ad.fileName} (${fileBuffer.length} bytes)...`);

    const ikResult = await imagekit.upload({
      file: fileBuffer,
      fileName: ad.fileName,
      folder: 'MANUAL_ADS',
    });

    console.log(`[IMAGEKIT_SUCCESS] URL: ${ikResult.url} | FileId: ${ikResult.fileId}`);

    const docData = {
      title: ad.title,
      subtitle: ad.subtitle,
      url: ikResult.url,
      imageUrl: ikResult.url,
      mediaFileId: ikResult.fileId,
      contactUrl: ad.contactUrl,
      color: ad.color,
      colorValue: ad.color,
      isActive: true,
      isAsset: false,
      type: 'image',
      migratedFromAsset: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    const docRef = db.collection('manual_ads').doc(ad.id);
    const existing = await docRef.get();
    if (!existing.exists) {
      docData.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }
    await docRef.set(docData, { merge: true });
    console.log(`[FIRESTORE_SUCCESS] Document "manual_ads/${ad.id}" created/updated with server ImageKit URL.`);
  }

  console.log('\n[MIGRATE_COMPLETE] All default ads migrated successfully to ImageKit and Firestore.');
  process.exit(0);
}

migrate().catch(err => {
  console.error('[MIGRATE_ERROR]', err);
  process.exit(1);
});
