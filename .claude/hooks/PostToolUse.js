#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Log to project .claude directory
const PROJECT_CLAUDE_DIR = path.join(__dirname, '..');
const LOG_FILE = path.join(PROJECT_CLAUDE_DIR, 'tool-use.log');

const log = (msg) => {
	const timestamp = new Date().toISOString();
	fs.appendFileSync(LOG_FILE, `${timestamp} - ${msg}\n`);
};

try {
	const [toolName, toolInputJson, toolOutputJson] = process.argv.slice(2);

	log('=== Tool Executed Successfully ===');
	log(`Tool: ${toolName}`);

	// Log input (truncate if too long)
	if (toolInputJson && toolInputJson !== 'undefined') {
		try {
			const input = JSON.parse(toolInputJson);
			const inputStr = JSON.stringify(input);
			log(`Input: ${inputStr.length > 200 ? inputStr.substring(0, 200) + '...' : inputStr}`);
		} catch (e) {
			log(`Input (raw): ${toolInputJson.substring(0, 200)}`);
		}
	}

	// Log output size (not full content, just metadata)
	if (toolOutputJson && toolOutputJson !== 'undefined') {
		try {
			const output = JSON.parse(toolOutputJson);
			log(`Output: ${typeof output} (${JSON.stringify(output).length} chars)`);
		} catch (e) {
			log(`Output: Parse error`);
		}
	}

	log('');

} catch (error) {
	log(`ERROR in PostToolUse: ${error.message}`);
}

// PostToolUse hooks don't need to respond
process.exit(0);
