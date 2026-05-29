const openAIAPIKey = Deno.env.get("OPENAI_API_KEY");
const openAIModel = Deno.env.get("OPENAI_MODEL") ?? "gpt-5-mini";
const appStoreIssuerID = Deno.env.get("APP_STORE_ISSUER_ID");
const appStoreKeyID = Deno.env.get("APP_STORE_KEY_ID");
const appStorePrivateKey = Deno.env.get("APP_STORE_PRIVATE_KEY");
const appStoreBundleID = Deno.env.get("APP_STORE_BUNDLE_ID") ?? "wolf.Flashcards";
const appStoreEnvironment = (Deno.env.get("APP_STORE_ENVIRONMENT") ?? "auto").toLowerCase();
const aiSubscriptionProductID = Deno.env.get("AI_SUBSCRIPTION_PRODUCT_ID") ?? "flashcards_ai_monthly";
const aiSubscriptionBypass = Deno.env.get("AI_SUBSCRIPTION_BYPASS") === "true";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const cardSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    cards: {
      type: "array",
      minItems: 1,
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          question: { type: "string" },
          answer: { type: "string" },
          questionSpeechSegments: {
            type: "array",
            minItems: 1,
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                text: { type: "string" },
                languageCode: { type: "string" },
              },
              required: ["text", "languageCode"],
            },
          },
          answerSpeechSegments: {
            type: "array",
            minItems: 1,
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                text: { type: "string" },
                languageCode: { type: "string" },
              },
              required: ["text", "languageCode"],
            },
          },
          deckName: { type: "string" },
        },
        required: ["question", "answer", "questionSpeechSegments", "answerSpeechSegments", "deckName"],
      },
    },
  },
  required: ["cards"],
};

const simplifiedAnswerSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer: { type: "string" },
    answerSpeechSegments: {
      type: "array",
      minItems: 1,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          text: { type: "string" },
          languageCode: { type: "string" },
        },
        required: ["text", "languageCode"],
      },
    },
  },
  required: ["answer", "answerSpeechSegments"],
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  if (!openAIAPIKey) {
    return jsonResponse({ error: "OPENAI_API_KEY is not configured in Supabase secrets." }, 500);
  }

  try {
    const body = await request.json();
    const subscription = await validateAISubscription(body);

    if (!subscription.isValid) {
      return jsonResponse({ error: subscription.message }, subscription.status);
    }

    switch (body.action) {
    case "generate_cards":
      return jsonResponse(await generateCards(body));
    case "simplify_answer":
      return jsonResponse(await simplifyAnswer(body));
    default:
      return jsonResponse({ error: "Unknown action." }, 400);
    }
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});

async function validateAISubscription(body: Record<string, unknown>): Promise<{ isValid: boolean; status: number; message: string }> {
  if (aiSubscriptionBypass) {
    return { isValid: true, status: 200, message: "Subscription bypass is enabled." };
  }

  if (!appStoreIssuerID || !appStoreKeyID || !appStorePrivateKey) {
    return { isValid: false, status: 500, message: "App Store subscription verification is not configured." };
  }

  const appStoreTransactionJWS = clean(body.appStoreTransactionJWS);

  if (!appStoreTransactionJWS) {
    return { isValid: false, status: 402, message: "Für KI-Funktionen ist ein aktives Abo erforderlich." };
  }

  const localPayload = decodeJWSPayload(appStoreTransactionJWS);
  const transactionID = clean(localPayload.transactionId);

  if (!transactionID) {
    return { isValid: false, status: 402, message: "Der App-Store-Kaufnachweis ist ungültig." };
  }

  let signedTransactionInfo: string;
  try {
    signedTransactionInfo = await fetchSignedTransactionInfo(transactionID);
  } catch {
    return {
      isValid: false,
      status: 402,
      message: "Der Kaufnachweis konnte bei Apple nicht geprüft werden. Lokale Xcode-StoreKit-Käufe funktionieren nur für den Kaufdialog; teste die echte KI-Freischaltung über Sandbox oder TestFlight.",
    };
  }

  const verifiedPayload = decodeJWSPayload(signedTransactionInfo);
  const expiresDate = Number(verifiedPayload.expiresDate ?? 0);
  const bundleID = clean(verifiedPayload.bundleId);
  const productID = clean(verifiedPayload.productId);
  const revocationDate = Number(verifiedPayload.revocationDate ?? 0);

  if (bundleID !== appStoreBundleID) {
    return { isValid: false, status: 403, message: "Der Kaufnachweis gehört nicht zu dieser App." };
  }

  if (productID !== aiSubscriptionProductID) {
    return { isValid: false, status: 403, message: "Der Kaufnachweis gehört nicht zum KI-Abo." };
  }

  if (revocationDate > 0) {
    return { isValid: false, status: 402, message: "Das KI-Abo wurde widerrufen." };
  }

  if (!Number.isFinite(expiresDate) || expiresDate <= Date.now()) {
    return { isValid: false, status: 402, message: "Das KI-Abo ist nicht aktiv." };
  }

  return { isValid: true, status: 200, message: "KI-Abo aktiv." };
}

