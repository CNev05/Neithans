import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import axios from 'axios';
import { google } from 'googleapis';

admin.initializeApp();
const db = admin.firestore();

// God View Bridge Configuration
const LARAVEL_WEBHOOK_URL = functions.config().laravel?.webhook_url || '';
const ABODE_SECRET_KEY = functions.config().laravel?.secret_key || '';
const UNISMS_API_KEY = () => process.env.UNISMS_API_KEY || functions.config().unisms?.key || '';
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'dormmate-6dc56';

const writableCollections = new Set(['owners', 'rooms', 'tenants', 'payments', 'sms_queue']);

export const provisionOwner = functions.auth.user().onCreate(async (user) => {
  const provisioningRef = db.collection('admin_provisioning').doc(user.email?.toLowerCase() || user.uid);
  const provisioning = await provisioningRef.get();
  const currentClaims = (await admin.auth().getUser(user.uid)).customClaims || {};
  if (!provisioning.exists && !currentClaims.role) {
    await admin.auth().setCustomUserClaims(user.uid, { superadmin: false, owner: true, role: 'owner' });
  }
  await db.collection('users').doc(user.uid).set({
    uid: user.uid,
    email: user.email || null,
    phoneNumber: user.phoneNumber || null,
    displayName: user.displayName || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

function isSuperAdmin(context: functions.https.CallableContext): boolean {
  return context.auth?.token.superadmin === true || context.auth?.token.role === 'superadmin';
}

function isOwner(context: functions.https.CallableContext): boolean {
  return context.auth?.token.owner === true || context.auth?.token.role === 'owner';
}

async function audit(context: functions.https.CallableContext, action: string, collection: string, documentId: string, metadata: Record<string, unknown> = {}) {
  await db.collection('audit_logs').add({
    actorUid: context.auth?.uid || 'system',
    action,
    collection,
    documentId,
    metadata,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

export const mutateRecord = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Signed in user required.');
  const { collection, id, values, operation = 'upsert' } = data || {};
  if (!writableCollections.has(collection) || typeof values !== 'object' || !values) {
    throw new functions.https.HttpsError('invalid-argument', 'Invalid collection or record.');
  }

  const ref = id ? db.collection(collection).doc(id) : db.collection(collection).doc();
  const existing = await ref.get();
  const existingData = existing.data() || {};
  const ownerId = values.ownerId || existingData.ownerId;
  if (isOwner(context) && (!ownerId || ownerId !== context.auth?.uid)) {
    throw new functions.https.HttpsError('permission-denied', 'Owners may only change their own records.');
  }
  const allowed = isSuperAdmin(context) || (isOwner(context) && ownerId === context.auth.uid);
  if (!allowed) throw new functions.https.HttpsError('permission-denied', 'You do not own this record.');
  if (operation === 'delete') {
    if (!existing.exists) return { id: ref.id, deleted: false };
    await ref.delete();
    await audit(context, 'delete', collection, ref.id);
    return { id: ref.id, deleted: true };
  }

  const record = {
    ...values,
    ...(ownerId ? { ownerId } : {}),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(existing.exists ? {} : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
  };
  await ref.set(record, { merge: true });
  await audit(context, existing.exists ? 'update' : 'create', collection, ref.id, { ownerId });
  return { id: ref.id };
});

export const setRole = functions.https.onCall(async (data, context) => {
  if (!isSuperAdmin(context)) throw new functions.https.HttpsError('permission-denied', 'superadmin only');
  const { uid, role } = data || {};
  if (typeof uid !== 'string' || !['owner', 'superadmin'].includes(role)) {
    throw new functions.https.HttpsError('invalid-argument', 'Valid uid and role required.');
  }
  const claims = role === 'superadmin'
    ? { superadmin: true, owner: false, role: 'superadmin' }
    : { superadmin: false, owner: true, role: 'owner' };
  await admin.auth().setCustomUserClaims(uid, claims);
  await db.collection('admins').doc(uid).set({ role, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  await audit(context, 'set_role', 'users', uid, { role });
  return { success: true, claims };
});

export const createAdmin = functions.https.onCall(async (data, context) => {
  if (!isSuperAdmin(context)) throw new functions.https.HttpsError('permission-denied', 'superadmin only');
  const { email, password, displayName, role = 'owner', permissions = [] } = data || {};
  if (typeof email !== 'string' || typeof password !== 'string' || password.length < 8 || !['owner', 'superadmin'].includes(role)) {
    throw new functions.https.HttpsError('invalid-argument', 'Email, password (8+ characters), and a valid role are required.');
  }
  const provisioningRef = db.collection('admin_provisioning').doc(email.trim().toLowerCase());
  await provisioningRef.set({ role, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  try {
    const user = await admin.auth().createUser({ email: email.trim(), password, displayName: displayName || undefined });
    const claims = role === 'superadmin'
      ? { superadmin: true, owner: false, role, permissions }
      : { superadmin: false, owner: true, role, permissions };
    await admin.auth().setCustomUserClaims(user.uid, claims);
    await db.collection('admins').doc(user.uid).set({ uid: user.uid, email: user.email, displayName: user.displayName || '', role, permissions, disabled: false, createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    await provisioningRef.delete();
    await audit(context, 'create_admin', 'admins', user.uid, { email: user.email, role, permissions });
    return { uid: user.uid };
  } catch (error: any) {
    await provisioningRef.delete().catch(() => undefined);
    if (error.code === 'auth/email-already-exists') throw new functions.https.HttpsError('already-exists', 'An account with this email already exists.');
    throw new functions.https.HttpsError('internal', 'Unable to create admin account.');
  }
});

export const setAdminStatus = functions.https.onCall(async (data, context) => {
  if (!isSuperAdmin(context)) throw new functions.https.HttpsError('permission-denied', 'superadmin only');
  const { uid, disabled } = data || {};
  if (typeof uid !== 'string' || typeof disabled !== 'boolean' || uid === context.auth?.uid) throw new functions.https.HttpsError('invalid-argument', 'Valid user and status required.');
  await admin.auth().updateUser(uid, { disabled });
  await db.collection('admins').doc(uid).set({ disabled, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  await audit(context, disabled ? 'disable_admin' : 'enable_admin', 'admins', uid);
  return { success: true };
});

export const deleteAdmin = functions.https.onCall(async (data, context) => {
  if (!isSuperAdmin(context)) throw new functions.https.HttpsError('permission-denied', 'superadmin only');
  const { uid } = data || {};
  if (typeof uid !== 'string' || uid === context.auth?.uid) throw new functions.https.HttpsError('invalid-argument', 'A different admin UID is required.');
  await admin.auth().deleteUser(uid);
  await db.collection('admins').doc(uid).delete();
  await audit(context, 'delete_admin', 'admins', uid);
  return { success: true };
});

// Rate limiter using Firestore transaction to prevent race conditions
async function checkRateLimit(uid: string, action: string, maxRequests: number = 10, windowMinutes: number = 1): Promise<boolean> {
  const rateLimitRef = db.collection('rate_limits').doc(`${uid}_${action}`);
  const windowMs = windowMinutes * 60 * 1000;

  return db.runTransaction(async (txn) => {
    const doc = await txn.get(rateLimitRef);
    const now = Date.now();

    if (!doc.exists) {
      txn.set(rateLimitRef, { count: 1, windowStart: now, lastRequest: now });
      return true;
    }

    const data = doc.data()!;
    const windowStart: number = data.windowStart;

    if (now - windowStart > windowMs) {
      txn.set(rateLimitRef, { count: 1, windowStart: now, lastRequest: now });
      return true;
    }

    if (data.count >= maxRequests) return false;

    txn.update(rateLimitRef, { count: admin.firestore.FieldValue.increment(1), lastRequest: now });
    return true;
  });
}

async function sendUniSms(to: string, body: string): Promise<boolean> {
  const apiKey = UNISMS_API_KEY();
  if (!apiKey) throw new Error('UNISMS_API_KEY not configured.');
  const basicAuth = 'Basic ' + Buffer.from(`${apiKey}:`).toString('base64');
  const normalizedTo = normalizePhilippinePhone(to);
  if (!normalizedTo) throw new Error('Invalid Philippine recipient number.');
  const response = await axios.post('https://unismsapi.com/api/sms', {
    sender: 'Neithans',
    recipient: normalizedTo,
    content: body,
  }, {
    headers: { 'Authorization': basicAuth, 'Content-Type': 'application/json', 'Accept': 'application/json' },
    timeout: 10000,
  });
  return response.status === 200 || response.status === 201;
}

function normalizePhilippinePhone(value: string): string | null {
  let digits = value.replace(/\D/g, '');
  if (digits.startsWith('00')) digits = digits.slice(2);
  if (digits.startsWith('0')) digits = `63${digits.slice(1)}`;
  if (digits.startsWith('9') && digits.length === 10) digits = `63${digits}`;
  return /^639\d{9}$/.test(digits) ? `+${digits}` : null;
}

/**
 * Trigger: On any write to payments/{paymentId}
 * Mirrors payment data to the Laravel MySQL database for Super Admin oversight.
 */
export const mirrorToMySQL = functions.firestore
  .document('payments/{paymentId}')
  .onWrite(async (change, context) => {
    if (!LARAVEL_WEBHOOK_URL) return null;
    const paymentId = context.params.paymentId;
    const data = change.after.exists ? change.after.data() : null;
    const payload = {
      id: paymentId,
      data,
      event: !change.before.exists ? 'created' : (!change.after.exists ? 'deleted' : 'updated'),
      timestamp: admin.firestore.Timestamp.now().toMillis(),
    };
    try {
      await axios.post(LARAVEL_WEBHOOK_URL, payload, {
        headers: { 'X-Abode-Secret-Key': ABODE_SECRET_KEY, 'Content-Type': 'application/json' },
        timeout: 5000,
      });
      console.log(`Mirrored payment ${paymentId} to MySQL.`);
    } catch (error: any) {
      console.error(`Failed to mirror payment ${paymentId}:`, error.message);
      await db.collection('failed_syncs').add({
        paymentId, payload, error: error.message, retryCount: 0,
        lastAttempt: admin.firestore.Timestamp.now(),
      });
    }
    return null;
  });

export const sendDirectSms = functions.https.onCall(async (data, context) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Signed in user required.');
  const { to, message } = data || {};
  if (typeof to !== 'string' || typeof message !== 'string' || !message.trim()) {
    throw new functions.https.HttpsError('invalid-argument', 'Recipient and message required.');
  }
  if (!isSuperAdmin(context) && !isOwner(context)) {
    throw new functions.https.HttpsError('permission-denied', 'Owner or superadmin access required.');
  }
  const rateLimitOk = await checkRateLimit(context.auth.uid, 'direct_sms', 5, 1);
  if (!rateLimitOk) throw new functions.https.HttpsError('resource-exhausted', 'Too many requests.');
  try {
    const ok = await sendUniSms(to, message);
    return { success: ok };
  } catch (error: any) {
    console.error('UniSMS Error:', error.response?.status || error.message);
    throw new functions.https.HttpsError('internal', 'SMS provider failed. Check the server-side SMS configuration and provider account.');
  }
});

// Scheduled: runs on 27th of every month at 00:00 UTC
export const scheduledMonthlyReminder = functions.pubsub
  .schedule('0 0 27 * *').timeZone('UTC')
  .onRun(async (_context) => {
    const now = admin.firestore.Timestamp.now();
    const month = new Date().getMonth() + 1;
    const year = new Date().getFullYear();

    const tenantsSnap = await db.collection('tenants').get();

    for (const t of tenantsSnap.docs) {
      const tenant = t.data();
      const tenantId = t.id;

      const payments = await db.collection('payments')
        .where('tenantId', '==', tenantId)
        .where('month', '==', month)
        .where('year', '==', year)
        .get();

      // Fixed: was 'paid' (lowercase) — must match Flutter which stores 'Paid'
      const paid = payments.docs.some(p => p.data().status === 'Paid');

      if (!paid) {
        const reminderId = `rent_${tenantId}_${year}_${month}`;
        const smsRef = db.collection('sms_queue').doc(reminderId);
        const existingReminder = await smsRef.get();
        if (existingReminder.exists) continue;

        const reminder = {
          ownerId: tenant.ownerId || null,
          tenantId,
          body: `Reminder: Rent for ${month}/${year} is due. Please pay promptly.`,
          template: 'reminder',
          scheduledAt: now,
          status: 'queued',
          createdAt: now,
        }
        await smsRef.set(reminder);

        try {
          const tenantPhone = tenant.phone;
          if (!tenantPhone) throw new Error('Tenant phone missing.');
          await sendUniSms(tenantPhone, reminder.body);
          await smsRef.update({ status: 'sent', sentAt: admin.firestore.Timestamp.now() });
        } catch (error: any) {
          console.error(`Reminder SMS failed for ${tenantId}:`, error.message);
          await smsRef.update({ status: 'failed', error: error.message, failedAt: admin.firestore.Timestamp.now() });
        }
      }
    }
    return null;
  });

export const sendSmsFromQueue = functions.https.onRequest(async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    const idToken = authHeader.split('Bearer ')[1];
    if (!idToken) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    let decodedToken;
    try {
      decodedToken = await admin.auth().verifyIdToken(idToken);
    } catch {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const rateLimitOk = await checkRateLimit(decodedToken.uid, 'send_sms', 10, 1);
    if (!rateLimitOk) {
      res.status(429).json({ error: 'Rate limit exceeded' });
      return;
    }

    const { smsId } = req.query;
    if (!smsId || typeof smsId !== 'string') {
      res.status(400).json({ error: 'Valid smsId required' });
      return;
    }

    const docRef = db.collection('sms_queue').doc(smsId);
    const doc = await docRef.get();
    if (!doc.exists) {
      res.status(404).json({ error: 'Not found' });
      return;
    }

    const data = doc.data() as any;
    if (data.status === 'sent') {
      res.status(200).json({ message: 'Already sent' });
      return;
    }

    if (decodedToken.superadmin !== true && data.ownerId !== decodedToken.uid) {
      res.status(403).json({ error: 'Forbidden' });
      return;
    }

    const tenantSnap = await db.collection('tenants').doc(data.tenantId).get();
    const to = (tenantSnap.data() as any)?.phone;
    if (!to) {
      res.status(400).json({ error: 'Phone missing' });
      return;
    }

    await sendUniSms(to, data.body);
    await docRef.update({ status: 'sent', sentAt: admin.firestore.Timestamp.now() });
    res.status(200).json({ success: true });
    return;
  } catch (err: any) {
    console.error('sendSmsFromQueue error:', err.message);
    res.status(500).json({ error: 'Internal error' });
    return;
  }
});

export const analyticsExport = functions.https.onRequest(async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }
    const idToken = authHeader.split('Bearer ')[1];
    if (!idToken) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const decodedToken = await admin.auth().verifyIdToken(idToken);
    if (decodedToken.superadmin !== true && decodedToken.role !== 'superadmin') {
      res.status(403).json({ error: 'Forbidden' });
      return;
    }

    const snapshot = await db.collection('analytics').orderBy('month', 'desc').limit(12).get();
    res.json({ data: snapshot.docs.map(d => d.data()) });
    return;
  } catch (error: any) {
    console.error('analyticsExport error:', error.message);
    res.status(500).json({ error: 'Internal error' });
    return;
  }
});

export const scheduledFirestoreBackup = functions.pubsub
  .schedule('0 2 * * *').timeZone('UTC')
  .onRun(async () => {
    const bucket = functions.config().backup?.bucket || `${PROJECT_ID}.appspot.com`;
    const auth = await google.auth.getClient({ scopes: ['https://www.googleapis.com/auth/datastore'] });
    const firestore = google.firestore({ version: 'v1', auth });
    const outputUriPrefix = `gs://${bucket}/firestore-backups/${new Date().toISOString().slice(0, 10)}`;
    const result = await firestore.projects.databases.exportDocuments({
      name: `projects/${PROJECT_ID}/databases/(default)`,
      requestBody: { outputUriPrefix },
    });
    await db.collection('backups').add({
      outputUriPrefix,
      operation: result.data.name || null,
      status: 'started',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return null;
  });
