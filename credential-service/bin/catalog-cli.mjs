#!/usr/bin/env node
// Browse the Moca AIR Kit ecosystem catalog (Bonus). Read-only, no auth.
//
//   node bin/catalog-cli.mjs              # first page of schemas + programs
//   node bin/catalog-cli.mjs search kyc   # search the catalog

import { browseSchemas, browsePrograms, searchCatalog, catalogBase } from "../src/catalog.mjs";

async function main() {
  const [cmd, term] = process.argv.slice(2);
  console.log("catalog host:", catalogBase());

  if (cmd === "search") {
    if (!term) throw new Error("usage: catalog-cli.mjs search <term>");
    const data = await searchCatalog(term, { limit: 10 });
    console.log(`\nsearch "${term}": ${data.total ?? (data.records?.length ?? 0)} result(s)`);
    for (const r of data.records ?? []) console.log("  -", JSON.stringify(r));
    return;
  }

  const schemas = await browseSchemas({ limit: 5 });
  console.log(`\nSchemas (total ${schemas.total}, showing ${schemas.records.length}):`);
  for (const s of schemas.records) {
    console.log(`  - ${s.schemaId}  ${s.title}  (credentials: ${s.credentialCount}, providers: ${s.providerCount})`);
  }

  const programs = await browsePrograms({ limit: 5 });
  console.log(`\nPrograms (total ${programs.total}, showing ${programs.records.length}):`);
  for (const p of programs.records) {
    console.log(`  - ${p.programId}  ${p.name}  (verifications: ${p.verificationCount}, credentials: ${p.credentialCount})`);
  }
}

main().then(() => process.exit(0)).catch((e) => { console.error(String(e.message ?? e)); process.exit(1); });
