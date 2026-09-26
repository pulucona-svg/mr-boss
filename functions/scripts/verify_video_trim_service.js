const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { VideoAdService } = require('../lib/services/video_ad_service');
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');
const ffprobeInstaller = require('@ffprobe-installer/ffprobe');

const ffmpegPath = ffmpegInstaller.path;
const ffprobePath = ffprobeInstaller.path;

async function runVerification() {
  console.log('--- Testing Video Ad Trimming & Duration Probing ---');
  console.log('FFmpeg binary:', ffmpegPath);
  console.log('FFprobe binary:', ffprobePath);

  const tmpDir = path.join(__dirname, '../tmp_test_videos');
  if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
  }

  // 1. Generate a 15-second test video with sine audio
  const shortVideoPath = path.join(tmpDir, 'short_15s.mp4');
  console.log('Generating 15s test video with audio...');
  spawnSync(ffmpegPath, [
    '-y',
    '-f', 'lavfi', '-i', 'testsrc=duration=15:size=320x240:rate=15',
    '-f', 'lavfi', '-i', 'sine=frequency=1000:duration=15',
    '-c:v', 'libx264',
    '-c:a', 'aac',
    shortVideoPath
  ]);

  // 2. Generate a 45-second test video with sine audio
  const longVideoPath = path.join(tmpDir, 'long_45s.mp4');
  console.log('Generating 45s test video with audio...');
  spawnSync(ffmpegPath, [
    '-y',
    '-f', 'lavfi', '-i', 'testsrc=duration=45:size=320x240:rate=15',
    '-f', 'lavfi', '-i', 'sine=frequency=800:duration=45',
    '-c:v', 'libx264',
    '-c:a', 'aac',
    longVideoPath
  ]);

  // TEST 1: Short video (15s <= 30s) -> should NOT be trimmed
  console.log('\n--- TEST 1: Processing 15s video (<= 30s limit) ---');
  const shortBuffer = fs.readFileSync(shortVideoPath);
  const result1 = await VideoAdService.processVideoAd(shortBuffer, 'short_15s.mp4');
  console.log('Result 1: duration =', result1.finalDuration, 'trimmed =', result1.trimmed);
  if (!result1.trimmed && Math.abs(result1.finalDuration - 15) < 1.0) {
    console.log('✓ PASS: 15s video kept as-is without trimming');
  } else {
    throw new Error('FAIL: 15s video was unexpectedly modified');
  }

  // TEST 2: Long video (45s > 30s) -> should BE TRIMMED to <= 30s with audio
  console.log('\n--- TEST 2: Processing 45s video (> 30s limit) ---');
  const longBuffer = fs.readFileSync(longVideoPath);
  const result2 = await VideoAdService.processVideoAd(longBuffer, 'long_45s.mp4');
  console.log('Result 2: duration =', result2.finalDuration, 'trimmed =', result2.trimmed);

  if (result2.trimmed && result2.finalDuration <= 30.5) {
    console.log('✓ PASS: 45s video successfully trimmed to', result2.finalDuration, 'seconds');
  } else {
    throw new Error(`FAIL: 45s video not properly trimmed: trimmed=${result2.trimmed}, duration=${result2.finalDuration}`);
  }

  // Verify trimmed video has audio
  const probeTrimmed = spawnSync(ffprobePath, [
    '-v', 'error',
    '-show_entries', 'stream=codec_type',
    '-of', 'json',
    '-i', 'pipe:0'
  ], { input: result2.buffer });
  const probeJson = JSON.parse(probeTrimmed.stdout.toString());
  const streams = probeJson.streams || [];
  const hasVideo = streams.some(s => s.codec_type === 'video');
  const hasAudio = streams.some(s => s.codec_type === 'audio');
  console.log('Trimmed stream check -> hasVideo:', hasVideo, 'hasAudio:', hasAudio);

  if (hasVideo && hasAudio) {
    console.log('✓ PASS: Trimmed video has both video and audio preserved intact!');
  } else {
    throw new Error('FAIL: Trimmed video missing audio or video stream');
  }

  // Clean up tmp files
  try {
    fs.unlinkSync(shortVideoPath);
    fs.unlinkSync(longVideoPath);
    fs.rmdirSync(tmpDir);
  } catch (_) {}

  console.log('\n========================================');
  console.log('ALL VIDEO AD PROBING & TRIMMING CHECKS PASSED');
  console.log('========================================');
}

runVerification().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
