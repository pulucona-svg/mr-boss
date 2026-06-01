import {onCall, HttpsError} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import ImageKit from "imagekit";

setGlobalOptions({maxInstances: 10});

const IMAGEKIT_PUBLIC_KEY = defineString("IMAGEKIT_PUBLIC_KEY");
const IMAGEKIT_PRIVATE_KEY = defineString("IMAGEKIT_PRIVATE_KEY");
const IMAGEKIT_URL_ENDPOINT = defineString("IMAGEKIT_URL_ENDPOINT");

let imagekitInstance: ImageKit | null = null;

const getImageKit = () => {
  if (!imagekitInstance) {
    imagekitInstance = new ImageKit({
      publicKey: IMAGEKIT_PUBLIC_KEY.value(),
      privateKey: IMAGEKIT_PRIVATE_KEY.value(),
      urlEndpoint: IMAGEKIT_URL_ENDPOINT.value(),
    });
  }
  return imagekitInstance;
};

/**
 * Get ImageKit Authentication parameters for client-side upload
 */
export const getImageKitAuth = onCall((request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const ik = getImageKit();
  const authParams = ik.getAuthenticationParameters();
  return authParams;
});

/**
 * Upload file to ImageKit (Server-side)
 * request.data: { file: base64String, fileName: string, folder: string }
 */
export const uploadToImageKit = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const {file, fileName, folder} = request.data;
  if (!file || !fileName) {
    throw new HttpsError("invalid-argument", "Missing file or fileName.");
  }

  const ik = getImageKit();
  try {
    const result = await ik.upload({
      file: file, // base64 string or binary
      fileName: fileName,
      folder: folder || "GENERAL",
      useUniqueFileName: true,
    });
    return result;
  } catch (error: any) {
    logger.error("ImageKit upload error:", error);
    throw new HttpsError("internal", "ImageKit upload failed: " + error.message);
  }
});

/**
 * Delete file from ImageKit
 * request.data: { fileId: string }
 */
export const deleteFromImageKit = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const {fileId} = request.data;
  if (!fileId) {
    throw new HttpsError("invalid-argument", "Missing fileId.");
  }

  const ik = getImageKit();
  try {
    await ik.deleteFile(fileId);
    return {success: true};
  } catch (error: any) {
    logger.error("ImageKit deletion error:", error);
    // If the file is already gone, we don't want to throw an error
    if (error.statusCode === 404) {
      return {success: true, message: "File already deleted or not found."};
    }
    throw new HttpsError("internal", "ImageKit deletion failed: " + error.message);
  }
});
