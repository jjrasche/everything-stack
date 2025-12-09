#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Debug logging
const LOG_FILE = path.join(__dirname, '..', 'hook-debug.log');
const log = (msg) => {
	const timestamp = new Date().toISOString();
	fs.appendFileSync(LOG_FILE, `${timestamp} - ${msg}\n`);
};

const BLOCKED_FILES = [
	/\.env$/,
	/\.key$/,
	/\.pem$/,
	/\.pfx$/,
	/settings\.local\.json$/
];

const respond = (decision, reason) => {
	const response = {
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: decision,
			permissionDecisionReason: reason
		}
	};
	log(`Responding: ${JSON.stringify(response)}`);
	console.log(JSON.stringify(response));
	process.exit(0);
};

const matchesAny = (str, patterns) => patterns.some(pattern => pattern.test(str));
const isBlockedFile = (filePath) => matchesAny(filePath, BLOCKED_FILES);

const handleWrite = (toolInput) => {
	const filePath = toolInput.file_path || '';
	log(`Write/Edit check for: ${filePath}`);
	if (isBlockedFile(filePath)) {
		return respond('deny', 'Blocked: Cannot write to sensitive files');
	}
	return respond('allow', 'Auto-approved write to non-sensitive file');
};

const handleBash = (toolInput) => {
	const cmd = toolInput.command || '';
	log(`Bash command: ${cmd}`);

	// Allow git rm --cached (untracking files, not deleting them)
	// This is safe - it only removes files from git's index, not the filesystem
	if (/git\s+rm\s+--cached/.test(cmd)) {
		log('Allowing git rm --cached (safe untrack operation)');
		return respond('allow', 'Auto-approved git untrack operation');
	}

	// Block dangerous delete commands on sensitive files
	// Extract file paths from the command and check each one
	if (/\brm\b|\bdel\b/.test(cmd)) {
		// Check if any blocked file pattern matches in the command
		for (const pattern of BLOCKED_FILES) {
			if (pattern.test(cmd)) {
				log(`Blocked: delete command targets sensitive file matching ${pattern}`);
				return respond('deny', 'Blocked: Cannot delete sensitive files');
			}
		}
	}

	return respond('allow', 'Auto-approved bash command');
};

const main = async () => {
	try {
		log('=== Hook invoked ===');

		// Read JSON from stdin
		const chunks = [];
		for await (const chunk of process.stdin) {
			chunks.push(chunk);
		}
		const inputJson = Buffer.concat(chunks).toString('utf8');
		log(`Stdin: ${inputJson}`);

		const input = JSON.parse(inputJson);
		const toolName = input.tool_name;
		const toolInput = input.tool_input || {};

		log(`Tool: ${toolName}`);
		log(`Input: ${JSON.stringify(toolInput)}`);

		// Handle Write and Edit with file blocking
		if (toolName === 'Write' || toolName === 'Edit') {
			return handleWrite(toolInput);
		}

		// Handle Bash commands
		if (toolName === 'Bash') {
			return handleBash(toolInput);
		}

		// Auto-approve read-only tools
		if (['Read', 'Glob', 'Grep', 'TodoWrite'].includes(toolName)) {
			return respond('allow', `Auto-approved ${toolName}`);
		}

		// Everything else asks user
		respond('ask', `Requires confirmation for ${toolName}`);

	} catch (error) {
		log(`ERROR: ${error.message}`);
		log(`Stack: ${error.stack}`);
		// On error, ask user (safe default)
		respond('ask', `Hook error: ${error.message}`);
	}
};

main();
