// Firebase Cloud Messaging (HTTP v1) using a service account stored in the
// FIREBASE_SERVICE_ACCOUNT secret (the full JSON file contents).

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedToken: { token: string; exp: number } | null = null;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    console.error("FIREBASE_SERVICE_ACCOUNT is not valid JSON");
    return null;
  }
}

async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.token;

  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const jwt = `${header}.${claims}.${b64url(sig)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`FCM auth failed: ${JSON.stringify(data)}`);
  cachedToken = { token: data.access_token, exp: now + (data.expires_in ?? 3600) };
  return cachedToken.token;
}

/**
 * Sends one push. Never throws: a failed notification must not fail the
 * attendance scan or payment that triggered it.
 */
export async function sendPush(
  token: string | null | undefined,
  title: string,
  body: string,
  data: Record<string, string> = {},
): Promise<boolean> {
  if (!token) return false;
  const sa = serviceAccount();
  if (!sa) {
    console.warn("FIREBASE_SERVICE_ACCOUNT not set – skipping push:", title);
    return false;
  }
  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${await accessToken(sa)}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body },
            data,
            android: { priority: "high", notification: { channel_id: "main", sound: "default" } },
          },
        }),
      },
    );
    if (!res.ok) {
      console.error("FCM send failed", res.status, await res.text());
      return false;
    }
    return true;
  } catch (e) {
    console.error("FCM error", e);
    return false;
  }
}