async function fetchSignedTransactionInfo(transactionID: string): Promise<string> {
  const jwt = await createAppStoreJWT();
  const environments = appStoreEnvironment === "sandbox"
    ? ["sandbox"]
    : appStoreEnvironment === "production"
    ? ["production"]
    : ["production", "sandbox"];

  let lastError = "App Store verification failed.";

  for (const environment of environments) {
    const baseURL = environment === "sandbox"
      ? "https://api.storekit-sandbox.itunes.apple.com"
      : "https://api.storekit.itunes.apple.com";
    const response = await fetch(`${baseURL}/inApps/v1/transactions/${transactionID}`, {
      headers: {
        authorization: `Bearer ${jwt}`,
      },
    });

    if (response.ok) {
      const payload = await response.json();
      const signedTransactionInfo = clean(payload.signedTransactionInfo);

      if (signedTransactionInfo) {
        return signedTransactionInfo;
      }

      lastError = "App Store returned no signed transaction info.";
      continue;
    }

    lastError = `App Store verification failed with ${response.status}.`;
  }

  throw new Error(lastError);
}

async function createAppStoreJWT(): Promise<string> {
  const issuedAt = Math.floor(Date.now() / 1000);
  const expiresAt = issuedAt + 15 * 60;
  const header = {
    alg: "ES256",
    kid: appStoreKeyID,
    typ: "JWT",
  };
  const payload = {
    iss: appStoreIssuerID,
    iat: issuedAt,
    exp: expiresAt,
    aud: "appstoreconnect-v1",
    bid: appStoreBundleID,
  };
  const signingInput = `${base64URLEncode(JSON.stringify(header))}.${base64URLEncode(JSON.stringify(payload))}`;
  const key = await importAppStorePrivateKey(appStorePrivateKey ?? "");
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64URLEncode(new Uint8Array(signature))}`;
}

async function importAppStorePrivateKey(privateKey: string): Promise<CryptoKey> {
  const normalized = privateKey.replaceAll("\\n", "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyData = Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function decodeJWSPayload(jws: string): Record<string, unknown> {
  const payload = jws.split(".")[1];

  if (!payload) {
    return {};
  }

  try {
    return JSON.parse(new TextDecoder().decode(base64URLDecode(payload)));
  } catch {
    return {};
  }
}

function base64URLEncode(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function base64URLDecode(value: string): Uint8Array {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

async function generateCards(body: Record<string, unknown>) {
  const topic = clean(body.topic);
  const difficultyLevel = clean(body.difficultyLevel) || clean(body.gradeLevel) || "Allgemein";
  const deckName = clean(body.deckName) || topic || "KI";
  const count = clamp(Number(body.count ?? 10), 5, 20);
  const difficultyProfile = profileForDifficulty(difficultyLevel);
  const appLanguage = languageNameForCode(clean(body.language) || "de");
  const answerLanguage = languageNameForCode(clean(body.answerLanguageCode) || "de-DE");
  const appLanguageCode = normalizeLanguageCode(clean(body.language) || "de-DE");
  const answerLanguageCode = normalizeLanguageCode(clean(body.answerLanguageCode) || "de-DE");

  if (!topic) {
    throw new Error("topic is required");
  }

  return callOpenAI({
    schemaName: "flashcards",
    schema: cardSchema,
    input: [
      {
        role: "system",
        content:
          "Du bist eine ruhige, präzise Lernhilfe. Erzeuge Karteikarten mit klar unterscheidbarem Schwierigkeitsgrad. Jede Karte muss als Frage und kurze Antwort funktionieren.",
      },
      {
        role: "user",
        content:
          `Erzeuge ${count} Karteikarten zum Thema "${topic}" auf dem Schwierigkeitslevel "${difficultyLevel}". ` +
          `Nutze den Stapelnamen "${deckName}". ` +
          `Schreibe jede Frage ausschließlich in ${appLanguage}. Die Frage darf nicht in ${answerLanguage} formuliert sein, außer bei einzelnen Zielwörtern, Zitaten oder kurzen Beispielsätzen. ` +
          `Schreibe jede Antwort überwiegend in ${answerLanguage}. Wenn die Karte eine Sprachlernkarte ist, darf eine kurze deutsche Einordnung vorkommen, aber die eigentliche Antwort muss in ${answerLanguage} stehen. ` +
          `Gib questionSpeechSegments und answerSpeechSegments aus. Die questionSpeechSegments müssen zusammen exakt den Fragetext ergeben; die answerSpeechSegments müssen zusammen exakt den Antworttext ergeben. ` +
          `Verwende "${appLanguageCode}" für deutsche/App-sprachliche Erklärteile und "${answerLanguageCode}" für Zielsprachen-Teile. ` +
          "Wenn Frage oder Antwort gemischte Sprachen enthalten, trenne sie sinnvoll in mehrere Segmente. Übersetze fremdsprachige Begriffe, Beispielsätze oder Zitate nicht weg, sondern markiere sie mit ihrer eigenen Sprache. " +
          `Profil fuer dieses Level: ${difficultyProfile} ` +
          "Der Unterschied zwischen den Levels muss deutlich sichtbar sein: Einsteiger fragt nach Begriffen, Wiedererkennen und einfachen Beispielen; Experte fragt nach Begründungen, Transfer, Grenzfällen, typischen Fehlern und präziser Fachsprache. " +
          "Die Fragen sollen klar, einzeln lernbar und nicht zu lang sein. Die Antworten sollen sachlich korrekt sein und genau zum geforderten Anspruch passen. " +
          "Vermeide bei hohen Levels einfache Definitionsfragen, sofern sie nicht mit Analyse, Vergleich oder Anwendung verbunden sind.",
      },
    ],
  });
}

async function simplifyAnswer(body: Record<string, unknown>) {
  const question = clean(body.question);
  const answer = clean(body.answer);
  const mode = clean(body.mode) || "simplify";
  const instruction = instructionForAnswerMode(mode);
  const appLanguage = languageNameForCode(clean(body.language) || "de");
  const answerLanguage = languageNameForCode(clean(body.answerLanguageCode) || "de-DE");
  const appLanguageCode = normalizeLanguageCode(clean(body.language) || "de-DE");
  const answerLanguageCode = normalizeLanguageCode(clean(body.answerLanguageCode) || "de-DE");

  if (!question || !answer) {
    throw new Error("question and answer are required");
  }

  return callOpenAI({
    schemaName: "simplified_answer",
    schema: simplifiedAnswerSchema,
    input: [
      {
        role: "system",
        content:
          "Du bearbeitest nur die Antwort einer Karteikarte. Ersetze die bisherige Antwort vollständig durch eine neue kurze Variante. Hänge nichts an, kombiniere keine früheren Varianten und wiederhole nicht mehrere Optionen gleichzeitig. Bleibe sachlich korrekt, kurz und direkt lernbar. Antworte nur mit der neuen Antwort im JSON-Format.",
      },
      {
        role: "user",
        content:
          `Frage (${appLanguage}, unverändert lassen): ${question}\n` +
          `Ausgangsantwort, die vollständig ersetzt werden soll: ${answer}\n\n` +
          "Erzeuge genau eine neue Antwort passend zur gewählten Option. Die neue Antwort muss allein stehen können und darf die Ausgangsantwort nicht zusätzlich anhängen. " +
          "Halte die neue Antwort kurz genug für eine einzelne Karteikarte. " +
          `Schreibe die neue Antwort überwiegend in ${appLanguage}, weil die App-Oberfläche und die Lernhilfe aktuell in dieser Sprache sind. ` +
          `Nutze ${answerLanguage} nur für Zielbegriffe, Zitate, fremdsprachige Beispiele oder kurze Beispielsätze, wenn sie fachlich zur Karte gehören. ` +
          `Gib zusätzlich answerSpeechSegments aus. Diese Segmente müssen zusammen exakt den Antworttext ergeben. Verwende "${appLanguageCode}" für Erklärteile in ${appLanguage} und "${answerLanguageCode}" für Antwortteile in ${answerLanguage}. ` +
          "Übersetze einzelne fremdsprachige Beispielwörter oder kurze Beispielsätze nicht automatisch in die App-Sprache, sondern erhalte sie und markiere sie als eigenes Sprachsegment. " +
          instruction,
      },
    ],
  });
}

async function callOpenAI({
  schemaName,
  schema,
  input,
}: {
  schemaName: string;
  schema: Record<string, unknown>;
  input: Array<Record<string, string>>;
}) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${openAIAPIKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      input,
      reasoning: { effort: "minimal" },
      text: {
        format: {
          type: "json_schema",
          name: schemaName,
          schema,
          strict: true,
        },
      },
    }),
  });

  const payload = await response.json();

  if (!response.ok) {
    throw new Error(payload.error?.message ?? `OpenAI request failed with ${response.status}`);
  }

  const outputText = payload.output_text ?? payload.output
    ?.flatMap((item: { content?: Array<{ text?: string }> }) => item.content ?? [])
    .map((content: { text?: string }) => content.text ?? "")
    .join("");

  if (!outputText) {
    throw new Error("OpenAI returned no text output.");
  }

  return JSON.parse(outputText);
}

function clean(value: unknown): string {
  return String(value ?? "").trim();
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }

  return Math.min(Math.max(Math.round(value), min), max);
}

function profileForDifficulty(level: string): string {
  const normalizedLevel = level.toLocaleLowerCase("de-DE");

  if (normalizedLevel.includes("einsteiger")) {
    return "Sehr leicht. Nutze Alltagssprache, konkrete Beispiele und direkte Was-ist-/Woran-erkennt-man-Fragen. Keine Spezialbegriffe ohne Erklärung, keine Mehrschritt-Aufgaben.";
  }

  if (normalizedLevel.includes("grundlagen")) {
    return "Leicht bis mittel. Prüfe zentrale Begriffe, einfache Zusammenhänge und typische Standardbeispiele. Fachbegriffe sind erlaubt, müssen aber knapp verständlich bleiben.";
  }

  if (normalizedLevel.includes("fortgeschritten")) {
    return "Mittel bis anspruchsvoll. Frage nach Zusammenhängen, Ursachen, Unterschieden, Anwendungen und typischen Fehlern. Antworten dürfen Fachsprache und kurze Begründungen enthalten.";
  }

  if (normalizedLevel.includes("studium")) {
    return "Anspruchsvoll. Frage nach Konzepten, Herleitungen, Abgrenzungen, Modellannahmen, Spezialfällen und Transfer auf neue Situationen. Antworten sollen präzise Fachsprache verwenden.";
  }

  if (normalizedLevel.includes("experte")) {
    return "Sehr anspruchsvoll. Frage nach tiefem Verständnis, Gegenbeispielen, Grenzfällen, Beweisideen, Fehleranalyse, Vergleichen konkurrierender Konzepte und praktischen Konsequenzen. Antworten sollen knapp, aber fachlich dicht und differenziert sein.";
  }

  return "Passe die Karten an erwachsene Lernende an. Steigere den Anspruch über Verständnis, Anwendung, Transfer und präzise Begriffe statt über unnötig lange Texte.";
}

function instructionForAnswerMode(mode: string): string {
  switch (mode) {
  case "example":
    return "Ersetze die Antwort durch ein kurzes, konkretes Beispiel. Halte es so knapp, dass es auf eine Karteikarte passt.";
  case "mnemonic":
    return "Erzeuge einen einprägsamen Merksatz zur Frage. Wenn nötig, füge eine sehr kurze Erklärung an.";
  case "mini_quiz":
    return "Erzeuge ein Mini-Quiz mit genau einer kurzen Frage und einer kurzen Lösung. Format: Mini-Quiz: ... Lösung: ...";
  case "child_friendly":
    return "Erkläre die Antwort kindgerecht mit sehr einfachen Worten und einem anschaulichen Vergleich. Vermeide Babysprache.";
  case "exam_answer":
    return "Formuliere eine prüfungstaugliche Musterantwort: präzise, vollständig genug, fachlich sauber und ohne unnötige Ausschmückung.";
  case "simplify":
  default:
    return "Schreibe die Antwort einfacher und verständlicher. Nutze einfache Begriffe und nur ein kleines Beispiel, wenn es wirklich hilft.";
  }
}

function languageNameForCode(code: string): string {
  const normalizedCode = code.toLowerCase();

  if (normalizedCode.startsWith("en")) {
    return "Englisch";
  }

  if (normalizedCode.startsWith("es")) {
    return "Spanisch";
  }

  if (normalizedCode.startsWith("fr")) {
    return "Französisch";
  }

  if (normalizedCode.startsWith("it")) {
    return "Italienisch";
  }

  if (normalizedCode.startsWith("pt")) {
    return "Portugiesisch";
  }

  if (normalizedCode.startsWith("nl")) {
    return "Niederländisch";
  }

  if (normalizedCode.startsWith("sv")) {
    return "Schwedisch";
  }

  if (normalizedCode.startsWith("pl")) {
    return "Polnisch";
  }

  if (normalizedCode.startsWith("tr")) {
    return "Türkisch";
  }

  if (normalizedCode.startsWith("ru")) {
    return "Russisch";
  }

  if (normalizedCode.startsWith("uk")) {
    return "Ukrainisch";
  }

  if (normalizedCode.startsWith("ar")) {
    return "Arabisch";
  }

  if (normalizedCode.startsWith("zh")) {
    return "Chinesisch";
  }

  if (normalizedCode.startsWith("ja")) {
    return "Japanisch";
  }

  if (normalizedCode.startsWith("ko")) {
    return "Koreanisch";
  }

  return "Deutsch";
}

function normalizeLanguageCode(code: string): string {
  const normalizedCode = code.toLowerCase();

  if (normalizedCode.startsWith("en")) {
    return "en-US";
  }

  if (normalizedCode.startsWith("es")) {
    return "es-ES";
  }

  if (normalizedCode.startsWith("fr")) {
    return "fr-FR";
  }

  if (normalizedCode.startsWith("it")) {
    return "it-IT";
  }

  if (normalizedCode.startsWith("pt")) {
    return "pt-PT";
  }

  if (normalizedCode.startsWith("nl")) {
    return "nl-NL";
  }

  if (normalizedCode.startsWith("sv")) {
    return "sv-SE";
  }

  if (normalizedCode.startsWith("pl")) {
    return "pl-PL";
  }

  if (normalizedCode.startsWith("tr")) {
    return "tr-TR";
  }

  if (normalizedCode.startsWith("ru")) {
    return "ru-RU";
  }

  if (normalizedCode.startsWith("uk")) {
    return "uk-UA";
  }

  if (normalizedCode.startsWith("ar")) {
    return "ar-SA";
  }

  if (normalizedCode.startsWith("zh")) {
    return "zh-CN";
  }

  if (normalizedCode.startsWith("ja")) {
    return "ja-JP";
  }

  if (normalizedCode.startsWith("ko")) {
    return "ko-KR";
  }

  return "de-DE";
}

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}
