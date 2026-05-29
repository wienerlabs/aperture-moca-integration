// Moca AIR Kit Catalog reader (Bonus). Read-only browse of ecosystem schemas
// and programs. No partner auth is required during the pilot.
//
// The catalog is served from the credential API host (NOT the
// api.*.mocachain.org host, whose /v1/catalog/* routes return 404). The base
// host is configured via MOCA_CATALOG_API.

import { config } from "./config.mjs";

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";

function base() {
  const b = process.env.MOCA_CATALOG_API || "https://credential-testnet.api.sandbox.air3.com";
  return b.replace(/\/+$/, "");
}

async function get(path) {
  const res = await fetch(`${base()}${path}`, {
    headers: { "User-Agent": UA, Accept: "application/json" },
  });
  const json = await res.json();
  // Envelope: { code: 80000000 (success), msg, data: { records, total, pages } }
  if (json.code !== 80000000) {
    throw new Error(`catalog error ${json.code}: ${JSON.stringify(json.msg)}`);
  }
  return json.data;
}

export async function browseSchemas({ page = 1, limit = 10 } = {}) {
  return get(`/catalog/schemas?page=${page}&limit=${limit}`);
}

export async function browsePrograms({ page = 1, limit = 10 } = {}) {
  return get(`/catalog/programs?page=${page}&limit=${limit}`);
}

export async function searchCatalog(q, { page = 1, limit = 10 } = {}) {
  return get(`/catalog/search?q=${encodeURIComponent(q)}&page=${page}&limit=${limit}`);
}

// Reference config so a misconfigured base surfaces clearly at import sites.
export const catalogBase = base;
void config;
