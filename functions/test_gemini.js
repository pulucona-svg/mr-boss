const { EnvConfig } = require("./lib/config/env_config");
EnvConfig.runStartupVerificationAndReport();

const apiKey = EnvConfig.getApiKey("gemini");
console.log("Gemini Key:", EnvConfig.maskSecret(apiKey));

async function testGemini(model) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: "Hello, list 2 news events in JSON format." }] }],
      generationConfig: { responseMimeType: "application/json" },
    }),
  });
  console.log(`Model: ${model} -> Status: ${res.status}`);
  if (res.ok) {
    const json = await res.json();
    console.log("SUCCESS:", JSON.stringify(json, null, 2));
  } else {
    console.log("ERROR:", await res.text());
  }
}

async function run() {
  await testGemini("gemini-3.6-flash");
}

run();
