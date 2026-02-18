const fs = require('fs');
const path = require('path');
const dir = path.dirname(__filename || process.argv[1]);
const j = JSON.parse(fs.readFileSync(path.join(__dirname, 'extractions', 'conv_3475558a.json'), 'utf8'));
let issues = [];
j.extraction.forEach(t => {
  const allIds = t.sentences.map(s => s.id);
  const spanIds = t.spans.flatMap(sp => sp.sentenceIds);
  const missing = allIds.filter(id => !spanIds.includes(id));
  const extra = spanIds.filter(id => !allIds.includes(id));
  const dupes = spanIds.filter((id, i) => spanIds.indexOf(id) !== i);
  if (missing.length) issues.push('Turn ' + t.turnIndex + ': missing from spans: ' + missing.join(','));
  if (extra.length) issues.push('Turn ' + t.turnIndex + ': in spans but not sentences: ' + extra.join(','));
  if (dupes.length) issues.push('Turn ' + t.turnIndex + ': duplicate in spans: ' + dupes.join(','));
});
if (issues.length === 0) {
  console.log('FULL COVERAGE: all sentences accounted for, no gaps, no overlaps');
} else {
  issues.forEach(i => console.log(i));
}

// Also check sourceIds in propositions reference valid sentence IDs
let propIssues = [];
j.extraction.forEach(t => {
  const allIds = t.sentences.map(s => s.id);
  t.propositions.forEach((p, idx) => {
    const bad = (p.sourceIds || []).filter(id => !allIds.includes(id));
    if (bad.length) propIssues.push('Turn ' + t.turnIndex + ' prop ' + idx + ': invalid sourceIds: ' + bad.join(','));
  });
});
if (propIssues.length === 0) {
  console.log('PROPOSITION SOURCES: all sourceIds reference valid sentences');
} else {
  propIssues.forEach(i => console.log(i));
}

console.log('\nSummary: ' + j.extraction.length + ' turns, ' + j.propositionCount + ' propositions declared, ' +
  j.extraction.reduce((sum, t) => sum + t.propositions.length, 0) + ' propositions actual');
