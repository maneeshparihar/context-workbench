/**
 * decode_eml.js
 * Usage: node HELPERS/decode_eml.js <path-to-eml-file>
 * 
 * Decodes base64-encoded body sections from an .eml file and prints them as plaintext.
 * Useful for extracting readable email conversation content from raw .eml exports.
 */
const fs = require('fs');
const path = require('path');

const emlPath = process.argv[2] || path.join(__dirname, '..', 'INPUTS', 'Re_ Olive Grove_ AI Calling & Data Automation Project.eml');

const content = fs.readFileSync(emlPath, 'utf-8');

// Find base64 sections between MIME boundaries
const regex = /Content-Transfer-Encoding: base64[\r\n\s]+([\s\S]*?)(?=\r?\n--_000)/g;
let match;
let sectionNum = 0;

while ((match = regex.exec(content)) !== null) {
  sectionNum++;
  const b64 = match[1].replace(/[\r\n\s]/g, '');
  try {
    const decoded = Buffer.from(b64, 'base64').toString('utf-8');
    console.log(`=== DECODED SECTION ${sectionNum} ===`);
    console.log(decoded);
    console.log(`=== END SECTION ${sectionNum} ===\n`);
  } catch (e) {
    console.error(`Error decoding section ${sectionNum}:`, e.message);
  }
}

if (sectionNum === 0) {
  console.log('No base64 sections found.');
}
