/** In-memory `AlgoliaIndex` for tests: records every call, never touches the network. */
import type { AlgoliaIndex, IndexSettings } from '../src/search/algolia';
import type { ProductRecord } from '../src/search/productRecord';

export type FakeCall =
  | { op: 'saveObject'; index: string; objectID: string }
  | { op: 'saveObjects'; index: string; objectIDs: string[] }
  | { op: 'deleteObject'; index: string; objectID: string }
  | { op: 'setSettings'; index: string; settings: IndexSettings; forwardToReplicas: boolean };

/** Shared by every index opened from one `FakeAlgolia`, like one Algolia application. */
export class FakeAlgolia {
  readonly calls: FakeCall[] = [];
  readonly records = new Map<string, Map<string, ProductRecord>>();
  readonly settings = new Map<string, IndexSettings>();
  /** Set to make every following call reject (simulates an outage). */
  failWith: Error | null = null;

  index(name: string): AlgoliaIndex {
    const store = () => {
      let s = this.records.get(name);
      if (s === undefined) this.records.set(name, (s = new Map()));
      return s;
    };
    const guard = () => {
      if (this.failWith) throw this.failWith;
    };
    return {
      name,
      saveObject: async (record) => {
        guard();
        this.calls.push({ op: 'saveObject', index: name, objectID: record.objectID });
        store().set(record.objectID, structuredClone(record));
      },
      saveObjects: async (records) => {
        guard();
        this.calls.push({ op: 'saveObjects', index: name, objectIDs: records.map((r) => r.objectID) });
        for (const r of records) store().set(r.objectID, structuredClone(r));
      },
      deleteObject: async (objectID) => {
        guard();
        this.calls.push({ op: 'deleteObject', index: name, objectID });
        store().delete(objectID);
      },
      setSettings: async (settings, options = {}) => {
        guard();
        const forwardToReplicas = options.forwardToReplicas ?? false;
        this.calls.push({ op: 'setSettings', index: name, settings, forwardToReplicas });
        this.settings.set(name, { ...this.settings.get(name), ...settings });
      },
    };
  }

  /** Calls that touched `objectID` (any index). */
  callsFor(objectID: string): FakeCall[] {
    return this.calls.filter(
      (c) =>
        ('objectID' in c && c.objectID === objectID) || ('objectIDs' in c && c.objectIDs.includes(objectID)),
    );
  }

  record(index: string, objectID: string): ProductRecord | undefined {
    return this.records.get(index)?.get(objectID);
  }
}
