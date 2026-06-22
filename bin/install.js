#!/usr/bin/env node
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const skillsRoot = join(repoRoot, "skills");
const args = process.argv.slice(2);
const force = args.includes("--force");
const list = args.includes("--list");
const help = args.includes("--help") || args.includes("-h");

function usage() {
  console.log(`Usage:
  npx agent-skills [--skill <name>] [--force]
  npx agent-skills --list

Options:
  --skill <name>  Install one skill. Defaults to all bundled skills.
  --force         Overwrite existing installed skills.
  --list          List bundled skills.
`);
}

function readSkillNames() {
  return readdirSync(skillsRoot)
    .filter((name) => statSync(join(skillsRoot, name)).isDirectory())
    .sort();
}

function getOptionValue(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  return args[index + 1] || null;
}

if (help) {
  usage();
  process.exit(0);
}

const skillNames = readSkillNames();

if (list) {
  for (const skillName of skillNames) {
    console.log(skillName);
  }
  process.exit(0);
}

const requestedSkill = getOptionValue("--skill");
const selectedSkills = requestedSkill ? [requestedSkill] : skillNames;
const codexHome = process.env.CODEX_HOME || join(homedir(), ".codex");
const installRoot = join(codexHome, "skills");

mkdirSync(installRoot, { recursive: true });

for (const skillName of selectedSkills) {
  const source = join(skillsRoot, skillName);
  const target = join(installRoot, skillName);

  if (!existsSync(source)) {
    console.error(`Unknown skill: ${skillName}`);
    console.error(`Available skills: ${skillNames.join(", ") || "(none)"}`);
    process.exit(1);
  }

  if (existsSync(target)) {
    if (!force) {
      console.error(`${skillName} already exists at ${target}. Use --force to overwrite.`);
      process.exit(1);
    }
    rmSync(target, { recursive: true, force: true });
  }

  cpSync(source, target, { recursive: true });
  console.log(`Installed ${skillName} to ${target}`);
}
