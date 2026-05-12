const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

exports.checkProfileAvailability = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be signed in.");
  }

  const uid = request.auth.uid;
  const data = request.data || {};

  const email = String(data.email || "").trim().toLowerCase();
  const phone = String(data.phone || "").trim();

  let emailUsed = false;
  let phoneUsed = false;

  if (email) {
    try {
      const userRecord = await admin.auth().getUserByEmail(email);
      emailUsed = userRecord.uid !== uid;
    } catch (e) {
      if (e.code !== "auth/user-not-found") {
        throw new HttpsError("internal", "Failed to check email.");
      }
    }
  }

  if (phone) {
    const snap = await admin
      .firestore()
      .collection("users")
      .where("phone", "==", phone)
      .limit(1)
      .get();

    phoneUsed = !snap.empty && snap.docs[0].id !== uid;
  }

  return { emailUsed, phoneUsed };
});