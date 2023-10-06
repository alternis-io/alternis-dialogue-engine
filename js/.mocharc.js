const path = require("path");

process.env.TS_NODE_PROJECT = path.join(__dirname, "tests/tsconfig.json");

module.exports = {
  require: [
    "ts-node/register",
    "source-map-support/register",
  ],
  timeout: 20_000,
};
