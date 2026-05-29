// AIR Kit (Moca) login helper for the dashboard (Faz 1).
//
// Loads the AIR Kit Web SDK from an ESM CDN at call time so the dashboard's
// webpack build gains no new bundled dependency and no node polyfill config is
// required. This keeps the Moca integration additive and removable: deleting
// this file and the AIR button reverts the dashboard to wallet-only login.
//
// The SDK runs in the browser only; this function must be called from a client
// component in response to a user action.

export interface AirLoginResult {
  readonly token: string;
  readonly address: string;
}

const AIRKIT_ESM_URL = "https://esm.sh/@mocanetwork/airkit@1.9.0-beta.3";

export async function loginWithAirAccount(): Promise<AirLoginResult> {
  const partnerId = process.env.NEXT_PUBLIC_MOCA_PARTNER_ID;
  if (!partnerId) {
    throw new Error("NEXT_PUBLIC_MOCA_PARTNER_ID is not configured");
  }

  // Dynamic, webpack-ignored import so the SDK is fetched as native ESM in the
  // browser rather than bundled by Next.
  const mod = await import(/* webpackIgnore: true */ AIRKIT_ESM_URL);
  const AirService = mod.AirService;
  const BUILD_ENV = mod.BUILD_ENV;

  const service = new AirService({ partnerId });
  await service.init({ buildEnv: BUILD_ENV.SANDBOX, enableLogging: true, skipRehydration: false });

  const result = await service.login();
  const token = result?.token;
  const address = result?.abstractAccountAddress;
  if (!token || !address) {
    throw new Error("AIR login did not return a token and abstract account address");
  }
  return { token, address };
}
