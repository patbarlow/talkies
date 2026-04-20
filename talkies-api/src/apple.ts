import { jwtVerify, createRemoteJWKSet } from "jose";

// jose caches the JWKS response and rotates when Apple rotates keys.
const JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

export interface AppleClaims {
  sub: string;            // stable Apple user ID
  email?: string;
  email_verified?: boolean | string;
  is_private_email?: boolean | string;
  real_user_status?: number;
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  expectedAudience: string,
): Promise<AppleClaims> {
  const { payload } = await jwtVerify(identityToken, JWKS, {
    issuer: "https://appleid.apple.com",
    audience: expectedAudience,
  });
  if (!payload.sub) throw new Error("Apple token missing sub");
  return payload as unknown as AppleClaims;
}
