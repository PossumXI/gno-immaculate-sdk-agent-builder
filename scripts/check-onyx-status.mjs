#!/usr/bin/env node
/**
 * Zero-dependency Gno.land Onyx (onyx-1) on-chain deployment & inert-queue verifier.
 *
 * Usage:
 *   node scripts/check-onyx-status.mjs [--namespace <g1...>] [--remote https://rpc.onyx.testnets.gno.land]
 *   node scripts/check-onyx-status.mjs --offline-self-test
 *
 * Distinguishes between:
 *   1. ACTIVE packages/realms (queryable via `vm/qfile` / `vm/qrender` on Onyx).
 *   2. SUBMITTED_INERT packages/realms (recorded on-chain in `vm/qinertpaths`, awaiting Onyx approver `enablepkg`).
 *   3. NOT_SUBMITTED paths (not yet broadcast at that versioned path).
 */

import assert from 'node:assert/strict';

export function classifyOnyxPathState({ path, qfileData, inertPaths }) {
  const inertSet = new Set(
    String(inertPaths || '')
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter(Boolean)
  );
  if (qfileData && !String(qfileData).includes('InvalidPackageError') && !String(qfileData).includes('is not available')) {
    const files = String(qfileData)
      .split(/\r?\n/)
      .map((s) => s.trim())
      .filter((s) => s.endsWith('.gno') || s === 'gnomod.toml');
    return { path, status: 'ACTIVE', files };
  }
  if (inertSet.has(path)) {
    return { path, status: 'SUBMITTED_INERT', files: [] };
  }
  return { path, status: 'NOT_SUBMITTED', files: [] };
}

async function abciQuery(remote, queryPath, dataStr = '') {
  const body = {
    jsonrpc: '2.0',
    id: 1,
    method: 'abci_query',
    params: {
      path: queryPath,
      data: Buffer.from(dataStr, 'utf8').toString('base64'),
    },
  };
  const res = await fetch(remote, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${remote}`);
  const json = await res.json();
  const resp = json?.result?.response || {};
  const decoded = resp.data
    ? Buffer.from(resp.data, 'base64').toString('utf8')
    : resp.value
      ? Buffer.from(resp.value, 'base64').toString('utf8')
      : '';
  return {
    code: resp.code ?? 0,
    error: resp.error || null,
    log: resp.log || '',
    data: decoded,
  };
}

async function main(argv = process.argv.slice(2)) {
  if (argv.includes('--offline-self-test')) {
    const active = classifyOnyxPathState({
      path: 'gno.land/p/g1example/signals',
      qfileData: 'coherence.gno\ndrift.gno\ngnomod.toml\nmath.gno\n',
      inertPaths: 'gno.land/p/g1example/assurance\n',
    });
    assert.equal(active.status, 'ACTIVE');
    assert.deepEqual(active.files, ['coherence.gno', 'drift.gno', 'gnomod.toml', 'math.gno']);

    const inert = classifyOnyxPathState({
      path: 'gno.land/p/g1example/assurance',
      qfileData: 'InvalidPackageError: package is not available',
      inertPaths: 'gno.land/p/g1example/assurance\ngno.land/r/g1example/assurance\n',
    });
    assert.equal(inert.status, 'SUBMITTED_INERT');

    const missing = classifyOnyxPathState({
      path: 'gno.land/r/g1example/effects/v2',
      qfileData: '',
      inertPaths: 'gno.land/p/g1example/assurance\n',
    });
    assert.equal(missing.status, 'NOT_SUBMITTED');
    console.log(JSON.stringify({ ok: true, selfTest: 'PASS' }));
    return;
  }

  let remote = process.env.GNO_REMOTE || 'https://rpc.onyx.testnets.gno.land';
  let namespace = process.env.GNO_ONYX_NAMESPACE || '';
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--remote' && argv[i + 1]) remote = argv[++i];
    else if (argv[i] === '--namespace' && argv[i + 1]) namespace = argv[++i];
  }

  const statusRes = await (await fetch(`${remote.replace(/\/$/, '')}/status`)).json();
  const chainStatus = {
    network: statusRes?.result?.node_info?.network || 'unknown',
    latestBlockHeight: Number(statusRes?.result?.sync_info?.latest_block_height || 0),
    latestBlockTime: statusRes?.result?.sync_info?.latest_block_time || null,
  };

  const inertResp = await abciQuery(remote, 'vm/qinertpaths', namespace);
  const inertLines = inertResp.data.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);

  let packages = [];
  if (namespace) {
    const candidates = [
      `gno.land/p/${namespace}/signals`,
      `gno.land/p/${namespace}/assurance`,
      `gno.land/r/${namespace}/assurance`,
      `gno.land/p/${namespace}/signals/v2`,
      `gno.land/p/${namespace}/assurance/v2`,
      `gno.land/r/${namespace}/assurance/v2`,
      `gno.land/r/${namespace}/effects/v2`,
    ];
    for (const path of candidates) {
      const qf = await abciQuery(remote, 'vm/qfile', path);
      packages.push(classifyOnyxPathState({ path, qfileData: qf.error ? qf.log : qf.data, inertPaths: inertResp.data }));
    }
  }

  console.log(
    JSON.stringify(
      {
        checkedAt: new Date().toISOString(),
        remote,
        chain: chainStatus,
        totalInertQueueCount: inertLines.length,
        namespace: namespace || '(pass --namespace <g1...> to inspect specific submitted paths)',
        packages,
      },
      null,
      2
    )
  );
}

if (import.meta.url === `file://${process.argv[1]?.replace(/\\/g, '/')}` || process.argv[1]?.endsWith('check-onyx-status.mjs')) {
  main().catch((err) => {
    console.error(err.message || err);
    process.exit(1);
  });
}
