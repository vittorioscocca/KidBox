module.exports = {
  env: {
    es2022: true,
    node: true,
  },
  parserOptions: {
    // Il runtime è Node 22 (package.json → engines.node). Con 2020 il parser
    // si fermava sul separatore numerico di `5_000_000` e ABBANDONAVA l'intero
    // index.js: il file non veniva lintato affatto.
    "ecmaVersion": 2022,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
    // `valid-jsdoc` è deprecato e rimosso da eslint core: arriva solo da
    // eslint-config-google e non sa leggere la sintassi di tipo moderna —
    // `import("firebase-admin/messaging").SendResponse[]` e i record inline
    // `{{plan: string|null, ...}}` glielo fanno segnalare come "syntax error".
    // Le annotazioni sono corrette: è la regola a essere indietro.
    "valid-jsdoc": "off",
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
