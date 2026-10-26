# AbsenAAJ — Project Instructions

## 1. Project Context
- This is a Laravel application running in Docker.
- The application container is `absenaaj-app`.
- The web container is `absenaaj-nginx`.
- Use the installed PHP and Laravel versions; verify them before relying on version-specific behavior.
- Keep project source code in this repository and durable cross-project notes in `/data/obsidian`.

## 2. Before Starting Work
1. Read `/data/obsidian/HOME.md` if available.
2. Find and read the relevant AbsenAAJ project notes in `/data/obsidian`.
3. Check `git status --short --branch` before editing.
4. Inspect the actual code, tests, configuration, and installed package versions.
5. Treat old notes as context, not proof of current application state.
6. Read applicable rules in `CLAUDE.md` and `.claude/skills/` when relevant. These files are references; do not assume OpenCode automatically activates Claude Code skills.

## 3. Commands and Runtime
- Run PHP and Artisan commands through the application container:
  `docker exec absenaaj-app php artisan <command>`
- Run Composer commands through the application container:
  `docker exec absenaaj-app composer <command>`
- Run the test suite with:
  `docker exec absenaaj-app php artisan test`
- Run only the narrowest relevant tests first, then the full suite when appropriate.
- Never run `migrate:fresh`, reset a database, or run destructive database commands against application data.
- Do not assume the OpenCode container has PHP, Composer, Docker CLI, or access to the Docker socket.
- Do not install or update dependencies without a clear reason and user approval.

## 4. Implementation and Verification
- Follow existing Laravel conventions and reuse established application patterns.
- Add or update tests for meaningful behavior changes.
- Verify changes with relevant tests, formatting checks, or other appropriate commands.
- Report the commands actually run and their results.
- Distinguish verified facts from assumptions and recommendations.

## 5. Security and Data Protection
- Never copy credentials, tokens, private keys, cookies, or `.env` contents into notes, logs, or commits.
- Do not weaken authentication, authorization, validation, or file access controls without explicit justification.
- Do not deploy, commit, push, delete, overwrite user data, or perform destructive actions without user approval.
- Review dependency and configuration changes before committing them.

## 6. Shared Knowledge Base
- Use `/data/obsidian` for durable project notes and session summaries.
- Keep AbsenAAJ notes separate from unrelated projects.
- After meaningful work, record the objective, changes, verification, decisions, remaining issues, and next steps.
- Update `/data/obsidian/Tasks/NEXT.md` when project priorities change.
- Do not create unnecessary notes for trivial work.
- Never store secrets in Obsidian.

## 7. Completion Summary
At the end of substantive work, report:
- What changed and why.
- Files affected.
- Tests and checks actually executed.
- Any unresolved issues or risks.
- The next recommended step.
