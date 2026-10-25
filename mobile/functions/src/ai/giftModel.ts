/**
 * The model behind AI Gift Search (SRS §2 "Gemini via Cloud Function
 * aiGiftSearch", §5.6), behind a one-method interface so tests pass a fake.
 *
 * Driver: Gemini through `@google/genai` —
 *  - Vertex AI (default): `vertexai: true`, the function's own project
 *    (GCLOUD_PROJECT), location `global`, Application Default Credentials (the
 *    functions' service account; needs the Vertex AI API enabled on the project);
 *  - the Gemini Developer API when an API key is given (the `GEMINI_API_KEY`
 *    secret, when the owner binds it to aiGiftSearch).
 * The SDK is loaded lazily, so it costs nothing for the other functions' cold starts.
 */
import type { JsonPrompt } from './giftSearchPrompts';

/**
 * Flash-Lite: ~1.5 s per call in production (Oct 2026) — the full Flash models
 * took 11–40 s+ per call with their default thinking and timed out the
 * two-step search. Override with the GEMINI_MODEL param.
 */
export const DEFAULT_GEMINI_MODEL = 'gemini-3.5-flash-lite';
/** Vertex AI location of the model endpoint. */
export const GEMINI_LOCATION = 'global';
/** Per call; the callable itself has 60 s. */
export const GEMINI_TIMEOUT_MS = 20_000;

/** Returns the parsed JSON the model produced for `prompt` (throws on any failure). */
export interface GiftSearchModel {
  /** Logged on `ai_searches.model`, e.g. `vertex:gemini-3.5-flash-lite`. */
  readonly name: string;
  generateJson(prompt: JsonPrompt): Promise<unknown>;
}

export interface GeminiOptions {
  model?: string;
  /** Gemini Developer API key; absent = Vertex AI. */
  apiKey?: string;
  /** Vertex AI project; default GCLOUD_PROJECT / GOOGLE_CLOUD_PROJECT. */
  project?: string;
  location?: string;
  timeoutMs?: number;
}

/** Minimal shape of the SDK client this driver uses. */
interface GenAiClient {
  models: {
    generateContent(params: {
      model: string;
      contents: string;
      config: Record<string, unknown>;
    }): Promise<{ text?: string | undefined }>;
  };
}

export function geminiModel(options: GeminiOptions = {}): GiftSearchModel {
  const model = options.model?.trim() || DEFAULT_GEMINI_MODEL;
  const apiKey = options.apiKey?.trim() || undefined;
  const project = options.project ?? process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT;
  const location = options.location ?? GEMINI_LOCATION;
  const timeout = options.timeoutMs ?? GEMINI_TIMEOUT_MS;
  let client: Promise<GenAiClient> | null = null;

  const getClient = (): Promise<GenAiClient> => {
    client ??= import('@google/genai').then(({ GoogleGenAI }) => {
      if (apiKey !== undefined) return new GoogleGenAI({ apiKey }) as unknown as GenAiClient;
      if (!project) throw new Error('Vertex AI needs a project id (GCLOUD_PROJECT)');
      return new GoogleGenAI({ vertexai: true, project, location }) as unknown as GenAiClient;
    });
    return client;
  };

  return {
    name: `${apiKey !== undefined ? 'gemini-api' : 'vertex'}:${model}`,
    async generateJson(prompt: JsonPrompt): Promise<unknown> {
      const ai = await getClient();
      const response = await ai.models.generateContent({
        model,
        contents: prompt.prompt,
        config: {
          systemInstruction: prompt.system,
          responseMimeType: 'application/json',
          responseSchema: prompt.schema,
          temperature: 0.2,
          httpOptions: { timeout },
        },
      });
      const text = response.text;
      if (typeof text !== 'string' || text.trim().length === 0) throw new Error('empty model response');
      return JSON.parse(text) as unknown;
    },
  };
}
