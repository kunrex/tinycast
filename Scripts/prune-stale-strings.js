#!/usr/bin/env node
// Remove compiler-marked stale entries without reformatting surviving translations.
"use strict";

const fs = require("fs");
const path = require("path");
const file = path.join(__dirname, "../Tinycast/Resources/Localizable.xcstrings");
const source = fs.readFileSync(file, "utf8");
let removed = 0;
const result = source.replace(/^    "(?:[^"\\]|\\.)*" : \{\n[\s\S]*?^    \},?\n/gm, (block) => {
  const entry = JSON.parse(`{${block.trim().replace(/,$/, "")}}`);
  if (Object.values(entry)[0].extractionState !== "stale") return block;
  console.log(`Removing stale string: ${Object.keys(entry)[0]}`);
  removed++;
  return "";
}).replace(/,\n(  \})/, "\n$1");
JSON.parse(result);
if (removed > 0) fs.writeFileSync(file, result);
console.log(`Removed ${removed} stale string(s).`);
