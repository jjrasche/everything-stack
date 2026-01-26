#!/usr/bin/env node
/**
 * Supabase CLI Operations
 *
 * Usage: node scripts/supabase-cli.js <command> [args]
 *
 * Commands:
 *   schema              Run scripts/setup_supabase.sql
 *   tables              List all public tables
 *   describe <table>    Show table columns
 *   query "<sql>"       Run ad-hoc SQL
 *   bucket <name>       Create storage bucket with dev policy
 *   buckets             List storage buckets
 *   policies <table>    Show RLS policies for table
 *
 * Requires .env with SUPABASE_URL and SUPABASE_DATABASE_PASSWORD
 */

const fs = require('fs');
const path = require('path');

// Load .env from current working directory or project root
function loadEnv() {
  const envPaths = [
    path.join(process.cwd(), '.env'),           // Current directory
    path.join(process.cwd(), '..', '.env'),     // Parent directory
    path.join(__dirname, '..', '.env'),         // Relative to script
    path.join(__dirname, '..', '..', '.env'),
  ];

  for (const envPath of envPaths) {
    if (fs.existsSync(envPath)) {
      const content = fs.readFileSync(envPath, 'utf8');
      content.split('\n').forEach(line => {
        const match = line.match(/^([^#=]+)=(.*)$/);
        if (match) {
          process.env[match[1].trim()] = match[2].trim();
        }
      });
      return true;
    }
  }
  return false;
}

loadEnv();

// Extract project ref from URL
function getProjectRef() {
  const url = process.env.SUPABASE_URL;
  if (!url) {
    console.error('Error: SUPABASE_URL not set in .env');
    process.exit(1);
  }
  const match = url.match(/https:\/\/(.+)\.supabase\.co/);
  return match ? match[1] : null;
}

// Create database client
async function createClient() {
  const { Client } = require('pg');
  const projectRef = getProjectRef();
  const password = process.env.SUPABASE_DATABASE_PASSWORD;

  if (!password) {
    console.error('Error: SUPABASE_DATABASE_PASSWORD not set in .env');
    process.exit(1);
  }

  const client = new Client({
    host: `db.${projectRef}.supabase.co`,
    port: 5432,
    database: 'postgres',
    user: 'postgres',
    password: password,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();
  return client;
}

// Commands
const commands = {
  async schema() {
    // Look for setup_supabase.sql in multiple locations
    const sqlPaths = [
      path.join(process.cwd(), 'scripts', 'setup_supabase.sql'),
      path.join(process.cwd(), 'setup_supabase.sql'),
      path.join(__dirname, 'setup_supabase.sql'),
    ];

    const sqlPath = sqlPaths.find(p => fs.existsSync(p));
    if (!sqlPath) {
      console.error('Error: setup_supabase.sql not found in scripts/ or current directory');
      process.exit(1);
    }

    const sql = fs.readFileSync(sqlPath, 'utf8');
    const client = await createClient();

    console.log('Running setup_supabase.sql...');
    const result = await client.query(sql);
    const commands = Array.isArray(result) ? result.map(r => r.command) : [result.command];
    console.log('Executed:', commands.filter(Boolean).join(', '));

    await client.end();
  },

  async tables() {
    const client = await createClient();

    const { rows } = await client.query(`
      SELECT t.table_name,
             (SELECT count(*) FROM information_schema.columns c WHERE c.table_name = t.table_name) as columns,
             (SELECT count(*) FROM pg_policies p WHERE p.tablename = t.table_name) as policies
      FROM information_schema.tables t
      WHERE t.table_schema = 'public'
      ORDER BY t.table_name
    `);

    console.log('Public tables:');
    if (rows.length === 0) {
      console.log('  (none)');
    } else {
      rows.forEach(r => console.log(`  - ${r.table_name} (${r.columns} cols, ${r.policies} policies)`));
    }

    await client.end();
  },

  async describe(tableName) {
    if (!tableName) {
      console.error('Usage: supabase-cli.js describe <table>');
      process.exit(1);
    }

    const client = await createClient();

    const { rows } = await client.query(`
      SELECT column_name, data_type, is_nullable, column_default
      FROM information_schema.columns
      WHERE table_name = $1
      ORDER BY ordinal_position
    `, [tableName]);

    if (rows.length === 0) {
      console.log(`Table '${tableName}' not found`);
    } else {
      console.log(`Table: ${tableName}`);
      rows.forEach(r => {
        const nullable = r.is_nullable === 'NO' ? 'NOT NULL' : '';
        const def = r.column_default ? `DEFAULT ${r.column_default.substring(0, 30)}` : '';
        console.log(`  ${r.column_name.padEnd(20)} ${r.data_type.padEnd(15)} ${nullable} ${def}`);
      });
    }

    await client.end();
  },

  async query(sql) {
    if (!sql) {
      console.error('Usage: supabase-cli.js query "<sql>"');
      process.exit(1);
    }

    const client = await createClient();
    const result = await client.query(sql);

    if (result.rows?.length) {
      console.table(result.rows);
    } else {
      console.log('Result:', result.command, result.rowCount !== null ? `(${result.rowCount} rows)` : '');
    }

    await client.end();
  },

  async bucket(name) {
    if (!name) {
      console.error('Usage: supabase-cli.js bucket <name>');
      process.exit(1);
    }

    const client = await createClient();

    // Create bucket
    await client.query(`
      INSERT INTO storage.buckets (id, name, public, file_size_limit)
      VALUES ($1, $1, false, 52428800)
      ON CONFLICT (id) DO NOTHING
    `, [name]);

    // Create dev policy
    try {
      await client.query(`
        CREATE POLICY "Allow all ${name} (dev)"
        ON storage.objects
        FOR ALL
        USING (bucket_id = $1)
        WITH CHECK (bucket_id = $1)
      `, [name]);
      console.log(`Bucket '${name}' created with dev policy`);
    } catch (e) {
      if (e.message.includes('already exists')) {
        console.log(`Bucket '${name}' already exists`);
      } else {
        throw e;
      }
    }

    await client.end();
  },

  async buckets() {
    const client = await createClient();

    const { rows } = await client.query(`
      SELECT id, name, public, file_size_limit
      FROM storage.buckets
      ORDER BY name
    `);

    console.log('Storage buckets:');
    if (rows.length === 0) {
      console.log('  (none)');
    } else {
      rows.forEach(r => {
        const size = r.file_size_limit ? `${Math.round(r.file_size_limit / 1024 / 1024)}MB` : 'unlimited';
        console.log(`  - ${r.name} (${r.public ? 'public' : 'private'}, ${size})`);
      });
    }

    await client.end();
  },

  async policies(tableName) {
    if (!tableName) {
      console.error('Usage: supabase-cli.js policies <table>');
      process.exit(1);
    }

    const client = await createClient();

    const { rows } = await client.query(`
      SELECT policyname, permissive, roles, cmd, qual, with_check
      FROM pg_policies
      WHERE tablename = $1
    `, [tableName]);

    console.log(`RLS policies for '${tableName}':`);
    if (rows.length === 0) {
      console.log('  (none)');
    } else {
      rows.forEach(r => {
        console.log(`  - ${r.policyname}`);
        console.log(`    Command: ${r.cmd}, Permissive: ${r.permissive}`);
        console.log(`    Roles: ${r.roles}`);
        if (r.qual) console.log(`    USING: ${r.qual.substring(0, 50)}`);
      });
    }

    await client.end();
  },

  help() {
    console.log(`
Supabase CLI Operations

Usage: node scripts/supabase-cli.js <command> [args]

Commands:
  schema              Run scripts/setup_supabase.sql
  tables              List all public tables
  describe <table>    Show table columns
  query "<sql>"       Run ad-hoc SQL
  bucket <name>       Create storage bucket with dev policy
  buckets             List storage buckets
  policies <table>    Show RLS policies for table
  help                Show this help

Examples:
  node scripts/supabase-cli.js schema
  node scripts/supabase-cli.js tables
  node scripts/supabase-cli.js describe entities
  node scripts/supabase-cli.js query "SELECT count(*) FROM entities"
  node scripts/supabase-cli.js bucket avatars
`);
  }
};

// Main
async function main() {
  const [,, command, ...args] = process.argv;

  if (!command || command === 'help' || command === '--help') {
    commands.help();
    process.exit(0);
  }

  if (!commands[command]) {
    console.error(`Unknown command: ${command}`);
    commands.help();
    process.exit(1);
  }

  try {
    await commands[command](...args);
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
}

main();
