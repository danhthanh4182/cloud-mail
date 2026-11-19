import { DatabaseSync } from 'node:sqlite';
export function testDb(schema) {
 const sqlite = new DatabaseSync(':memory:'); sqlite.exec(schema);
 return { sqlite, prepare(sql) { let values=[]; return { bind(...v) { values=v; return this; }, async first() { return sqlite.prepare(sql).get(...values) || null; }, async all() { return {results:sqlite.prepare(sql).all(...values)}; }, async run() { const r=sqlite.prepare(sql).run(...values); return {meta:{changes:Number(r.changes)}}; } }; }, async batch(statements) { sqlite.exec('BEGIN'); try { const results=[]; for(const s of statements)results.push(await s.run()); sqlite.exec('COMMIT');return results; } catch(e){sqlite.exec('ROLLBACK');throw e;} } };
}
